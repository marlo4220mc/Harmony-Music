// ignore_for_file: constant_identifier_names

import 'dart:convert';
import 'package:audio_service/audio_service.dart';
import 'package:dio/dio.dart';
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';

import '/models/album.dart';
import '/services/utils.dart';
import '../utils/helper.dart';
import 'constant.dart';
import 'continuations.dart';
import 'nav_parser.dart';

enum AudioQuality {
  Low,
  High,
}

class MusicServices extends getx.GetxService {
  final Map<String, String> _headers = {
    'user-agent': userAgent,
    'accept': '*/*',
    'accept-encoding': 'gzip, deflate',
    'content-type': 'application/json',
    'content-encoding': 'gzip',
    'origin': domain,
    'cookie': 'CONSENT=YES+1',
  };

  final Map<String, dynamic> _context = {
    'context': {
      'client': {
        "clientName": "WEB_REMIX",
        "clientVersion": "1.20230213.01.00",
      },
      'user': {}
    }
  };

  @override
  void onInit() {
    init();
    super.onInit();
  }

  final dio = Dio();

  Future<void> init() async {
    //check visitor id in data base, if not generate one , set lang code
    final date = DateTime.now();
    _context['context']['client']['clientVersion'] =
        "1.${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}.01.00";
    final signatureTimestamp = getDatestamp() - 1;
    _context['playbackContext'] = {
      'contentPlaybackContext': {'signatureTimestamp': signatureTimestamp},
    };

    final appPrefsBox = Hive.box('AppPrefs');
    hlCode = appPrefsBox.get('contentLanguage') ?? "en";
    if (appPrefsBox.containsKey('visitorId')) {

  final visitorData =
      appPrefsBox.get("visitorId");

  print(
    "VISITOR DATA: $visitorData",
  );

  final isInvalidVisitor =
      visitorData == null ||
      visitorData is! Map ||
      !visitorData.containsKey("id") ||
      !visitorData.containsKey("exp");

  if (isInvalidVisitor) {

    print(
      "INVALID visitorId -> deleting",
    );

    await appPrefsBox.delete(
      "visitorId",
    );

  } else if (
      !isExpired(
        epoch: visitorData['exp'],
      )) {

    _headers['X-Goog-Visitor-Id'] =
        visitorData['id'];

    print('[HarmonySearch] init: loaded visitorId from DB=$visitorData[id]');

    appPrefsBox.put(
      "visitorId",
      {
        'id': visitorData['id'],
        'exp':
            DateTime.now()
                    .millisecondsSinceEpoch ~/
                1000 +
            2590200
      },
    );

    return;

  } else {

    print(
      "EXPIRED visitorId -> deleting",
    );

    await appPrefsBox.delete(
      "visitorId",
    );
  }
}

    final visitorId = await genrateVisitorId();
    if (visitorId != null) {
      _headers['X-Goog-Visitor-Id'] = visitorId;
      print('[HarmonySearch] init: generated new visitorId=$visitorId');
      appPrefsBox.put("visitorId", {
        'id': visitorId,
        'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 2592000
      });
      return;
    }
    // not able to generate in that case
    _headers['X-Goog-Visitor-Id'] =
        "CgttN24wcmd5UzNSWSi2lvq2BjIKCgJKUBIEGgAgYQ%3D%3D";
    print('[HarmonySearch] init: using HARDCODED fallback visitorId=${_headers['X-Goog-Visitor-Id']}');
  }

  set hlCode(String code) {
    _context['context']['client']['hl'] = code;
  }

  Future<String?> genrateVisitorId() async {
    try {
      final response =
          await dio.get(domain, options: Options(headers: _headers));
      print('[HarmonySearch] genrateVisitorId: status=${response.statusCode} type=${response.data.runtimeType} len=${response.data.toString().length}');
      final reg = RegExp(r'ytcfg\.set\s*\(\s*({.+?})\s*\)\s*;');
      final matches = reg.firstMatch(response.data.toString());
      String? visitorId;
      if (matches != null) {
        final ytcfg = json.decode(matches.group(1).toString());
        visitorId = ytcfg['VISITOR_DATA']?.toString();
        print('[HarmonySearch] genrateVisitorId: found in HTML: $visitorId');
      } else {
        print('[HarmonySearch] genrateVisitorId: ytcfg pattern NOT FOUND in response');
      }
      return visitorId;
    } catch (e) {
      print('[HarmonySearch] genrateVisitorId: FAILED with $e');
      return null;
    }
  }

