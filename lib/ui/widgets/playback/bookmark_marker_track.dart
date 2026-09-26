import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// User bookmarks drawn over the video seek bar.
///
/// Sibling to [ChapterMarkerTrack] (same Stack-over-Slider approach so the
/// Slider keeps painting itself), but drawn as small amber diamonds rather
/// than plain lines, so a bookmark reads differently from a chapter mark
/// when both sit on the same bar.
class BookmarkMarkerTrack extends StatelessWidget {
  /// Bookmark timestamps in milliseconds.
  final List<int> positionsMs;

  final int durationMs;

  const BookmarkMarkerTrack({
    super.key,
    required this.positionsMs,
    required this.durationMs,
  });

  static const double height = 10;

  /// Matches [ChapterMarkerTrack]'s inset so the two tracks line up on the
  /// same bar: BaseSliderTrackShape insets by half the overlay radius (14),
  /// which is larger than half the thumb (7) for this seek bar's thumb.
  static const double _trackInset = 14;

  @override
  Widget build(BuildContext context) {
    if (positionsMs.isEmpty || durationMs <= 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BookmarkMarkerPainter(
            positionsMs: positionsMs,
            durationMs: durationMs,
            color: const Color(0xFFFFC107), // Amber accent
          ),
        ),
      ),
    );
  }
}

class _BookmarkMarkerPainter extends CustomPainter {
  final List<int> positionsMs;
  final int durationMs;
  final Color color;

  const _BookmarkMarkerPainter({
    required this.positionsMs,
    required this.durationMs,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (durationMs <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const inset = BookmarkMarkerTrack._trackInset;
    final usable = math.max(size.width - inset * 2, 0.0);
    const half = 4.5;

    for (final ms in positionsMs) {
      final fraction = (ms / durationMs).clamp(0.0, 1.0);
      final x = inset + fraction * usable;
      final cy = size.height / 2;
      final path = Path()
        ..moveTo(x, cy - half)
        ..lineTo(x + half, cy)
        ..lineTo(x, cy + half)
        ..lineTo(x - half, cy)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, shadowPaint);
    }
  }

  @override
  bool shouldRepaint(_BookmarkMarkerPainter old) =>
      old.durationMs != durationMs ||
      old.color != color ||
      !listEquals(old.positionsMs, positionsMs);
}
