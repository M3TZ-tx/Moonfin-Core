import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/playback_bookmark.dart';
import '../data/services/media_server_client_factory.dart';

/// Stores and synchronizes per-item timestamp bookmarks on this device and with
/// Jellyfin Enhanced (if installed on the server).
///
/// If Jellyfin Enhanced is available, bookmarks are two-way synced across
/// devices (Web, Desktop, Mobile). If offline or on a server without the plugin,
/// bookmarks remain safely preserved in local storage.
class PlaybackBookmarkRepository {
  PlaybackBookmarkRepository._();

  static final PlaybackBookmarkRepository instance =
      PlaybackBookmarkRepository._();

  static const _keyPrefix = 'playback_bookmarks_v1';

  String _keyFor(String serverId, String itemId) =>
      '${_keyPrefix}_${serverId}_$itemId';

  MediaServerClient? _resolveClient(String serverId) {
    try {
      if (GetIt.instance.isRegistered<MediaServerClientFactory>()) {
        return GetIt.instance<MediaServerClientFactory>().getClientIfExists(serverId);
      }
    } catch (_) {}
    return null;
  }

  Dio _createDio(MediaServerClient client) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Authorization': buildServerAuthorizationHeader(
            scheme: 'MediaBrowser',
            deviceInfo: client.deviceInfo,
            accessToken: client.accessToken ?? '',
          ),
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    configureServerDio(dio);
    return dio;
  }

  String _generateBookmarkId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random();
    final randomPart = List.generate(9, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'Bm_${DateTime.now().millisecondsSinceEpoch}_$randomPart';
  }

  /// Loads bookmarks from local storage first, then attempts a background or
  /// direct sync with Jellyfin Enhanced if available.
  Future<List<PlaybackBookmark>> load(
    String serverId,
    String itemId, {
    String? itemName,
  }) async {
    final local = await _loadLocal(serverId, itemId);

    final client = _resolveClient(serverId);
    if (client == null || client.accessToken == null || client.userId == null) {
      return local;
    }

    try {
      final remote = await _fetchFromJellyfinEnhanced(client, itemId);
      if (remote != null) {
        await _saveLocal(serverId, itemId, remote);
        return remote;
      }
    } catch (_) {
      // Gracefully fall back to local on network or plugin unavailability
    }

    return local;
  }

  Future<List<PlaybackBookmark>> _loadLocal(String serverId, String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(serverId, itemId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final bookmarks = decoded
          .whereType<Map<String, dynamic>>()
          .map(PlaybackBookmark.fromJson)
          .toList();
      bookmarks.sort((a, b) => a.positionMs.compareTo(b.positionMs));
      return bookmarks;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveLocal(
    String serverId,
    String itemId,
    List<PlaybackBookmark> bookmarks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final sorted = [...bookmarks]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    if (sorted.isEmpty) {
      await prefs.remove(_keyFor(serverId, itemId));
      return;
    }
    await prefs.setString(
      _keyFor(serverId, itemId),
      jsonEncode(sorted.map((b) => b.toJson()).toList(growable: false)),
    );
  }

  /// Queries Jellyfin Enhanced's endpoint: /JellyfinEnhanced/user-settings/{userId}/bookmark.json
  Future<List<PlaybackBookmark>?> _fetchFromJellyfinEnhanced(
    MediaServerClient client,
    String itemId,
  ) async {
    final dio = _createDio(client);
    try {
      final url = '${client.baseUrl}/JellyfinEnhanced/user-settings/${client.userId}/bookmark.json';
      final response = await dio.get<dynamic>(url);
      if (response.statusCode != 200 || response.data == null) return null;

      final data = response.data;
      final Map<String, dynamic> root = data is String ? jsonDecode(data) : (data as Map<String, dynamic>);
      final bookmarksMap = root['Bookmarks'] as Map<String, dynamic>?;
      if (bookmarksMap == null) return null;

      final result = <PlaybackBookmark>[];
      final targetItemId = itemId.toLowerCase().replaceAll('-', '');

      for (final entry in bookmarksMap.entries) {
        final bMap = entry.value;
        if (bMap is! Map<String, dynamic>) continue;
        final rawId = (bMap['ItemId'] as String? ?? '').toLowerCase().replaceAll('-', '');
        if (rawId == targetItemId) {
          result.add(PlaybackBookmark.fromJellyfinEnhanced(entry.key, bMap));
        }
      }
      result.sort((a, b) => a.positionMs.compareTo(b.positionMs));
      return result;
    } finally {
      dio.close();
    }
  }

  /// Adds a bookmark and returns the item's full, sorted list afterward.
  Future<List<PlaybackBookmark>> add(
    String serverId,
    String itemId, {
    required int positionMs,
    required String label,
    String? itemName,
    String? mediaType,
  }) async {
    final bookmarkId = _generateBookmarkId();
    final bookmark = PlaybackBookmark(
      id: bookmarkId,
      positionMs: positionMs,
      label: label.trim(),
      createdAt: DateTime.now(),
      itemName: itemName,
    );

    final existing = await _loadLocal(serverId, itemId);
    final updated = [...existing, bookmark]
      ..sort((a, b) => a.positionMs.compareTo(b.positionMs));
    await _saveLocal(serverId, itemId, updated);

    // Sync to Jellyfin Enhanced in background
    unawaited(_pushAddOrUpdateToJellyfinEnhanced(
      serverId,
      itemId,
      bookmark,
      mediaType: mediaType,
    ));

    return updated;
  }

  /// Removes a bookmark by id and returns the item's remaining list.
  Future<List<PlaybackBookmark>> remove(
    String serverId,
    String itemId,
    String bookmarkId,
  ) async {
    final existing = await _loadLocal(serverId, itemId);
    final updated = existing.where((b) => b.id != bookmarkId).toList();
    await _saveLocal(serverId, itemId, updated);

    // Sync removal to Jellyfin Enhanced
    unawaited(_pushRemoveToJellyfinEnhanced(serverId, bookmarkId));

    return updated;
  }

  /// Edits an existing bookmark's time and/or label in place.
  Future<List<PlaybackBookmark>> update(
    String serverId,
    String itemId,
    String bookmarkId, {
    int? positionMs,
    String? label,
  }) async {
    final existing = await _loadLocal(serverId, itemId);
    PlaybackBookmark? target;
    final updated = [
      for (final b in existing)
        if (b.id == bookmarkId) ...[
          target = b.copyWith(positionMs: positionMs, label: label?.trim()),
          target,
        ] else
          b,
    ]..sort((a, b) => a.positionMs.compareTo(b.positionMs));

    await _saveLocal(serverId, itemId, updated);

    if (target != null) {
      unawaited(_pushAddOrUpdateToJellyfinEnhanced(serverId, itemId, target));
    }

    return updated;
  }

  Future<void> _pushAddOrUpdateToJellyfinEnhanced(
    String serverId,
    String itemId,
    PlaybackBookmark bookmark, {
    String? mediaType,
  }) async {
    final client = _resolveClient(serverId);
    if (client == null || client.accessToken == null || client.userId == null) return;

    final dio = _createDio(client);
    try {
      final url = '${client.baseUrl}/JellyfinEnhanced/user-settings/${client.userId}/bookmark.json';
      final response = await dio.get<dynamic>(url);
      Map<String, dynamic> root = {};
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        root = data is String ? jsonDecode(data) : Map<String, dynamic>.from(data as Map);
      }
      final bookmarksMap = Map<String, dynamic>.from(root['Bookmarks'] as Map? ?? {});

      bookmarksMap[bookmark.id] = bookmark.toJellyfinEnhancedJson(
        itemId: itemId,
        mediaType: mediaType,
      );
      root['Bookmarks'] = bookmarksMap;

      await dio.post<dynamic>(
        url,
        data: jsonEncode(root),
      );
    } catch (_) {
      // Ignore network errors; state remains safe locally
    } finally {
      dio.close();
    }
  }

  Future<void> _pushRemoveToJellyfinEnhanced(
    String serverId,
    String bookmarkId,
  ) async {
    final client = _resolveClient(serverId);
    if (client == null || client.accessToken == null || client.userId == null) return;

    final dio = _createDio(client);
    try {
      final url = '${client.baseUrl}/JellyfinEnhanced/user-settings/${client.userId}/bookmark.json';
      final response = await dio.get<dynamic>(url);
      if (response.statusCode != 200 || response.data == null) return;

      final data = response.data;
      final Map<String, dynamic> root = data is String ? jsonDecode(data) : Map<String, dynamic>.from(data as Map);
      final bookmarksMap = Map<String, dynamic>.from(root['Bookmarks'] as Map? ?? {});

      if (bookmarksMap.remove(bookmarkId) != null) {
        root['Bookmarks'] = bookmarksMap;
        await dio.post<dynamic>(
          url,
          data: jsonEncode(root),
        );
      }
    } catch (_) {
      // Ignore network errors
    } finally {
      dio.close();
    }
  }
}