  Future<Response> _sendRequest(String action, Map<dynamic, dynamic> data,
      {additionalParams = "", int retryCount = 0}) async {
    if (retryCount > 3) {
      printINFO("Max retries reached for $action");
      throw NetworkError();
    }
    final url = "$baseUrl$action$fixedParms$additionalParams";
    final visitorId = _headers['X-Goog-Visitor-Id'] ?? '(not set)';
    print('[HarmonySearch] REQ action=$action retry=$retryCount visitorId=$visitorId');
    print('[HarmonySearch] REQ url=$url');
    try {
      final response =
          await dio.post(url,
              options: Options(
                headers: _headers,
              ),
              data: data);

      final body = response.data.toString();
      final preview = body.length > 500 ? body.substring(0, 500) : body;
      print('[HarmonySearch] RES action=$action status=${response.statusCode} dataType=${response.data.runtimeType} dataLen=${body.length}');
      print('[HarmonySearch] RES body preview: $preview');

      if (response.statusCode == 200) {
        if (response.data is! Map || body.isEmpty) {
          print('[HarmonySearch] RES action=$action EMPTY BODY or non-Map data');
          return _sendRequest(action, data,
              additionalParams: additionalParams, retryCount: retryCount + 1);
        }
        return response;
      } else {
        printINFO(
            "Retry $retryCount for $action — status ${response.statusCode}");
        return _sendRequest(action, data,
            additionalParams: additionalParams, retryCount: retryCount + 1);
      }
    } on DioException catch (e) {
      final rawBody = e.response?.data.toString() ?? '(no raw response)';
      final rawPreview = rawBody.length > 500 ? rawBody.substring(0, 500) : rawBody;
      print('[HarmonySearch] ERR action=$action type=${e.type} msg=${e.message}');
      print('[HarmonySearch] ERR response status=${e.response?.statusCode} body=$rawPreview');
      printINFO("Error $e");
      // if JSON parse failed, retry with plain text to capture the body
      if (e.type == DioExceptionType.unknown && rawBody.isNotEmpty && rawBody != '(no raw response)') {
        print('[HarmonySearch] ERR retrying to capture raw response');
        try {
          final plainResponse = await dio.post(url,
              options: Options(headers: _headers, responseType: ResponseType.plain),
              data: data);
          print('[HarmonySearch] ERR plain response status=${plainResponse.statusCode} body=${plainResponse.data.toString().length > 500 ? plainResponse.data.toString().substring(0, 500) : plainResponse.data.toString()}');
        } catch (e2) {
          print('[HarmonySearch] ERR plain response also failed: $e2');
        }
      }
      throw NetworkError();
    }
  }

  // Future<List<Map<String, dynamic>>>
  Future<dynamic> getHome({required int limit}) async {
    final data = Map.from(_context);
    data["browseId"] = "FEmusic_home";
    final response = await _sendRequest("browse", data);
    var results =
    nav(response.data, single_column_tab + section_list);

results ??= nav(response.data, [
  'contents',
  'twoColumnBrowseResultsRenderer',
  'tabs',
  0,
  'tabRenderer',
  'content',
  'sectionListRenderer',
  'contents'
]);

results ??= [];

final home = [...parseMixedContent(results)];

    final sectionList =
    nav(response.data,
        single_column_tab + ['sectionListRenderer']) ??
    nav(response.data, [
      'contents',
      'twoColumnBrowseResultsRenderer',
      'tabs',
      0,
      'tabRenderer',
      'content',
      'sectionListRenderer'
    ]) ??
    {};
    //inspect(sectionList);
    //print(sectionList.containsKey('continuations'));
    if (sectionList is Map &&
    sectionList.containsKey('continuations')) {
      requestFunc(additionalParams) async {
        return (await _sendRequest("browse", data,
                additionalParams: additionalParams))
            .data;
      }

      parseFunc(contents) => parseMixedContent(contents);
      final x = (await getContinuations(sectionList, 'sectionListContinuation',
          limit - home.length, requestFunc, parseFunc));
      // inspect(x);
      home.addAll([...x]);
    }

    return home;
  }

