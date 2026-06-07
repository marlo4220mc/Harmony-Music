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
import '/services/music_service.dart';
import '../Settings/settings_screen_controller.dart';

class HomeScreenController extends GetxController {
  final MusicServices _musicServices = Get.find<MusicServices>();
  final isContentFetched = false.obs;
  final tabIndex = 0.obs;
  final networkError = false.obs;
  final quickPicks = QuickPicks([]).obs;
  final snapshotCards = <QuickPicks>[].obs;
  final middleContent = [].obs;
  final fixedContent = [].obs;
  //isHomeScreenOnTop var only useful if bottom nav enabled
  final isHomeSreenOnTop = true.obs;
  final List<ScrollController> contentScrollControllers = [];
  bool reverseAnimationtransiton = false;

  @override
  onInit() {
    super.onInit();
    _initAndLoadContent();
  }

  Future<void> _initAndLoadContent() async {
    await _musicServices.init();
    loadContent();
  }

  Future<void> loadContent() async {
    final box = Hive.box("AppPrefs");
    final currentContentType = box.get("discoverContentType") ?? "TR";
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
            await _loadRecommendationSnapshots();
            if (snapshotCards.isNotEmpty && snapshotCards.first.title == "foryou") {
              snapshotCards.removeAt(0);
            }
          }
        }
      } else {
        loadContentFromNetwork();
      }
    } else {
      loadContentFromNetwork();
    }
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
      printINFO("Loaded from offline db");
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
    "TR";

if (!discoverContentTypes.contains(
    contentType)) {

  printERROR(
    "Invalid discover type $contentType -> TR");

  contentType = "TR";

  await box.put(
    'discoverContentType',
    "TR",
  );
}

    networkError.value = false;
    try {
      List middleContentTemp = [];
      final homeContentListMap = await _musicServices.getHome(
          limit:
              Get.find<SettingsScreenController>().noOfHomeScreenContent.value);
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
      } else if (contentType == "BOLI") {
        await _loadRecommendationSnapshots();
        if (snapshotCards.isNotEmpty) {
          quickPicks.value = snapshotCards.removeAt(0);
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

    printINFO(
      "Quick Picks not found, using fallback",
    );

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
      await _loadRecommendationSnapshots();
      if (snapshotCards.isNotEmpty) {
        quickPicks_ = snapshotCards.removeAt(0);
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

  Future<void> _loadRecommendationSnapshots() async {
    try {
      final box = await Hive.openBox("RecommendationSnapshots");
      final len = box.length;
      if (len == 0) return;
      final List<QuickPicks> cards = [];

      // FOR YOU = most recent snapshot
      try {
        final latest = box.getAt(len - 1);
        final latestTracks = latest["tracks"] as List?;
        if (latestTracks != null) {
          final deserialized = latestTracks
              .map((e) => MediaItemBuilder.fromJson(e))
              .toList();
          cards.add(QuickPicks(deserialized, title: "foryou"));
        }
      } catch (_) {}

      // DISCOVER = random snapshot != FOR YOU
      try {
        if (len >= 2) {
          final discoverIdx = Random().nextInt(len - 1);
          final discover = box.getAt(discoverIdx);
          final discoverTracks = discover["tracks"] as List?;
          if (discoverTracks != null && discoverTracks.isNotEmpty) {
            cards.add(QuickPicks(
              discoverTracks.map((e) => MediaItemBuilder.fromJson(e)).toList(),
              title: "discover",
            ));
          }
        }
      } catch (_) {}

      // CONTINUE RADIO = most recent radio snapshot
      try {
        for (int i = len - 1; i >= 0; i--) {
          final entry = box.getAt(i);
          if (entry["type"] == "radio") {
            final radioTracks = entry["tracks"] as List?;
            if (radioTracks != null && radioTracks.isNotEmpty) {
              cards.add(QuickPicks(
                radioTracks.map((e) => MediaItemBuilder.fromJson(e)).toList(),
                title: "continueRadio",
              ));
            }
            break;
          }
        }
      } catch (_) {}

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
      printINFO("Saved Homescreen data data");
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
      printINFO("Saved Homescreen data data");
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
  void dispose() {
    disposeDetachedScrollControllers(disposeAll: true);
    super.dispose();
  }
}
