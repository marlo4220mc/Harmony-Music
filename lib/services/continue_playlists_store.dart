import 'dart:math';
import 'package:hive/hive.dart';
import '../models/playlist.dart';

class ContinuePlaylistsStore {
  static const _memoryBoxName = 'ContinuePlaylistsMemory';
  static const _homeBoxName = 'ContinuePlaylistsHome';
  static const _maxMemory = 50;

  static Box? _memoryBox;
  static Box? _homeBox;

  static Future<Box> _getMemoryBox() async {
    _memoryBox ??= await Hive.openBox(_memoryBoxName);
    return _memoryBox!;
  }

  static Future<Box> _getHomeBox() async {
    _homeBox ??= await Hive.openBox(_homeBoxName);
    return _homeBox!;
  }

  static int _safeInt(Map map, String key) =>
      map[key] is int ? map[key] as int : 0;

  static String _safeString(Map map, String key) =>
      map[key] is String ? map[key] as String : '';

  static Future<void> save({
    required String playlistId,
    required String title,
    String? subtitle,
    String? imageUrl,
  }) async {
    try {
      final box = await _getMemoryBox();
      final now = DateTime.now().millisecondsSinceEpoch;

      if (box.containsKey(playlistId)) {
        final entry = Map<String, dynamic>.from(box.get(playlistId));
        entry['updatedAt'] = now;
        entry['interactionCount'] = _safeInt(entry, 'interactionCount') + 1;
        await box.put(playlistId, entry);
      } else {
        await box.put(playlistId, {
          'title': title,
          'subtitle': subtitle ?? '',
          'imageUrl': imageUrl ?? '',
          'updatedAt': now,
          'interactionCount': 1,
        });
      }

      await _evictIfNeeded(box);
      await recalculateHome();
    } catch (_) {
    }
  }

  static Future<bool> contains(String playlistId) async {
    try {
      final box = await _getMemoryBox();
      return box.containsKey(playlistId);
    } catch (_) {
      return false;
    }
  }

  static Future<void> remove(String playlistId) async {
    try {
      final box = await _getMemoryBox();
      await box.delete(playlistId);
      await recalculateHome();
    } catch (_) {
    }
  }

  static Future<List<Playlist>> loadHome() async {
    try {
      final homeBox = await _getHomeBox();
      final data = homeBox.get('homeData');
      if (data is! List) return [];

      final memoryBox = await _getMemoryBox();
      final result = <Playlist>[];
      for (final entry in data) {
        if (entry is! String) continue;
        if (!memoryBox.containsKey(entry)) continue;
        final raw = memoryBox.get(entry);
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        result.add(Playlist(
          title: _safeString(map, 'title'),
          playlistId: entry,
          description: _safeString(map, 'subtitle'),
          thumbnailUrl: _safeString(map, 'imageUrl').isNotEmpty
              ? _safeString(map, 'imageUrl')
              : Playlist.thumbPlaceholderUrl,
        ));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<List<Playlist>> loadMemory() async {
    try {
      final box = await _getMemoryBox();
      final result = <Playlist>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        result.add(Playlist(
          title: _safeString(map, 'title'),
          playlistId: key.toString(),
          description: _safeString(map, 'subtitle'),
          thumbnailUrl: _safeString(map, 'imageUrl').isNotEmpty
              ? _safeString(map, 'imageUrl')
              : Playlist.thumbPlaceholderUrl,
        ));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  static Future<void> recalculateHome() async {
    try {
      final memoryBox = await _getMemoryBox();
      if (memoryBox.isEmpty) {
        final homeBox = await _getHomeBox();
        await homeBox.put('homeData', <String>[]);
        return;
      }

      final entries = <_MemoryEntry>[];
      for (final key in memoryBox.keys) {
        final raw = memoryBox.get(key);
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        entries.add(_MemoryEntry(
          playlistId: key.toString(),
          updatedAt: _safeInt(map, 'updatedAt'),
          interactionCount: _safeInt(map, 'interactionCount'),
        ));
      }

      entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final top10 = <String>[];

      if (entries.isNotEmpty) {
        top10.add(entries.first.playlistId);
        entries.removeAt(0);
      }

      entries.sort((a, b) => _score(b).compareTo(_score(a)));
      final topByScore = entries.take(min(4, entries.length)).toList();
      for (final e in topByScore) {
        top10.add(e.playlistId);
        entries.remove(e);
      }

      final remaining = entries.toList();
      final dailySeed = DateTime.now().millisecondsSinceEpoch ~/ 86400000;
      remaining.sort((a, b) =>
          (a.playlistId.hashCode ^ dailySeed)
              .compareTo(b.playlistId.hashCode ^ dailySeed));
      for (final e
          in remaining.take(min(10 - top10.length, remaining.length))) {
        top10.add(e.playlistId);
      }

      final homeBox = await _getHomeBox();
      await homeBox.put('homeData', top10);
    } catch (_) {
    }
  }

  static int _score(_MemoryEntry entry) {
    final daysSince =
        DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(entry.updatedAt),
        ).inDays;
    return entry.interactionCount + max(0, 30 - daysSince);
  }

  static Future<void> _evictIfNeeded(Box box) async {
    if (box.length <= _maxMemory) return;

    try {
      final entries = <_MemoryEntry>[];
      for (final key in box.keys) {
        final raw = box.get(key);
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        entries.add(_MemoryEntry(
          playlistId: key.toString(),
          updatedAt: _safeInt(map, 'updatedAt'),
          interactionCount: _safeInt(map, 'interactionCount'),
        ));
      }

      entries.sort((a, b) => _score(a).compareTo(_score(b)));
      final toRemove = entries.take(entries.length - _maxMemory);
      for (final e in toRemove) {
        await box.delete(e.playlistId);
      }
    } catch (_) {
    }
  }
}

class _MemoryEntry {
  final String playlistId;
  final int updatedAt;
  final int interactionCount;

  const _MemoryEntry({
    required this.playlistId,
    required this.updatedAt,
    required this.interactionCount,
  });
}
