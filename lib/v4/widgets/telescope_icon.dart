import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 24dp 单色线形望远镜。几何与 assets/icon/telescope.svg 保持一致。
class V4TelescopeIcon extends StatelessWidget {
  final double size;
  final Color? color;
  final String? semanticsLabel;

  const V4TelescopeIcon({
    super.key,
    this.size = 24,
    this.color,
    this.semanticsLabel = '精读',
  });

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final icon = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TelescopePainter(resolved)),
    );
    if (semanticsLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(label: semanticsLabel, image: true, child: icon);
  }
}

class _TelescopePainter extends CustomPainter {
  final Color color;
  const _TelescopePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.scale(scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.save();
    canvas.translate(11, 9);
    canvas.rotate(-32 * math.pi / 180);
    canvas.translate(-11, -9);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, 6.5, 13.5, 5),
        const Radius.circular(1),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(7, 6.5), const Offset(7, 11.5), stroke);
    canvas.drawLine(const Offset(15, 6.5), const Offset(15, 11.5), stroke);
    final eyepiece = Path()
      ..moveTo(4, 8)
      ..lineTo(2.5, 8)
      ..lineTo(2.5, 10)
      ..lineTo(4, 10);
    canvas.drawPath(eyepiece, stroke);
    canvas.restore();

    canvas.drawCircle(const Offset(10.6, 12.7), 1, stroke);
    canvas.drawLine(const Offset(10.6, 13.7), const Offset(10.6, 15.1), stroke);
    canvas.drawLine(const Offset(10.6, 15.1), const Offset(6.5, 21), stroke);
    canvas.drawLine(const Offset(10.6, 15.1), const Offset(14.7, 21), stroke);
    canvas.drawLine(const Offset(10.6, 15.1), const Offset(10.6, 21), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TelescopePainter oldDelegate) =>
      oldDelegate.color != color;
}