  Future<List<Map<String, dynamic>>> getCharts(String catogory,
      {String? countryCode}) async {
    final List<Map<String, dynamic>> charts = [];
    final data = Map.from(_context);

    data['browseId'] = 'FEmusic_charts';
    data['context']['client']["hl"] = 'en';
    if (countryCode != null) {
      data['formData'] = {
        'selectedValues': [countryCode]
      };
    }
    final response = (await _sendRequest('browse', data)).data;
    final results = nav(response, single_column_tab + section_list);
    results.removeAt(0);
    for (dynamic result in results) {
      if (nav(result, [
            "musicCarouselShelfRenderer",
            "header",
            "musicCarouselShelfBasicHeaderRenderer",
            ...title_text
          ]) ==
          "Video charts") {
        final catString = catogory == "TMV" ? "Top Music Videos" : "Trending";
        for (dynamic item in result['musicCarouselShelfRenderer']['contents']) {
          final parsed = parseChartsItemBrowseId(item);
          if (parsed['title'].toString().contains(catString)) {
            final songs = (await getPlaylistOrAlbumSongs(
                playlistId: parsed['browseId']))['tracks'];
            final limitedSongs = songs.length > 24 ? songs.sublist(0, 24) : songs;
            charts.add({'title': parsed['title'], 'contents': limitedSongs});
            break;
          }
        }
      } else {
        continue;
      }
    }

    return charts;
  }

  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    if (videoId.isNotEmpty && videoId.substring(0, 4) == "MPED") {
      videoId = videoId.substring(4);
    }
    final data = Map.from(_context);
    data['enablePersistentPlaylistPanel'] = true;
    data['isAudioOnly'] = true;
    data['tunerSettingValue'] = 'AUTOMIX_SETTING_NORMAL';
    if (videoId == "" && playlistId == null) {
      throw Exception(
          "You must provide either a video id, a playlist id, or both");
    }
    if (videoId != "") {
      data['videoId'] = videoId;
      playlistId ??= "RDAMVM$videoId";

      if (!(radio || shuffle)) {
        data['watchEndpointMusicSupportedConfigs'] = {
          'watchEndpointMusicConfig': {
            'hasPersistentPlaylistPanel': true,
            'musicVideoType': "MUSIC_VIDEO_TYPE_ATV",
          }
        };
      }
    }

    playlistId = validatePlaylistId(playlistId!);
    data['playlistId'] = playlistId;
    final isPlaylist =
        playlistId.startsWith('PL') || playlistId.startsWith('OLA');
    if (shuffle) {
      data['params'] = "wAEB8gECKAE%3D";
    }
    if (radio) {
      data['params'] = "wAEB";
    }

    final List<dynamic> tracks = [];
    dynamic lyricsBrowseId, relatedBrowseId, playlist;
    final results = {};

    if (additionalParamsNext == null) {
      final response = (await _sendRequest("next", data)).data;
      final watchNextRenderer = nav(response, [
        'contents',
        'singleColumnMusicWatchNextResultsRenderer',
        'tabbedRenderer',
        'watchNextTabbedResultsRenderer'
      ]);

      lyricsBrowseId = getTabBrowseId(watchNextRenderer, 1);
      relatedBrowseId = getTabBrowseId(watchNextRenderer, 2);
      if (onlyRelated) {
        return {
          'lyrics': lyricsBrowseId,
          'related': relatedBrowseId,
        };
      }

      results.addAll(nav(watchNextRenderer, [
        ...tab_content,
        'musicQueueRenderer',
        'content',
        'playlistPanelRenderer'
      ]));
      playlist = results['contents']
          .map((content) => nav(content,
              ['playlistPanelVideoRenderer', ...navigation_playlist_id]))
          .where((e) => e != null)
          .toList()
          .first;
      tracks.addAll(parseWatchPlaylist(results['contents']));
    }

    dynamic additionalParamsForNext;
    if (results.containsKey('continuations') || additionalParamsNext != null) {
      requestFunc(additionalParams) async =>
          (await _sendRequest("next", data, additionalParams: additionalParams))
              .data;
      parseFunc(contents) => parseWatchPlaylist(contents);
      final x = await getContinuations(results, 'playlistPanelContinuation',
          limit - tracks.length, requestFunc, parseFunc,
          ctokenPath: isPlaylist ? '' : 'Radio',
          isAdditionparamReturnReq: true,
          additionalParams_: additionalParamsNext);
      additionalParamsForNext = x[1];
      tracks.addAll(List<dynamic>.from(x[0]));
    }

