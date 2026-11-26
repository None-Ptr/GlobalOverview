import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:global_overview/v4/theme/v4_tokens.dart';

class V4ObservationRing extends StatelessWidget {
  final int current;
  final int goal;
  final double size;

  const V4ObservationRing({
    super.key,
    required this.current,
    required this.goal,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    final v4 = context.v4;
    final type = context.v4Type;
    final progress = goal <= 0 ? 0.0 : (current / goal).clamp(0.0, 1.0);
    return Semantics(
      excludeSemantics: true,
      label: '今日学习 ' + current.toString() + '，目标 ' + goal.toString(),
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(progress, track: v4.rule, arc: v4.brand),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  current.toString(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                    color: v4.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text('今日', style: type.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color track;
  final Color arc;
  const _RingPainter(this.progress, {required this.track, required this.arc});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc;
}
