import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

import '/models/media_Item_builder.dart';
import '/ui/player/player_controller.dart';
import '/utils/helper.dart';
import '/models/album.dart';
import '/models/playlist.dart';
import '/models/quick_picks.dart';
import '/services/continue_playlists_store.dart';
import '/services/music_service.dart';
import '../Settings/settings_screen_controller.dart';

class HomeScreenController extends GetxController
    with WidgetsBindingObserver {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final snapshotCards = <QuickPicks>[].obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;
  final continuePlaylists = <Playlist>[].obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;

  @override
  onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _initAndLoadContent();
  }

  Future<void> _initAndLoadContent() async {
    await _musicServices.init();
    loadContent();
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final currentContentType = box.get("discoverContentType") ?? "BOLI";
    final isCachedHomeScreenDataEnabled =
        box.get("cacheHomeScreenData") ?? true;
    if (isCachedHomeScreenDataEnabled) {
      final loaded = await loadContentFromDb();
      if (loaded) {
        final currTimeSecsDiff = DateTime.now().millisecondsSinceEpoch -
            (box.get("homeScreenDataTime") ??
                DateTime.now().millisecondsSinceEpoch);
        final isStale = currTimeSecsDiff / 1000 > 3600 * 8;
        final cachedContentType =
            Hive.box("homeScreenData").get("cachedContentType") ?? "";
        final contentTypeChanged = cachedContentType != currentContentType;
        if (isStale || contentTypeChanged) {
          loadContentFromNetwork(silent: true);
        } else {
          if (currentContentType == "BOLI") {
            await _refreshBoliCards();
          }
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
    continuePlaylists.assignAll(await ContinuePlaylistsStore.loadHome());
  }

  void refreshContinuePlaylists() async {
    continuePlaylists.assignAll(await ContinuePlaylistsStore.loadHome());
  }

  Future<bool> loadContentFromDb() async {
    final homeScreenData = await Hive.openBox("homeScreenData");
    if (homeScreenData.keys.isNotEmpty) {
      final String quickPicksType = homeScreenData.get("quickPicksType");
      final List quickPicksData = homeScreenData.get("quickPicks");
      final List middleContentData = homeScreenData.get("middleContent") ?? [];
      final List fixedContentData = homeScreenData.get("fixedContent") ?? [];
      quickPicks.value = QuickPicks(
          quickPicksData.map((e) => MediaItemBuilder.fromJson(e)).toList(),
          title: quickPicksType);
      middleContent.value = middleContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      fixedContent.value = fixedContentData
          .map((e) => e["type"] == "Album Content"
              ? AlbumContent.fromJson(e)
              : PlaylistContent.fromJson(e))
          .toList();
      isContentFetched.value = true;
      
      return true;
    } else {
      return false;
    }
  }

  Future<void> loadContentFromNetwork({bool silent = false}) async {
    final box = Hive.box("AppPrefs");
    String contentType =
    box.get(
      "discoverContentType",
    ) ??
    "BOLI";

if (!discoverContentTypes.contains(
    contentType)) {

  printERROR(
    "Invalid discover type $contentType -> BOLI");

  contentType = "BOLI";

  await box.put(
    'discoverContentType',
    "BOLI",
  );
}

    networkError.value = false;
    try {
      List middleContentTemp = [];
      final homeContentListMap = await _musicServices.getHome(
          limit:
              Get.find<SettingsScreenController>().noOfHomeScreenContent.value);

      if (contentType == "BOLI") {
        await _refreshBoliCards();
        if (quickPicks.value.title != "foryou") {
          contentType = "TR";
        }
      }

      if (contentType == "TR") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Trending");
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          quickPicks.value = QuickPicks(
              List<MediaItem>.from(con["contents"]),
              title: "Trending");
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere((element) =>
              element['title'] == "Trending");
          if (index != -1) {
            quickPicks.value = QuickPicks(
                List<MediaItem>.from(charts[index]["contents"]),
                title: charts[index]['title']);
            middleContentTemp.addAll(charts);
          }
        }
      } else if (contentType == "TMV") {
        final index = homeContentListMap
            .indexWhere((element) => element['title'] == "Top music videos");
        if (index != -1 && index != 0) {
          final con = homeContentListMap.removeAt(index);
          quickPicks.value = QuickPicks(List<MediaItem>.from(con["contents"]),
              title: con["title"]);
        } else if (index == -1) {
          List charts = await _musicServices.getCharts(contentType);
          final index = charts.indexWhere((element) =>
              element['title'] == "Top Music Videos");
          if (index != -1) {
            quickPicks.value = QuickPicks(
                List<MediaItem>.from(charts[index]["contents"]),
                title: charts[index]["title"]);
            middleContentTemp.addAll(charts);
          }
        }
      }

      if (contentType != "BOLI") {
        await _loadRecommendationSnapshots();
        snapshotCards.clear();
      }

      if (quickPicks.value.songList.isEmpty) {

  final index =
      homeContentListMap.indexWhere(
    (element) =>
        element['title']
            .toString()
            .toLowerCase()
            .contains("quick"),
  );

  Map<String, dynamic>? con;

  if (index != -1) {

    con = homeContentListMap.removeAt(index);

  } else if (
      homeContentListMap.isNotEmpty) {

    

    con = homeContentListMap.first;
  }

  if (con != null) {

    quickPicks.value = QuickPicks(
      List<MediaItem>.from(
        con["contents"] ?? [],
      ),
      title:
          con["title"] ?? "Discover",
    );
  }
}

      middleContent.value = _setContentList(middleContentTemp);
      fixedContent.value = _setContentList(homeContentListMap);

      isContentFetched.value = true;

      // set home content last update time
      cachedHomeScreenData(updateAll: true);
      await Hive.box("AppPrefs")
          .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
      // ignore: unused_catch_stack
    } on NetworkError catch (r, e) {
      printERROR("Home Content not loaded due to ${r.message}");
      await Future.delayed(const Duration(seconds: 1));
      networkError.value = !silent;
    }
  }

  List _setContentList(
    List<dynamic> contents,
  ) {
    List contentTemp = [];
    for (var content in contents) {
      final items = content["contents"];
      if (items.isEmpty) continue;
      if (items[0].runtimeType == Playlist) {
        final tmp = PlaylistContent(
            playlistList: items.whereType<Playlist>().toList(),
            title: content["title"]);
        if (tmp.playlistList.length >= 2) {
          contentTemp.add(tmp);
        }
      } else if (items[0].runtimeType == Album) {
        final tmp = AlbumContent(
            albumList: items.whereType<Album>().toList(),
            title: content["title"]);
        if (tmp.albumList.length >= 2) {
          contentTemp.add(tmp);
        }
      }
    }
    return contentTemp;
  }

  Future<void> changeDiscoverContent(dynamic val, {String? songId}) async {
    QuickPicks? quickPicks_;
    if (val == "TMV" || val == 'TR') {
      try {
        final charts = await _musicServices.getCharts(val);
        final index = charts.indexWhere((element) =>
            element['title'] ==
            (val == "TMV" ? "Top Music Videos" : "Trending"));
        quickPicks_ = QuickPicks(
            List<MediaItem>.from(charts[index]["contents"]),
            title: charts[index]["title"]);
      } catch (e) {
        printERROR(
            "Seems ${val == "TMV" ? "Top music videos" : "Trending songs"} currently not available!");
      }
    } else if (val == "BOLI") {
      await _refreshBoliCards();
      if (quickPicks.value.songList.isNotEmpty) {
        quickPicks_ = quickPicks.value;
      }
    } else {
      snapshotCards.clear();
      return;
    }
    if (val == "TMV" || val == 'TR') {
      snapshotCards.clear();
    }
    if (quickPicks_ == null) return;

    quickPicks.value = quickPicks_;

    // set home content last update time
    cachedHomeScreenData(updateQuickPicksNMiddleContent: true);
    await Hive.box("AppPrefs")
        .put("homeScreenDataTime", DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _migrateToV3IfNeeded() async {
    final box = await Hive.openBox("RecommendationSnapshots");
    final len = box.length;
    if (len == 0) return;
    final first = box.getAt(0);
    if (first == null || first["repeatCount"] != null) return;

    final Map<String, Map> merged = {};
    for (int i = 0; i < len; i++) {
      final entry = box.getAt(i);
      if (entry == null) continue;
      final sid = entry["sourceSongId"]?.toString() ?? "";
      if (sid.isEmpty) continue;
      final createdAt = (entry["createdAt"] ?? 0) as int;
      final isRadio = entry["type"] == "radio";

      if (merged.containsKey(sid)) {
        final existing = merged[sid]!;
        existing["repeatCount"] = (existing["repeatCount"] as int) + 1;
        if (createdAt < (existing["firstSeenAt"] as int)) {
          existing["firstSeenAt"] = createdAt;
        }
        if (createdAt > (existing["lastPlayedAt"] as int)) {
          existing["lastPlayedAt"] = createdAt;
          existing["tracks"] = entry["tracks"];
          existing["playlistId"] = entry["playlistId"];
        }
        if (isRadio && createdAt > ((existing["lastRadioAt"] as int?) ?? 0)) {
          existing["lastRadioAt"] = createdAt;
        }
      } else {
        merged[sid] = {
          "sourceSongId": sid,
          "sourceSongTitle": entry["sourceSongTitle"] ?? "",
          "playlistId": entry["playlistId"] ?? "",
          "repeatCount": 1,
          "firstSeenAt": createdAt,
          "lastPlayedAt": createdAt,
          if (isRadio) "lastRadioAt": createdAt,
          "tracks": entry["tracks"],
        };
      }
    }

    await box.clear();
    for (final entry in merged.values) {
      await box.add(entry);
    }
  }

  QuickPicks? _calculateDiscover(List<Map> entries, String? forYouId) {
    if (entries.length < 2) return null;
    final candidates = entries
        .where((e) => e["sourceSongId"] != forYouId && e["lastPlayedAt"] != null)
        .toList();
    if (candidates.isEmpty) return null;
    Map? selected;
    if (candidates.length < 3) {
      selected = candidates[Random().nextInt(candidates.length)];
    } else {
      final scores = <double>[];
      double totalScore = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in candidates) {
        final cnt = (e["repeatCount"] ?? 1) as int;
        final lastPlayed = (e["lastPlayedAt"] ?? 0) as int;
        final hours = ((now - lastPlayed) / 3600000).clamp(0, 720).toInt();
        final double baseWeight = cnt == 1 ? 50 : (cnt <= 4 ? 35 : 20);
        final recencyBonus = hours < 30 ? 30 - hours : 0;
        final score = baseWeight + recencyBonus;
        scores.add(score);
        totalScore += score;
      }
      double pick = Random().nextDouble() * totalScore;
      for (int i = 0; i < candidates.length; i++) {
        pick -= scores[i];
        if (pick <= 0) {
          selected = candidates[i];
          break;
        }
      }
      selected ??= candidates.last;
    }
    final tracks = selected["tracks"] as List?;
    if (tracks == null || tracks.isEmpty) return null;
    return QuickPicks(
      tracks.map((e) => MediaItemBuilder.fromJson(e)).toList(),
      title: "discover",
    );
  }

  Future<void> _loadRecommendationSnapshots() async {
    try {
      final box = await Hive.openBox("RecommendationSnapshots");
      final len = box.length;
      if (len == 0) return;

      await _migrateToV3IfNeeded();
      final newLen = box.length;
      if (newLen == 0) return;

      final List<Map> entries = [];
      for (int i = 0; i < newLen; i++) {
        final entry = box.getAt(i);
        if (entry != null) entries.add(entry);
      }

      final List<QuickPicks> cards = [];

      // FOR YOU = entry with max lastPlayedAt
      Map? forYouEntry;
      for (final entry in entries) {
        if (forYouEntry == null || (entry["lastPlayedAt"] ?? 0) > (forYouEntry["lastPlayedAt"] ?? 0)) {
          forYouEntry = entry;
        }
      }
      if (forYouEntry != null) {
        final tracks = forYouEntry["tracks"] as List?;
        if (tracks != null && tracks.isNotEmpty) {
          cards.add(QuickPicks(
            tracks.map((e) => MediaItemBuilder.fromJson(e)).toList(),
            title: "foryou",
          ));
        }
      }

      // DISCOVER = weighted selection
      final discover = _calculateDiscover(entries, forYouEntry?["sourceSongId"]);
      if (discover != null) {
        cards.add(discover);
      }

      // CONTINUE RADIO = entry with max lastRadioAt
      Map? radioEntry;
      for (final entry in entries) {
        final lastRadio = entry["lastRadioAt"] as int?;
        if (lastRadio != null &&
            (radioEntry == null || lastRadio > (radioEntry["lastRadioAt"] as int))) {
          radioEntry = entry;
        }
      }
      if (radioEntry != null) {
        final tracks = radioEntry["tracks"] as List?;
        if (tracks != null && tracks.isNotEmpty) {
          cards.add(QuickPicks(
            tracks.map((e) => MediaItemBuilder.fromJson(e)).toList(),
            title: "continueradio",
          ));
        }
      }

      snapshotCards.value = cards;
    } catch (_) {}
  }

  void onSideBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  void onBottonBarTabSelected(int index) {
    reverseAnimationtransiton = index > tabIndex.value;
    tabIndex.value = index;
  }

  ///This is used to minimized bottom navigation bar by setting [isHomeSreenOnTop.value] to `true` and set mini player height.
  ///
  ///and applicable/useful if bottom nav enabled
  void whenHomeScreenOnTop() {
    if (Get.find<SettingsScreenController>().isBottomNavBarEnabled.isTrue) {
      final currentRoute = getCurrentRouteName();
      final isHomeOnTop = currentRoute == '/homeScreen';
      final isResultScreenOnTop = currentRoute == '/searchResultScreen';
      final playerCon = Get.find<PlayerController>();

      isHomeSreenOnTop.value = isHomeOnTop;

      // Set miniplayer height accordingly
      if (!playerCon.initFlagForPlayer) {
        if (isHomeOnTop) {
          playerCon.playerPanelMinHeight.value = 75.0;
        } else {
          Future.delayed(
              isResultScreenOnTop
                  ? const Duration(milliseconds: 300)
                  : Duration.zero, () {
            playerCon.playerPanelMinHeight.value =
                75.0 + Get.mediaQuery.viewPadding.bottom;
          });
        }
      }
    }
  }

  Future<void> cachedHomeScreenData({
    bool updateAll = false,
    bool updateQuickPicksNMiddleContent = false,
  }) async {
    if (Get.find<SettingsScreenController>().cacheHomeScreenData.isFalse ||
        quickPicks.value.songList.isEmpty) {
      return;
    }

    final homeScreenData = Hive.box("homeScreenData");

    if (updateQuickPicksNMiddleContent) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "cachedContentType":
            Hive.box("AppPrefs").get("discoverContentType") ?? "TR",
      });
      
    } else if (updateAll) {
      await homeScreenData.putAll({
        "quickPicksType": quickPicks.value.title,
        "quickPicks": _getContentDataInJson(quickPicks.value.songList,
            isQuickPicks: true),
        "middleContent": _getContentDataInJson(middleContent.toList()),
        "fixedContent": _getContentDataInJson(fixedContent.toList()),
        "cachedContentType":
            Hive.box("AppPrefs").get("discoverContentType") ?? "TR",
      });
      
    }
  }

  List<Map<String, dynamic>> _getContentDataInJson(List content,
      {bool isQuickPicks = false}) {
    if (isQuickPicks) {
      return content.toList().map((e) => MediaItemBuilder.toJson(e)).toList();
    } else {
      return content.map((e) {
        if (e.runtimeType == AlbumContent) {
          return (e as AlbumContent).toJson();
        } else {
          return (e as PlaylistContent).toJson();
        }
      }).toList();
    }
  }

  void disposeDetachedScrollControllers({bool disposeAll = false}) {
    final scrollControllersCopy = contentScrollControllers.toList();
    for (final contoller in scrollControllersCopy) {
      if (!contoller.hasClients || disposeAll) {
        contentScrollControllers.remove(contoller);
        contoller.dispose();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        Hive.isBoxOpen("AppPrefs") &&
        Hive.box("AppPrefs").get("discoverContentType") == "BOLI") {
      _refreshBoliCards();
    }
  }

  Future<void> _refreshBoliCards() async {
    await _loadRecommendationSnapshots();
    if (snapshotCards.isNotEmpty) {
      quickPicks.value = snapshotCards.removeAt(0);
    }
  }

  Future<void> refreshContinueRadio() async {
    try {
      final box = await Hive.openBox("RecommendationSnapshots");
      final len = box.length;
      if (len == 0) return;
      Map? radioEntry;
      for (int i = 0; i < len; i++) {
        final entry = box.getAt(i);
        if (entry == null) continue;
        final lastRadio = entry["lastRadioAt"] as int?;
        if (lastRadio != null &&
            (radioEntry == null ||
                lastRadio > (radioEntry["lastRadioAt"] as int))) {
          radioEntry = entry;
        }
      }
      if (radioEntry == null) return;
      final tracks = radioEntry["tracks"] as List?;
      if (tracks == null || tracks.isEmpty) return;
      final card = QuickPicks(
        tracks.map((e) => MediaItemBuilder.fromJson(e)).toList(),
        title: "continueradio",
      );
      final idx = snapshotCards.indexWhere((qp) => qp.title == "continueradio");
      if (idx >= 0) {
        snapshotCards[idx] = card;
      } else {
        snapshotCards.add(card);
      }
    } catch (_) {}
  }

  Future<void> refreshAfterBootstrap() async {
    if (Hive.isBoxOpen("AppPrefs") &&
        Hive.box("AppPrefs").get("discoverContentType") == "BOLI") {
      await _refreshBoliCards();
      if (quickPicks.value.title == "foryou") {
        await loadContentFromNetwork(silent: true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
