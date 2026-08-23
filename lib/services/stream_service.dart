import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// The only client that still returns downloadable media URLs. In August 2026
/// YouTube began gating the others behind a proof-of-origin token: extraction
/// succeeds, then the URL serves ~1MB from offset 0 and answers any
/// open-ended read - which is what a player issues - with 403.
/// yt-dlp added this client for the same reason; it requires neither a JS
/// player nor a PO token, so extraction stays on a background isolate.
/// Values mirror yt-dlp's `visionos` INNERTUBE_CLIENTS entry (also vendored by
/// bozmund/Harmony-Music); if playback starts 403ing again, re-check them
/// against upstream first.
const _visionosClient = YoutubeApiClient(
  {
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'hl': 'en',
      }
    },
  },
  'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
);

class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider(
      {required this.playable, this.audioFormats, this.statusMSG = ""});

  static Future<StreamProvider> fetch(String videoId) async {
    final yt = YoutubeExplode();

    try {
      // VISIONOS only. Every other client's URLs are now proof-of-origin
      // gated: they extract fine, then 403 the moment a player asks for the
      // whole file. A fallback chain cannot help - the only thing a gated
      // client can return is URLs that do not play - and each extra client
      // costs a full player-response fetch plus retries per song.
      final res = await yt.videos.streamsClient.getManifest(videoId,
          ytClients: [_visionosClient]);
      final audio = res.audioOnly;
      if (audio.isEmpty) {
        return StreamProvider(playable: false, statusMSG: "networkError");
      }
      return StreamProvider(
          playable: true,
          statusMSG: "OK",
          audioFormats: audio
              .map((e) => Audio(
                  itag: e.tag,
                  audioCodec:
                      e.audioCodec.contains('mp') ? Codec.mp4a : Codec.opus,
                  bitrate: e.bitrate.bitsPerSecond,
                  duration: e.duration ?? 0,
                  loudnessDb: e.loudnessDb,
                  url: e.url.toString(),
                  size: e.size.totalBytes))
              .toList());
    } catch (e) {
      if (e is SocketException) {
        return StreamProvider(
          playable: false,
          statusMSG: "networkError",
        );
      } else if (e is VideoUnplayableException) {
        return StreamProvider(
          playable: false,
          statusMSG: e.message.isEmpty ? "Song is unplayable" : e.message,
        );
      } else if (e is VideoRequiresPurchaseException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song requires purchase",
        );
      } else if (e is VideoUnavailableException) {
        return StreamProvider(
          playable: false,
          statusMSG: "Song is unavailable",
        );
      } else if (e is YoutubeExplodeException) {
        return StreamProvider(
          playable: false,
          statusMSG: e.message,
        );
      } else {
        return StreamProvider(
          playable: false,
          statusMSG: "Unknown error occurred",
        );
      }
    } finally {
      yt.close();
    }
  }

  /// Picks the first itag in [preference] that the manifest actually offers,
  /// instead of choosing by position in the manifest (a library-side reorder
  /// must not change which codec the app plays).
  Audio? _preferred(List<int> preference) {
    final formats = audioFormats;
    if (formats == null || formats.isEmpty) return null;
    for (final itag in preference) {
      for (final format in formats) {
        if (format.itag == itag) return format;
      }
    }
    return formats.first;
  }

  Audio? get highestQualityAudio => _preferred(const [140, 251]);

  Audio? get highestBitrateMp4aAudio => _preferred(const [140, 139]);

  Audio? get highestBitrateOpusAudio => _preferred(const [251, 250]);

  Audio? get lowQualityAudio => _preferred(const [249, 139]);

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson()
    };
  }
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;
  Audio(
      {required this.itag,
      required this.audioCodec,
      required this.bitrate,
      required this.duration,
      required this.loudnessDb,
      required this.url,
      required this.size});

  Map<String, dynamic> toJson() => {
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size
      };

  factory Audio.fromJson(json) => Audio(
      audioCodec: (json["audioCodec"] as String).contains("mp4a")
          ? Codec.mp4a
          : Codec.opus,
      itag: json['itag'],
      duration: json["approxDurationMs"] ?? 0,
      bitrate: json["bitrate"] ?? 0,
      loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
      url: json['url'],
      size: json["size"] ?? 0);
}

enum Codec { mp4a, opus }
