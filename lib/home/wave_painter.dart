import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Bottom activity wave — animates while a scan is in progress, sits flat
/// at rest. Echoes the audio-waveform footer from the reference design.
class WavePainter extends CustomPainter {
  final double phase;
  final bool isActive;

  WavePainter({required this.phase, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accentPrimary.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final amplitude = isActive ? 12.0 : 3.0;
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height / 2 +
          amplitude * math.sin((x / size.width * 4 * math.pi) + phase);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) => true;
}
