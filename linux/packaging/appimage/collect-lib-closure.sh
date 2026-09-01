#!/usr/bin/env bash
# Collect the dynamic-library closure of the given libraries into <libdir>
# and rewrite RUNPATH to $ORIGIN so each bundled library resolves its own
# dependencies from inside the AppImage, without a global LD_LIBRARY_PATH.
#
# Usage:
#   collect-lib-closure.sh [--src-prefix DIR] <libdir> <libname> [<libname> ...]
#
# --src-prefix DIR: a isolated build prefix (e.g. /opt/reposeed/extracted/usr)
#   whose libraries must be preferred over the host/system ones. This lets us
#   bundle the official distro libmpv.so.2 (and its FFmpeg/libass closure)
#   extracted from repository packages instead of the host libmpv2. If omitted,
#   it falls back to ldconfig/system search.
#
# The AppImage stays self-contained for the media stack (libmpv.so.2) and the
# system tray (libayatana-appindicator3.so.1) while delegating glibc, GTK and
# hardware/driver libraries to the host distro.
#
# Multi-distro scope: the multimedia stack bundled here is self-contained, so
# users do NOT need to install mpv, libmpv, FFmpeg, libass or HarfBuzz to run
# the AppImage. The AppImage still keeps a minimal set of host dependencies,
# namely glibc, the ALSA/PulseAudio audio stack and the OpenSSL runtime, along
# with the graphical/GTK components that Flutter already uses. The mpv
# executable is never packaged, only libmpv and its media libraries.

set -euo pipefail

SRC_PREFIX=""
if [[ "$1" == "--src-prefix" ]]; then
  SRC_PREFIX="$2"
  shift 2
  if [[ -z "$SRC_PREFIX" || ! -d "$SRC_PREFIX" ]]; then
    echo "::error::--src-prefix requires an existing directory" >&2
    exit 1
  fi
fi

LIBDIR="${1:?usage: collect-lib-closure.sh [--src-prefix DIR] <libdir> <libname> [<libname> ...]}"
shift

# Base system + toolchain libs that every distro already provides. NOT bundled.
# openssl (libssl/libcrypto) is declared as a host dependency by the
# .deb/.rpm/.pkg packages (only reached through libavformat's https) and is
# ubiquitous on glibc distros, so it stays on the host too.
BASE_SKIP='^(ld-linux|libc\.so|libm\.so|libdl\.so|libpthread|librt\.so|libstdc\+\+|libgcc_s|libresolv|libnsl|libutil|libanl|libcrypt|libz\.so|libssl\.so|libcrypto\.so)'

# Hardware/driver host glue that must never be packaged into the AppImage.
# These stay on the host (NVIDIA/Mesa/DRI loaders/ICDs resolve at runtime).
# NOTE: libplacebo is intentionally NOT here: it is a hard DT_NEEDED of the
# official libmpv.so.2 and its SONAME diverges across distros (.349/.351/.360),
# so it must be BUNDLED (alone) to keep the AppImage portable. Its own
# Vulkan/lcms2 dependencies remain on the host.
# The GTK/GLib UI family, the audio stack and the crypto/TLS stack are also
# delegated to the host: the app is a GTK/Flutter application that already
# provides GTK/GLib, and the audio/graphics drivers are system components.
HOST_SKIP='^(libGL|libEGL|libGLX|libOpenGL|libvulkan|libdrm|libgbm|libva|libvdpau|libnvidia|libcuda|libnvcuvid|libX11|libXext|libXrandr|libxcb|libwayland|libsndfile|libasound\.so|libpulse|libjack|libpipewire|libsndio|libopenal|libcaca|libSDL)'
# GTK/GLib/rendering UI family -> HOST (the Flutter/GTK app needs it anyway).
UI_SKIP='^(libgtk-3|libgdk-3|libglib|libgobject|libgio-2|libgmodule|libgthread|libgdk_pixbuf|libpango|libpangocairo|libpangoft2|libpixman-1|libcairo|libcairo-gobject|librsvg|libffi|libpcre2|libexpat|libgraphene|libepoxy|libwayland-cursor|libwayland-egl)'
# Crypto / TLS / numeric / system libs pulled by the closure -> HOST.
SEC_SKIP='^(libssl|libcrypto|libmbedcrypto|libgnutls|libnettle|libhogweed|libgmp|libidn2|libunistring|libp11-kit|libtasn1|libmd|libbsd|libcap|libblas|liblapack|libgfortran|libfftw3|libgomp|libatomic|libnuma|libxml2|libsystemd|libselinux|libacl|libattr)'

declare -A RESOLVED=()
declare -A BUNDLED=()
declare -A SRC_RESOLVED=()

skip_lib() {
  local n="$1"
  [[ "$n" =~ $BASE_SKIP ]] && return 0
  [[ "$n" =~ $HOST_SKIP ]] && return 0
  [[ "$n" =~ $UI_SKIP ]] && return 0
  [[ "$n" =~ $SEC_SKIP ]] && return 0
  return 1
}

resolve_in_prefix() {
  local soname="$1" base
  if [[ -z "$SRC_PREFIX" ]]; then
    return 1
  fi
  for base in "$SRC_PREFIX/lib/x86_64-linux-gnu" "$SRC_PREFIX/lib"; do
    if [[ -e "$base/$soname" ]]; then
      printf '%s\n' "$(readlink -f "$base/$soname")"
      return 0
    fi
  done
  return 1
}

resolve() {
  local soname="$1" path=""
  if [[ -n "${RESOLVED[$soname]:-}" ]]; then
    return
  fi
  if path="$(resolve_in_prefix "$soname")"; then
    SRC_RESOLVED["$soname"]=1
  elif path="$(ldconfig -p 2>/dev/null | awk -v n="$soname" '$1 == n { print $NF; exit }')"; then
    :
  else
    for cand in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
      if [[ -e "$cand/$soname" ]]; then
        path="$(readlink -f "$cand/$soname")"
        break
      fi
    done
  fi
  RESOLVED["$soname"]="$path"
}

needed_libs() {
  objdump -p "$1" 2>/dev/null | awk '/NEEDED/ { print $2 }'
}

bundle() {
  local soname="$1" path dep
  if skip_lib "$soname"; then
    echo "  [skip] $soname (host/base)"
    return
  fi
  if [[ -n "${BUNDLED[$soname]:-}" ]]; then
    return
  fi
  resolve "$soname"
  path="${RESOLVED[$soname]:-}"
  if [[ -z "$path" ]]; then
    echo "::warning::cannot resolve $soname"
    return
  fi
  BUNDLED["$soname"]=1
  echo "  [bundle] $soname -> $path"
  for dep in $(needed_libs "$path"); do
    bundle "$dep"
  done
  install -Dm755 "$path" "$LIBDIR/$soname"
  patchelf --set-rpath '$ORIGIN' "$LIBDIR/$soname"
}

mkdir -p "$LIBDIR"
echo "Collecting closures into $LIBDIR"
if [[ -n "$SRC_PREFIX" ]]; then
  echo "  source prefix: $SRC_PREFIX"
fi
for target in "$@"; do
  bundle "$target"
done
echo "Bundled libraries:"
ls -la "$LIBDIR"