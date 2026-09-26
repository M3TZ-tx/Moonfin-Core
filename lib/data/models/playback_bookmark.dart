/// A user-created note pinned to one point in a video's timeline.
///
/// Fully compatible with Jellyfin Enhanced's "Smart Bookmarks" schema,
/// allowing bidirectional synchronization with Jellyfin Enhanced plugin on
/// the server while maintaining local offline persistence.
class PlaybackBookmark {
  /// Stable identifier for this bookmark. For Jellyfin Enhanced synced bookmarks,
  /// this is the map key (e.g. `Bm_1790279538154_kkcf546db`).
  final String id;

  /// Playback position in milliseconds.
  final int positionMs;

  /// User-entered note or description for this timestamp.
  final String label;

  /// When this bookmark was created.
  final DateTime createdAt;

  /// Optional title of the media item this bookmark belongs to.
  final String? itemName;

  const PlaybackBookmark({
    required this.id,
    required this.positionMs,
    required this.label,
    required this.createdAt,
    this.itemName,
  });

  PlaybackBookmark copyWith({
    int? positionMs,
    String? label,
    String? itemName,
  }) {
    return PlaybackBookmark(
      id: id,
      positionMs: positionMs ?? this.positionMs,
      label: label ?? this.label,
      createdAt: createdAt,
      itemName: itemName ?? this.itemName,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'positionMs': positionMs,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
    if (itemName != null) 'itemName': itemName,
  };

  factory PlaybackBookmark.fromJson(Map<String, dynamic> json) {
    return PlaybackBookmark(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      label: json['label'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      itemName: json['itemName'] as String?,
    );
  }

  /// Converts to the Jellyfin Enhanced server schema dictionary for bookmark.json
  Map<String, dynamic> toJellyfinEnhancedJson({
    required String itemId,
    String? mediaType,
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    return {
      'ItemId': itemId,
      'TmdbId': '',
      'TvdbId': '',
      'MediaType': mediaType ?? 'video',
      'Name': itemName ?? '',
      'Timestamp': positionMs / 1000.0,
      'Label': label,
      'CreatedAt': createdAt.toUtc().toIso8601String(),
      'UpdatedAt': nowIso,
      'SyncedFrom': 'Moonfin',
    };
  }

  /// Parses from Jellyfin Enhanced server bookmark.json item entry
  factory PlaybackBookmark.fromJellyfinEnhanced(
    String bookmarkId,
    Map<String, dynamic> json,
  ) {
    final tsSeconds = (json['Timestamp'] as num?)?.toDouble() ?? 0.0;
    final positionMs = (tsSeconds * 1000).round();
    final label = json['Label'] as String? ?? '';
    final name = json['Name'] as String?;
    final createdAt =
        DateTime.tryParse(json['CreatedAt'] as String? ?? '') ?? DateTime.now();

    return PlaybackBookmark(
      id: bookmarkId,
      positionMs: positionMs,
      label: label,
      createdAt: createdAt,
      itemName: name,
    );
  }
}
