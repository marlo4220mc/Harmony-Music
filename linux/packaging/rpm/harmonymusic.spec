Name: harmonymusic
Version: __VERSION__
Release: 1%{?dist}
Summary: An application to stream Music
Group: Application/Multimedia
Vendor: marlo4220mc
Packager: marlo4220mc
License: GPLv3
URL: https://github.com/marlo4220mc/Harmony-Music
Requires: mpv-libs, libayatana-appindicator-gtk3
BuildArch: x86_64

%description
A cross platform app for music streaming.

%prep

%build

%install
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_datadir}/harmonymusic
mkdir -p %{buildroot}%{_datadir}/applications
mkdir -p %{buildroot}%{_datadir}/pixmaps
cp -r harmonymusic/* %{buildroot}%{_datadir}/harmonymusic
ln -s %{_datadir}/harmonymusic/harmonymusic %{buildroot}%{_bindir}/harmonymusic
cp -r harmonymusic.desktop %{buildroot}%{_datadir}/applications/harmonymusic.desktop
cp -r harmonymusic.png %{buildroot}%{_datadir}/pixmaps/harmonymusic.png

%post
update-mime-database %{_datadir}/mime &> /dev/null || :

%postun
update-mime-database %{_datadir}/mime &> /dev/null || :

%files
%{_bindir}/harmonymusic
%{_datadir}/harmonymusic
%{_datadir}/applications/harmonymusic.desktop
%{_datadir}/pixmaps/harmonymusic.png

%defattr(-,root,root)