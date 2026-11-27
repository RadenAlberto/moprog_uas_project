import 'package:flutter/material.dart';

import '../MODELS/style_model.dart';

/// Ikon garis sederhana untuk tiap bentuk wajah.
class FaceShapeIcon extends StatelessWidget {
  const FaceShapeIcon({
    super.key,
    required this.shape,
    this.color = Colors.black87,
    this.width = 38,
    this.height = 46,
  });

  final FaceShape shape;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _FaceShapePainter(shape, color),
    );
  }
}

class _FaceShapePainter extends CustomPainter {
  const _FaceShapePainter(this.shape, this.color);

  final FaceShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final center = Offset(size.width / 2, size.height / 2);
    final w = size.width - 4;
    final h = size.height - 4;

    switch (shape) {
      case FaceShape.oval:
        canvas.drawOval(
          Rect.fromCenter(center: center, width: w * 0.82, height: h),
          paint,
        );
      case FaceShape.round:
        canvas.drawOval(
          Rect.fromCenter(center: center, width: w, height: w),
          paint,
        );
      case FaceShape.square:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center, width: w * 0.9, height: h * 0.88),
            const Radius.circular(9),
          ),
          paint,
        );
      case FaceShape.heart:
        final left = center.dx - w / 2;
        final right = center.dx + w / 2;
        final top = center.dy - h / 2;
        final bottom = center.dy + h / 2;
        final path = Path()
          ..moveTo(left, top + h * 0.2)
          ..quadraticBezierTo(left, top, center.dx, top)
          ..quadraticBezierTo(right, top, right, top + h * 0.2)
          ..quadraticBezierTo(
            right - w * 0.08,
            top + h * 0.68,
            center.dx,
            bottom,
          )
          ..quadraticBezierTo(
            left + w * 0.08,
            top + h * 0.68,
            left,
            top + h * 0.2,
          )
          ..close();
        canvas.drawPath(path, paint);
      case FaceShape.oblong:
        canvas.drawOval(
          Rect.fromCenter(center: center, width: w * 0.66, height: h),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.color != color;
}
