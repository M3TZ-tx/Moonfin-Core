import 'package:flutter/material.dart';

import '../../../data/models/playback_bookmark.dart';
import '../../../playback/playback_bookmark_repository.dart';
import '../../../util/playback_time_label.dart';
import '../../widgets/overlay_sheet.dart';

/// "Add Bookmark" dialog: lets the viewer drop a timestamped note on the
/// item currently playing, and lists/jumps-to/deletes the notes already on
/// it. Modeled on Jellyfin Enhanced's bookmark dialog.
///
/// This dialog interacts with [PlaybackBookmarkRepository] which keeps
/// bookmarks stored locally and syncs with Jellyfin Enhanced on the server.
class BookmarkManagerDialog extends StatefulWidget {
  final String serverId;
  final String itemId;
  final String itemName;

  /// Where the seek bar is right now; pre-fills the time field and is the
  /// position a fresh bookmark gets if the field is left untouched.
  final Duration initialPosition;

  final Duration duration;

  /// Called when the user taps a bookmark's jump arrow. The dialog stays
  /// open afterward, matching Jellyfin Enhanced, so a viewer can queue up
  /// several jumps or keep adding notes without reopening it.
  final ValueChanged<Duration> onJumpTo;

  const BookmarkManagerDialog({
    super.key,
    required this.serverId,
    required this.itemId,
    required this.itemName,
    required this.initialPosition,
    required this.duration,
    required this.onJumpTo,
  });

  static Future<void> show(
    BuildContext context, {
    required String serverId,
    required String itemId,
    required String itemName,
    required Duration initialPosition,
    required Duration duration,
    required ValueChanged<Duration> onJumpTo,
  }) {
    return showFocusRestoringDialog<void>(
      context: context,
      builder: (_) => BookmarkManagerDialog(
        serverId: serverId,
        itemId: itemId,
        itemName: itemName,
        initialPosition: initialPosition,
        duration: duration,
        onJumpTo: onJumpTo,
      ),
    );
  }

  @override
  State<BookmarkManagerDialog> createState() => _BookmarkManagerDialogState();
}

class _BookmarkManagerDialogState extends State<BookmarkManagerDialog> {
  late final TextEditingController _timeController;
  final _labelController = TextEditingController();

  List<PlaybackBookmark> _bookmarks = const [];
  bool _loading = true;
  String? _timeError;

  @override
  void initState() {
    super.initState();
    _timeController = TextEditingController(
      text: formatPlaybackDuration(widget.initialPosition),
    );
    _load();
  }

  @override
  void dispose() {
    _timeController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bookmarks = await PlaybackBookmarkRepository.instance.load(
      widget.serverId,
      widget.itemId,
      itemName: widget.itemName,
    );
    if (!mounted) return;
    setState(() {
      _bookmarks = bookmarks;
      _loading = false;
    });
  }

  /// Parses `h:mm:ss`, `m:ss`, or a bare seconds count.
  int? _parseTimeToMs(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(':');
    if (parts.any((p) => int.tryParse(p) == null)) return null;
    final nums = parts.map(int.parse).toList();
    int seconds;
    switch (nums.length) {
      case 1:
        seconds = nums[0];
        break;
      case 2:
        seconds = nums[0] * 60 + nums[1];
        break;
      case 3:
        seconds = nums[0] * 3600 + nums[1] * 60 + nums[2];
        break;
      default:
        return null;
    }
    if (seconds < 0) return null;
    return seconds * 1000;
  }

  Future<void> _addBookmark() async {
    final ms = _parseTimeToMs(_timeController.text);
    if (ms == null) {
      setState(() => _timeError = 'Enter a time like 5:27 or 1:05:27');
      return;
    }
    setState(() => _timeError = null);
    final updated = await PlaybackBookmarkRepository.instance.add(
      widget.serverId,
      widget.itemId,
      positionMs: ms,
      label: _labelController.text,
      itemName: widget.itemName,
    );
    if (!mounted) return;
    setState(() {
      _bookmarks = updated;
      _labelController.clear();
    });
  }

  Future<void> _deleteBookmark(PlaybackBookmark bookmark) async {
    final updated = await PlaybackBookmarkRepository.instance.remove(
      widget.serverId,
      widget.itemId,
      bookmark.id,
    );
    if (!mounted) return;
    setState(() => _bookmarks = updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final surface = scheme.brightness == Brightness.dark
        ? const Color(0xFF17181C)
        : scheme.surface;

    final titleText = isArabic ? 'العلامات المرجعية والملاحظات' : 'Smart Bookmarks';
    final timeLabel = isArabic ? 'الوقت' : 'TIME';
    final noteLabel = isArabic ? 'الملاحظة (اختياري)' : 'NOTE / LABEL (OPTIONAL)';
    final noteHint = isArabic ? 'مثال: مشهد رائع، معلومة مهمة...' : 'e.g. Epic scene, Important note...';
    final existingLabel = isArabic ? 'العلامات المرجعية السابقة' : 'EXISTING BOOKMARKS';
    final emptyText = isArabic ? 'لا توجد علامات مرجعية بعد.' : 'No bookmarks yet.';
    final addBtnText = isArabic ? 'إضافة علامة مرجعية' : 'Add Bookmark';
    final cancelBtnText = isArabic ? 'إغلاق' : 'Close';

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleText,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.itemName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _fieldLabel(theme, timeLabel),
              const SizedBox(height: 6),
              TextField(
                controller: _timeController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  errorText: _timeError,
                  isDense: true,
                  prefixIcon: const Icon(Icons.access_time_rounded, size: 20),
                ),
                onChanged: (_) {
                  if (_timeError != null) setState(() => _timeError = null);
                },
              ),
              const SizedBox(height: 16),
              _fieldLabel(theme, noteLabel),
              const SizedBox(height: 6),
              TextField(
                controller: _labelController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: noteHint,
                  isDense: true,
                  prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                ),
                onSubmitted: (_) => _addBookmark(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _fieldLabel(theme, existingLabel),
                  const SizedBox(width: 8),
                  if (_bookmarks.isNotEmpty)
                    CircleAvatar(
                      radius: 10,
                      backgroundColor: const Color(0xFFFFC107).withOpacity(0.3),
                      child: Text(
                        '${_bookmarks.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFC107),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : _bookmarks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            emptyText,
                            style: TextStyle(color: theme.hintColor),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _bookmarks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final bookmark = _bookmarks[index];
                          return _BookmarkRow(
                            bookmark: bookmark,
                            onJump: () => widget.onJumpTo(
                              Duration(milliseconds: bookmark.positionMs),
                            ),
                            onDelete: () => _deleteBookmark(bookmark),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                    ),
                    onPressed: _addBookmark,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(addBtnText),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 16),
                    label: Text(cancelBtnText),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(ThemeData theme, String text) => Text(
    text,
    style: theme.textTheme.labelSmall?.copyWith(
      color: theme.hintColor,
      letterSpacing: 0.5,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _BookmarkRow extends StatelessWidget {
  final PlaybackBookmark bookmark;
  final VoidCallback onJump;
  final VoidCallback onDelete;

  const _BookmarkRow({
    required this.bookmark,
    required this.onJump,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.hintColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFFFC107),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatPlaybackDuration(
                    Duration(milliseconds: bookmark.positionMs),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (bookmark.label.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bookmark.label,
                    style: TextStyle(color: theme.hintColor, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'Jump to bookmark',
            onPressed: onJump,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete bookmark',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