    return {
      'tracks': tracks,
      'playlistId': playlist,
      'lyrics': lyricsBrowseId,
      'related': relatedBrowseId,
      'additionalParamsForNext': additionalParamsForNext
    };
  }

  Future<String> getAlbumBrowseId(String audioPlaylistId) async {
    final response = await dio.get("${domain}playlist",
        options: Options(headers: _headers),
        queryParameters: {"list": audioPlaylistId});
    final reg = RegExp(r'\"MPRE.+?\"');
    final matchs = reg.firstMatch(response.data.toString());
    if (matchs != null) {
      final x = (matchs[0])!;
      final res = (x.substring(1)).split("\\")[0];
      return res;
    }
    return audioPlaylistId;
  }

  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    final params = await getWatchPlaylist(videoId: videoId, onlyRelated: true);
    final data = Map.from(_context);
    data['browseId'] = params['related'];
    data['context']['client']['hl'] = hlCode;
    final response = (await _sendRequest('browse', data)).data;
    final sections = nav(response, ['contents'] + section_list);
    final x = parseMixedContent(sections);
    return x;
  }

  dynamic getLyrics(String browseId) async {
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final response = (await _sendRequest('browse', data)).data;
    return nav(
      response,
      ['contents', ...section_list_item, ...description_shelf, ...description],
    );
  }

  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int limit = 3000,
      bool related = false,
      int suggestionsLimit = 0}) async {
    String browseId = playlistId != null
        ? (playlistId.startsWith("VL") ? playlistId : "VL$playlistId")
        : albumId!;
    if (albumId != null && albumId.contains("OLAK5uy")) {
      browseId = await getAlbumBrowseId(browseId);
    }
    final data = Map.from(_context);
    data['browseId'] = browseId;
    final Map<String, dynamic> response =
        (await _sendRequest('browse', data)).data;
    if (playlistId != null) {
      final Map<String, dynamic> header =
          nav(response, ['header', "musicDetailHeaderRenderer"]) ??
              nav(response, [
                'contents',
                "twoColumnBrowseResultsRenderer",
                'tabs',
                0,
                "tabRenderer",
                "content",
                "sectionListRenderer",
                "contents",
                0,
                "musicResponsiveHeaderRenderer"
              ]);

      final Map<String, dynamic> results =
          nav(response, musicPlaylistShelfRenderer) ??
              nav(
                response,
                [
                  'contents',
                  "singleColumnBrowseResultsRenderer",
                  "tabs",
                  0,
                  "tabRenderer",
                  "content",
                  'sectionListRenderer',
                  'contents',
                  0,
                  "musicPlaylistShelfRenderer"
                ],
              );
      final Map<String, dynamic> playlist = {'id': results['playlistId']};

      playlist['title'] = nav(header, title_text);
      playlist['thumbnails'] = nav(header, thumnail_cropped) ??
          nav(header, [
            "thumbnail",
            "musicThumbnailRenderer",
            "thumbnail",
            "thumbnails"
          ]);
      playlist["description"] = nav(header, description);
      final int runCount = header['subtitle']['runs'].length;
      if (runCount > 1) {
        playlist['author'] = {
          'name': nav(header, subtitle2),
          'id': nav(header, ['subtitle', 'runs', 2] + navigation_browse_id)
        };
        if (runCount == 5) {
          playlist['year'] = nav(header, subtitle3);
        }
      }

      final int secondSubtitleRunCount =
          header['secondSubtitle']['runs'].length;
      final String count = (((header['secondSubtitle']['runs']
                      [secondSubtitleRunCount % 3]['text'])
                  .split(' ')[0])
              .split(',') as List)
          .join();
      final int songCount = int.parse(count);
      if (header['secondSubtitle']['runs'].length > 1) {
        playlist['duration'] = header['secondSubtitle']['runs']
            [(secondSubtitleRunCount % 3) + 2]['text'];
      }
      playlist['trackCount'] = songCount;

      // requestFunc(additionalParams) async => (await _sendRequest("browse", data,
      //         additionalParams: additionalParams))
      //     .data;

      requestFuncCountinuation(cont) async =>
          (await _sendRequest("browse", {...data, ...cont})).data;

      if (songCount > 0) {
        playlist['tracks'] = parsePlaylistItems(results['contents']);
        limit = songCount;

        List<dynamic> parseFunc(contents) => parsePlaylistItems(contents);

        playlist['tracks'] = [
          ...(playlist['tracks']),
          ...(await getContinuationsPlaylist(
              results, limit, requestFuncCountinuation, parseFunc))
        ];
      }
      playlist['duration_seconds'] = sumTotalDuration(playlist);
      return playlist;
    }

    //album content
    final album = parseAlbumHeader(response);
    dynamic results = nav(
          response,
          [
            'contents',
            "twoColumnBrowseResultsRenderer",
            "secondaryContents",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        ) ??
        nav(
          response,
          [
            'contents',
            "singleColumnBrowseResultsRenderer",
            "tabs",
            0,
            "tabRenderer",
            "content",
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer'
          ],
        );

    album['tracks'] = parsePlaylistItems(results['contents'],
        artistsM: album['artists'],
        thumbnailsM: album["thumbnails"],
        albumIdName: {"id": albumId, 'name': album['title']},
        albumYear: album['year'],
        isAlbum: true);
    results = nav(
      response,
      [...single_column_tab, ...section_list, 1, 'musicCarouselShelfRenderer'],
    );
    if (results != null) {
      List contents = [];
      if (results.runtimeType.toString().contains("Iterable") ||
          results.runtimeType.toString().contains("List")) {
        for (dynamic result in results) {
          contents.add(parseAlbum(result['musicTwoRowItemRenderer']));
        }
      } else {
        contents
            .add(parseAlbum(results['contents'][0]['musicTwoRowItemRenderer']));
      }
      album['other_versions'] = contents;
    }
    album['duration_seconds'] = sumTotalDuration(album);

    return album;
  }

  Future<List<String>> getSearchSuggestion(String queryStr) async {
    final data = Map.from(_context);
    data['input'] = queryStr;
    final res = nav(
            (await _sendRequest("music/get_search_suggestions", data)).data,
            ['contents', 0, 'searchSuggestionsSectionRenderer', 'contents']) ??
        [];
    return res
        .map<String?>((item) {
          return (nav(item, [
            'searchSuggestionRenderer',
            'navigationEndpoint',
            'searchEndpoint',
            'query'
          ])).toString();
        })
        .whereType<String>()
        .toList();
  }

  ///Specially created for deep-links
  Future<List> getSongWithId(String songId) async {
    final data = Map.of(_context);
    data['videoId'] = songId;
    final response = (await _sendRequest("player", data)).data;
    final category =
        nav(response, ["microformat", "microformatDataRenderer", "category"]);
    if (category == "Music" ||
        (response["videoDetails"]).containsKey("musicVideoType")) {
      final list = await getWatchPlaylist(videoId: songId);
      return [true, list['tracks']];
    }
    return [false, null];
  }

  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    printINFO('[HarmonySearch] search() query="$query" filter=$filter scope=$scope limit=$limit');
    final data = Map.of(_context);
    data['context']['client']["hl"] = 'en';
    data['query'] = query;

    final Map<String, dynamic> searchResults = {};
    final filters = [
      'albums',
      'artists',
      'playlists',
      'community_playlists',
      'featured_playlists',
      'songs',
      'videos'
    ];

    if (filter != null && !filters.contains(filter)) {
      throw Exception(
          'Invalid filter provided. Please use one of the following filters or leave out the parameter: ${filters.join(', ')}');
    }

    final scopes = ['library', 'uploads'];

    if (scope != null && !scopes.contains(scope)) {
      throw Exception(
          'Invalid scope provided. Please use one of the following scopes or leave out the parameter: ${scopes.join(', ')}');
    }

    if (scope == scopes[1] && filter != null) {
      throw Exception(
          'No filter can be set when searching uploads. Please unset the filter parameter when scope is set to uploads.');
    }

    final params = getSearchParams(filter, scope, ignoreSpelling);

    if (filterParams != null || params != null) {
      data['params'] = filterParams ?? params;
    }

    print('[HarmonySearch] search() sending request query="$query"');
    final rawResponse = await _sendRequest("search", data);
    print('[HarmonySearch] search() got response status=${rawResponse.statusCode} dataType=${rawResponse.data.runtimeType}');
    final response = rawResponse.data;

    print('[HarmonySearch] response keys=${response.keys} hasContents=${response.containsKey('contents')}');

    if (response is! Map || !response.containsKey('contents')) {
      print('[HarmonySearch] EARLY RETURN: response not Map or missing contents');
      return searchResults;
    }

    dynamic results;

    final tabbedContents = nav(response, [
      'contents',
      'tabbedSearchResultsRenderer',
      'tabs',
      scope == null || filter != null ? 0 : scopes.indexOf(scope) + 1,
      'tabRenderer',
      'content'
    ]);
    print('[HarmonySearch] tabbedContents=${tabbedContents != null} (${tabbedContents.runtimeType})');
    if (tabbedContents != null) {
      results = tabbedContents;
    } else {
      print('[HarmonySearch] using response[contents] fallback');
      results = response['contents'];
    }
    print('[HarmonySearch] results type=${results.runtimeType}');

    // Search Chips
    /*
    {
      "searchEndpoint": {
        "Songs": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Videos": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Albums": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Artists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Community playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB",
        "Featured playlists": "Eg-KAQwIARAAGAMQCRAFEAAYASgB"
      }
     */
    if (filter == null) {
      final searchChips = nav(results,
          ['sectionListRenderer', 'header', "chipCloudRenderer", "chips"]);

      searchResults['searchEndpoint'] = {};
      if (searchChips != null) {
        for (dynamic chipsItemRenderer in searchChips) {
          final chip = chipsItemRenderer['chipCloudChipRenderer'];
          final chipText = nav(chip, ['text', 'runs', 0, 'text']);
          searchResults['searchEndpoint'][chipText] =
              nav(chip, ['navigationEndpoint', 'searchEndpoint', 'params']);
        }
      }

      // now Featured playlists and community playlists are not coming in top results
      // so adding them in tab if not present
      if ((searchResults['searchEndpoint'])
              .containsKey("Community playlists") &&
          !searchResults.containsKey("Community playlists")) {
        searchResults["Community playlists"] = [];
      }

      if ((searchResults['searchEndpoint']).containsKey("Featured playlists") &&
          !searchResults.containsKey("Featured playlists")) {
        searchResults["Featured playlists"] = [];
      }
    }

    /// End Search Chips

    results = nav(results, ['sectionListRenderer', 'contents']);
    print('[HarmonySearch] sectionList contents type=${results.runtimeType}');

    if (results is! List) {
      print('[HarmonySearch] EARLY RETURN: results is not a List');
      return searchResults;
    }
    print('[HarmonySearch] sectionList contents length=${results.length}');
    String? type = filter?.substring(0, filter.length - 1).toLowerCase();
    printINFO('[HarmonySearch] processing ${results.length} shelves, type=$type filter=$filter');

    for (int shelfIdx = 0; shelfIdx < results.length; shelfIdx++) {
      final res = results[shelfIdx];
      if (res is! Map) { printWarning('[HarmonySearch] shelf[$shelfIdx] SKIP: not a Map'); continue; }

      Map? effectiveShelf;
      effectiveShelf = nav(res, ['musicShelfRenderer']);
      if (effectiveShelf is! Map) {
        final isr = nav(res, ['itemSectionRenderer']);
        if (isr is Map) {
          final itemSectionContents = isr['contents'];
          if (itemSectionContents is List) {
            effectiveShelf = {'contents': itemSectionContents};
          }
        }
      }
      if (effectiveShelf is! Map) {
        effectiveShelf = nav(res, ['musicCardShelfRenderer']);
      }
      if (effectiveShelf is! Map) {
        printWarning('[HarmonySearch] shelf[$shelfIdx] SKIP: unrecognized renderer, keys=${res.keys}');
        continue;
      }

      dynamic itemResults = nav(effectiveShelf, ['contents']);
      if (itemResults is! List) {
        printWarning('[HarmonySearch] shelf[$shelfIdx] SKIP: contents is not a List');
        continue;
      }
      String? typeFilter = filter;
      final category =
          filter == null ? "mixed" : (nav(effectiveShelf, title_text) ?? "");
      if (filter == null) {
        final mixedItems = parseSearchResults(itemResults,
            ['artist', 'playlist', 'song', 'video', 'station'], type, category);
        for (var item in mixedItems) {
          if (item == null) continue;
          String itemType;
          if (item is MediaItem) {
            final resultType = item.extras?['resultType']?.toString();
            itemType = resultType != null ? "${resultType}s" : "Songs";
          } else {
            itemType = "${item.runtimeType}s";
          }
          if (searchResults.containsKey(itemType) &&
              (searchResults[itemType] as List).length < 3) {
            (searchResults[itemType] as List).add(item);
          } else if (!searchResults.containsKey(itemType)) {
            searchResults[itemType] = [item];
          }
        }
      } else {
        searchResults[category] = parseSearchResults(
            itemResults,
            ['artist', 'playlist', 'song', 'video', 'station'],
            type,
            category);

      }
      type = typeFilter?.substring(0, typeFilter.length - 1).toLowerCase();

      if (filter != null && category.isNotEmpty) {
        requestFunc(additionalParams) async =>
            (await _sendRequest("search", data,
                    additionalParams: additionalParams))
                .data;
        parseFunc(contents) => parseSearchResults(contents,
            ['artist', 'playlist', 'song', 'video', 'station'], type, category);

        if (searchResults.containsKey(category)) {
          final x = await getContinuations(
              effectiveShelf,
              'musicShelfContinuation',
              limit - ((searchResults[category] as List).length),
              requestFunc,
              parseFunc,
              isAdditionparamReturnReq: true);

          searchResults["params"] = {
            'data': data,
            "type": type,
            "category": category,
            'additionalParams': x[1],
          };

          searchResults[category] = [
            ...(searchResults[category] as List),
            ...(x[0])
          ];
        }
      }
    }

    printINFO('[HarmonySearch] search() FINAL keys=${searchResults.keys} counts=${searchResults.map((k, v) => MapEntry(k, v is List ? v.length : v.runtimeType))}');
    return searchResults;
  }

  Future<Map<String, dynamic>> getSearchContinuation(Map additionalParamsNext,
      {int limit = 10}) async {
    final data = additionalParamsNext['data'];
    final type = additionalParamsNext['type'];
    final category = additionalParamsNext['category'];
    final Map<String, dynamic> searchResults = {};

    requestFunc(additionalParams) async =>
        (await _sendRequest("search", data, additionalParams: additionalParams))
            .data;

    parseFunc(contents) => parseSearchResults(contents,
        ['artist', 'playlist', 'song', 'video', 'station'], type, category);

    final x = await getContinuations(
        {}, 'musicShelfContinuation', limit, requestFunc, parseFunc,
        isAdditionparamReturnReq: true,
        additionalParams_: additionalParamsNext['additionalParams']);

    searchResults["params"] = {
      "data": data,
      "type": type,
      "category": category,
      'additionalParams': x[1],
    };

    searchResults[category] = x[0];

    return searchResults;
  }

  Future<Map<String, dynamic>> getArtist(String channelId) async {
    if (channelId.startsWith("MPLA")) {
      channelId = channelId.substring(4);
    }
    final data = Map.from(_context);
    data['context']['client']["hl"] = 'en';
    data['browseId'] = channelId;
    final response = (await _sendRequest("browse", data)).data;
    final results = nav(response, [...single_column_tab, ...section_list]);

    final Map<String, dynamic> artist = {'description': null, 'views': null};
    final Map<String, dynamic> header = (response['header']
            ['musicImmersiveHeaderRenderer']) ??
        response['header']['musicVisualHeaderRenderer'];
    artist['name'] = nav(header, title_text);
    final descriptionShelf =
        findObjectByKey(results, description_shelf[0], isKey: true);
    if (descriptionShelf != null) {
      artist['description'] = nav(descriptionShelf, description);
      artist['views'] = descriptionShelf['subheader'] == null
          ? null
          : descriptionShelf['subheader']['runs'][0]['text'];
    }
    final dynamic subscriptionButton = header['subscriptionButton'] != null
        ? header['subscriptionButton']['subscribeButtonRenderer']
        : null;
    artist['channelId'] = channelId;
    artist['shuffleId'] = nav(header,
        ['playButton', 'buttonRenderer', ...navigation_watch_playlist_id]);
    artist['radioId'] = nav(
      header,
      ['startRadioButton', 'buttonRenderer'] + navigation_playlist_id,
    );
    artist['subscribers'] = subscriptionButton != null
        ? nav(
            subscriptionButton,
            ['subscriberCountText', 'runs', 0, 'text'],
          )
        : null;

    artist['thumbnails'] = nav(header, thumbnails);

    artist.addAll(parseArtistContents(results));
    return artist;
  }

  Future<Map<String, dynamic>> getArtistRealtedContent(
      Map<String, dynamic> browseEndpoint, String category,
      {String additionalParams = ""}) async {
    final Map<String, dynamic> result = {
      "results": [],
    };
    final data = Map.of(_context);
    browseEndpoint.remove("content");
    if (browseEndpoint.isEmpty) return result;
    data.addAll(browseEndpoint);
    final response =
        (await _sendRequest("browse", data, additionalParams: additionalParams))
            .data;
    final contents = nav(response, [
      'contents',
      'singleColumnBrowseResultsRenderer',
      'tabs',
      0,
      'tabRenderer',
      'content',
      'sectionListRenderer',
      'contents',
      0,
    ]);

    if (category == "Songs" || category == "Videos") {
      if (additionalParams != "") {
        final contentList = nav(response, [
          "onResponseReceivedActions",
          0,
          "appendContinuationItemsAction",
          "continuationItems"
        ]);
        final x = parsePlaylistItems(contentList);
        result['results'] = x;
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else if (contents.containsKey("gridRenderer")) {
        result['results'] = (contents['gridRenderer']['items'])
            .map((video) => parseVideo(video['musicTwoRowItemRenderer']))
            .toList();
        result['additionalParams'] = "&ctoken=${null}&continuation=${null}";
      } else {
        final collapseContent =
            nav(contents, ['musicPlaylistShelfRenderer', "collapsedItemCount"]);
        if (collapseContent != null) {
          final contentlist =
              contents['musicPlaylistShelfRenderer']['contents'];
          if (contentlist.length.toString() != collapseContent.toString()) {
            final continuationItem = contentlist.removeAt(100);
            result['results'] = parsePlaylistItems(contentlist);
            final continuationKey = nav(continuationItem, [
              "continuationItemRenderer",
              "continuationEndpoint",
              "continuationCommand",
              "token"
            ]);
            result['additionalParams'] =
                "&ctoken=$continuationKey&continuation=$continuationKey";
          } else {
            result['results'] = parsePlaylistItems(contentlist);
            result['additionalParams'] = "&ctoken=null&continuation=null";
          }
        }
        return result;
      }
    } else if (category == 'Albums' || category == 'Singles') {
      List contentlist;

      /// in continuation
      if (additionalParams != "") {
        contentlist =
            response['continuationContents']['gridContinuation']['items'];
        final continuationKey = nav(response, [
          'continuationContents',
          'gridContinuation',
          'continuations',
          0,
          'nextContinuationData',
          'continuation'
        ]);
        result['additionalParams'] =
            "&ctoken=$continuationKey&continuation=$continuationKey";
      } else {
        /// in first request
        contentlist = contents['gridRenderer']['items'];

        final continuationKey = nav(contents, [
          'gridRenderer',
          'continuations',
          0,
          'nextContinuationData',
          'continuation'
        ]);
        result['additionalParams'] =
            "&ctoken=$continuationKey&continuation=$continuationKey";
      }

      result['results'] = category == 'Albums'
          ? contentlist
              .map((item) => parseAlbum(item['musicTwoRowItemRenderer']))
              .whereType<Album>()
              .toList()
          : contentlist
              .map((item) => parseSingle(item['musicTwoRowItemRenderer']))
              .whereType<Album>()
              .toList();
    }
    return result;
  }

  Future<String?> getSongYear(String songId) async {
    final data = Map.from(_context);
    data['browseId'] = "MPTC$songId";
    try {
      final response = (await _sendRequest('browse', data)).data;
      String? year = nav(response, [
        "onResponseReceivedActions",
        0,
        "openPopupAction",
        "popup",
        "dismissableDialogRenderer",
        "metadata",
        "musicMultiRowListItemRenderer",
        "secondTitle",
        "runs",
        2,
        "text"
      ]);
      return year;
    } catch (e) {
      rethrow;
    }
  }

  @override
  void onClose() {
    dio.close();
    super.onClose();
  }
}

class NetworkError extends Error {
  final message = "Network Error !";
}
