import 'package:flutter/material.dart';

import '../core/theme.dart' show AppColors;
import 'history_entry.dart';

/// A compact chronological line chart of download/upload Mbps across past
/// runs, so a trend (a slow decline, a one-off dip) is visible at a glance
/// instead of scrolling a list comparing numbers by eye. [entries] is
/// expected oldest-first — [HistoryScreen] reverses `HistoryStore`'s
/// newest-first order before handing entries here. Only solo runs land in
/// history (`_finishCompare` never calls `HistoryStore.add`), so the series
/// is a single unbroken run of solo scans, not split by connection type.
class TrendChart extends StatelessWidget {
  final List<HistoryEntry> entries;

  const TrendChart({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'SPEED TREND',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              _legendDot(AppColors.accentPrimaryGlow, 'Download'),
              const SizedBox(width: 14),
              _legendDot(AppColors.accentSecondary, 'Upload'),
              const SizedBox(width: 14),
              _legendDot(AppColors.amber, 'Loss'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            width: double.infinity,
            child: CustomPaint(painter: _TrendPainter(entries: entries)),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<HistoryEntry> entries;

  _TrendPainter({required this.entries});

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;

    final maxMbps = entries.fold<double>(
      0,
      (max, e) => [max, e.downloadMbps, e.uploadMbps].reduce(
        (a, b) => a > b ? a : b,
      ),
    );
    final scale = maxMbps <= 0 ? 1.0 : maxMbps;

    void drawLine(List<double> values, Color color) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final x = size.width * i / (values.length - 1);
        final y = size.height - (values[i] / scale) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    drawLine(
        entries.map((e) => e.downloadMbps).toList(), AppColors.accentPrimaryGlow);
    drawLine(entries.map((e) => e.uploadMbps).toList(), AppColors.accentSecondary);

    // Packet loss doesn't share the Mbps scale, so it's marked as small dots
    // pinned to the bottom of the chart rather than plotted as a line.
    for (var i = 0; i < entries.length; i++) {
      final loss = entries[i].lossPercent;
      if (loss <= 0) continue;
      final x = size.width * i / (entries.length - 1);
      final y = size.height - 4;
      canvas.drawCircle(
        Offset(x, y),
        3,
        Paint()..color = loss >= 20 ? AppColors.coral : AppColors.amber,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.entries != entries;
}
