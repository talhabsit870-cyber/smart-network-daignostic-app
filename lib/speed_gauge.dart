import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'main.dart' show AppColors;

/// A compact needle gauge in the classic speed-test style: a gradient arc,
/// non-linear tick marks (dense at the low end, sparse at the high end,
/// matching how throughput actually clusters), a thin needle, and a big
/// centered readout. Sized via [size] so the same widget works as the
/// live test dial and as a small twin metric on the results page.
class SpeedGauge extends StatelessWidget {
  final double value;
  final double maxValue;
  final double size;
  final String unitLabel;

  const SpeedGauge({
    super.key,
    required this.value,
    this.maxValue = 100,
    this.size = 180,
    this.unitLabel = 'Mbps',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _SpeedGaugePainter(value: value, maxValue: maxValue),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.06),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toStringAsFixed(1),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: size * 0.19,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                SizedBox(height: size * 0.03),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: size * 0.035,
                      height: size * 0.035,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.violetGlow,
                      ),
                    ),
                    SizedBox(width: size * 0.03),
                    Text(
                      unitLabel,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: size * 0.075,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedGaugePainter extends CustomPainter {
  final double value;
  final double maxValue;

  _SpeedGaugePainter({required this.value, required this.maxValue});

  static const _ticks = [0, 1, 5, 10, 20, 30, 50, 75, 100];
  static const _startAngle = math.pi * 0.75; // 135°
  static const _sweepAngle = math.pi * 1.5; // 270°

  double _angleFor(double v) =>
      _startAngle + _sweepAngle * (v / maxValue).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    // A generous margin is reserved outside the arc for tick marks + the
    // "100" label (the widest) so they never clip the canvas edge, even at
    // the down-left/down-right diagonal where both x and y offsets stack.
    final radius = shortest / 2 - shortest * 0.22;
    final strokeWidth = shortest * 0.065;

    canvas.drawCircle(
      center,
      radius + strokeWidth * 0.9,
      Paint()..color = AppColors.surface,
    );

    final trackPaint = Paint()
      ..color = AppColors.unknown
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
        _startAngle, _sweepAngle, false, trackPaint);

    final progress = (value / maxValue).clamp(0.0, 1.0);
    if (progress > 0) {
      final progressPaint = Paint()
        ..shader = const SweepGradient(
          startAngle: _startAngle,
          endAngle: _startAngle + _sweepAngle,
          colors: [AppColors.violet, AppColors.violetGlow, AppColors.magenta],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          _startAngle, _sweepAngle * progress, false, progressPaint);
    }

    // Tick marks — a short radial dash at each tick's exact angle, so every
    // number has a precise anchor point on the ring instead of floating.
    final tickPaint = Paint()
      ..color = AppColors.textMuted
      ..strokeWidth = shortest * 0.008
      ..strokeCap = StrokeCap.round;
    final tickInnerR = radius + strokeWidth * 0.5 + shortest * 0.015;
    final tickOuterR = tickInnerR + shortest * 0.035;
    for (final tick in _ticks) {
      final angle = _angleFor(tick.toDouble());
      canvas.drawLine(
        Offset(center.dx + tickInnerR * math.cos(angle),
            center.dy + tickInnerR * math.sin(angle)),
        Offset(center.dx + tickOuterR * math.cos(angle),
            center.dy + tickOuterR * math.sin(angle)),
        tickPaint,
      );
    }

    final labelRadius = tickOuterR + shortest * 0.05;
    for (final tick in _ticks) {
      final angle = _angleFor(tick.toDouble());
      final pos = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '$tick',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: shortest * 0.045,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    final needleAngle = _angleFor(value);
    final needleLength = radius - strokeWidth * 0.6;
    final needleEnd = Offset(
      center.dx + needleLength * math.cos(needleAngle),
      center.dy + needleLength * math.sin(needleAngle),
    );
    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = shortest * 0.014
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);
    canvas.drawCircle(center, shortest * 0.026, Paint()..color = Colors.white);
    canvas.drawCircle(
        center, shortest * 0.014, Paint()..color = AppColors.violet);
  }

  @override
  bool shouldRepaint(covariant _SpeedGaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.maxValue != maxValue;
}
