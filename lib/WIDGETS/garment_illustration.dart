import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../MODELS/product_model.dart';

/// Jenis siluet pakaian untuk ilustrasi produk.
enum GarmentKind {
  tee,
  shirt,
  sweater,
  jacket,
  hoodie,
  pants,
  shorts,
  skirt,
  dress,
  socks,
  bag,
  cap,
  scarf,
  beanie,
}

/// Menebak siluet dari nama/kategori produk.
GarmentKind garmentFor(Product product) {
  final name = product.name.toLowerCase();
  final category = product.category.toLowerCase();
  bool has(List<String> keys) => keys.any(name.contains);

  if (has(['socks', 'kaos kaki'])) return GarmentKind.socks;
  if (has(['bag', 'tote', 'tas '])) return GarmentKind.bag;
  if (has(['beanie'])) return GarmentKind.beanie;
  if (has([' cap', 'bucket hat', 'topi'])) return GarmentKind.cap;
  if (has(['scarf', 'muffler', 'syal'])) return GarmentKind.scarf;
  if (has(['dress', 'gaun', 'terusan'])) return GarmentKind.dress;
  if (has(['skirt', 'rok '])) return GarmentKind.skirt;
  if (has(['shorts', 'celana pendek'])) return GarmentKind.shorts;
  if (has(['jeans', 'pants', 'leggings', 'chino', 'jogger', 'celana'])) {
    return GarmentKind.pants;
  }
  if (has(['hoodie'])) return GarmentKind.hoodie;
  if (has(['parka', 'jacket', 'jaket', 'mantel', 'blouson', 'trucker', 'coat'])) {
    return GarmentKind.jacket;
  }
  if (has([
    'sweatshirt',
    'sweater',
    'sweter',
    'cardigan',
    'turtleneck',
    'pajama',
    'pyjama',
    'relaxwear',
    'long sleeve',
  ])) {
    return GarmentKind.sweater;
  }
  if (has(['t-shirt', 'kaos', 'tank', 'polo', 'bodysuit', ' tee'])) {
    return GarmentKind.tee;
  }
  if (has(['shirt', 'blouse', 'kemeja', 'blus'])) return GarmentKind.shirt;

  switch (category) {
    case 'outerwear':
      return GarmentKind.jacket;
    case 'pants':
    case 'jeans':
      return GarmentKind.pants;
    case 'shirts':
      return GarmentKind.shirt;
    case 'accessories':
      return GarmentKind.bag;
    default:
      return GarmentKind.tee;
  }
}

Color _lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0).toDouble())
      .toColor();
}

Color _darken(Color c, double amount) => _lighten(c, -amount);

/// Ilustrasi pakaian yang digambar dengan kode (tanpa koneksi internet),
/// dipakai untuk produk yang belum punya foto atau saat foto gagal dimuat.
class GarmentIllustration extends StatelessWidget {
  const GarmentIllustration({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final color = product.availableColors.isNotEmpty
        ? product.availableColors.first
        : Colors.grey;
    final hsl = HSLColor.fromColor(color);
    final backdrop = hsl
        .withSaturation((hsl.saturation * 0.45).clamp(0.0, 1.0).toDouble())
        .withLightness(0.93)
        .toColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighten(backdrop, 0.04), _darken(backdrop, 0.04)],
        ),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: GarmentPainter(kind: garmentFor(product), color: color),
      ),
    );
  }
}

class GarmentPainter extends CustomPainter {
  GarmentPainter({required this.kind, required this.color});

  final GarmentKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height) * 0.64;
    if (side <= 0) return;

    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 100);

    // Bayangan lembut di bawah pakaian.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 97), width: 62, height: 5),
      Paint()..color = const Color(0x22000000),
    );

    final body = _bodyPath(kind);

    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_lighten(color, 0.07), _darken(color, 0.07)],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..color = _darken(color, 0.28);
    final detail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round
      ..color = _darken(color, 0.22);
    final detailFill = Paint()..color = _darken(color, 0.22);

    // Elemen di belakang badan utama (gagang tas).
    if (kind == GarmentKind.bag) {
      canvas.drawPath(
        Path()
          ..moveTo(36, 38)
          ..cubicTo(36, 8, 64, 8, 64, 38),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = _darken(color, 0.28),
      );
    }

    canvas.drawPath(body, fill);
    canvas.drawPath(body, outline);

    switch (kind) {
      case GarmentKind.tee:
        canvas.drawPath(
          Path()
            ..moveTo(38, 14)
            ..quadraticBezierTo(50, 28, 62, 14),
          detail,
        );
        break;
      case GarmentKind.shirt:
        canvas.drawPath(
          Path()
            ..moveTo(38, 12)
            ..lineTo(50, 32)
            ..lineTo(40, 26)
            ..close(),
          detail,
        );
        canvas.drawPath(
          Path()
            ..moveTo(62, 12)
            ..lineTo(50, 32)
            ..lineTo(60, 26)
            ..close(),
          detail,
        );
        canvas.drawLine(const Offset(50, 32), const Offset(50, 90), detail);
        for (final y in [42.0, 54.0, 66.0, 78.0]) {
          canvas.drawCircle(Offset(50, y), 1.3, detailFill);
        }
        break;
      case GarmentKind.sweater:
        canvas.drawPath(
          Path()
            ..moveTo(38, 14)
            ..quadraticBezierTo(50, 28, 62, 14),
          detail,
        );
        canvas.drawLine(const Offset(24, 84), const Offset(76, 84), detail);
        canvas.drawLine(const Offset(3, 76), const Offset(13, 78), detail);
        canvas.drawLine(const Offset(97, 76), const Offset(87, 78), detail);
        break;
      case GarmentKind.jacket:
        canvas.drawLine(const Offset(50, 20), const Offset(50, 90), detail);
        canvas.drawPath(
          Path()
            ..moveTo(38, 12)
            ..lineTo(42, 24)
            ..lineTo(50, 20)
            ..lineTo(58, 24)
            ..lineTo(62, 12),
          detail,
        );
        canvas.drawLine(const Offset(30, 66), const Offset(40, 70), detail);
        canvas.drawLine(const Offset(70, 66), const Offset(60, 70), detail);
        break;
      case GarmentKind.hoodie:
        canvas.drawPath(
          Path()
            ..moveTo(34, 14)
            ..quadraticBezierTo(50, -2, 66, 14)
            ..quadraticBezierTo(50, 30, 34, 14),
          detail,
        );
        canvas.drawLine(const Offset(45, 26), const Offset(45, 40), detail);
        canvas.drawLine(const Offset(55, 26), const Offset(55, 40), detail);
        canvas.drawPath(
          Path()
            ..moveTo(32, 68)
            ..lineTo(68, 68)
            ..lineTo(72, 86)
            ..lineTo(28, 86)
            ..close(),
          detail,
        );
        break;
      case GarmentKind.pants:
        canvas.drawLine(const Offset(26, 16), const Offset(74, 16), detail);
        canvas.drawLine(const Offset(50, 16), const Offset(50, 36), detail);
        canvas.drawPath(
          Path()
            ..moveTo(28, 18)
            ..quadraticBezierTo(34, 28, 40, 20),
          detail,
        );
        break;
      case GarmentKind.shorts:
        canvas.drawLine(const Offset(24, 21), const Offset(76, 21), detail);
        canvas.drawLine(const Offset(50, 21), const Offset(50, 40), detail);
        break;
      case GarmentKind.skirt:
        canvas.drawLine(const Offset(32, 20), const Offset(68, 20), detail);
        const tops = [40.0, 47.0, 53.0, 60.0];
        const bottoms = [24.0, 40.0, 60.0, 76.0];
        for (var i = 0; i < tops.length; i++) {
          canvas.drawLine(Offset(tops[i], 22), Offset(bottoms[i], 88), detail);
        }
        break;
      case GarmentKind.dress:
        canvas.drawLine(const Offset(36, 42), const Offset(64, 42), detail);
        canvas.drawPath(
          Path()
            ..moveTo(40, 44)
            ..quadraticBezierTo(30, 70, 22, 90),
          detail,
        );
        canvas.drawPath(
          Path()
            ..moveTo(60, 44)
            ..quadraticBezierTo(70, 70, 78, 90),
          detail,
        );
        break;
      case GarmentKind.socks:
        canvas.drawLine(const Offset(34, 14), const Offset(62, 14), detail);
        canvas.drawLine(const Offset(34, 20), const Offset(62, 20), detail);
        canvas.drawLine(const Offset(34, 26), const Offset(62, 26), detail);
        break;
      case GarmentKind.bag:
        canvas.drawLine(const Offset(20, 48), const Offset(80, 48), detail);
        break;
      case GarmentKind.cap:
        final brim = Path()
          ..moveTo(14, 58)
          ..lineTo(98, 58)
          ..quadraticBezierTo(100, 70, 72, 68)
          ..lineTo(14, 64)
          ..close();
        canvas.drawPath(brim, Paint()..color = _darken(color, 0.12));
        canvas.drawPath(brim, outline);
        canvas.drawCircle(const Offset(52, 23), 2.2, detailFill);
        canvas.drawLine(const Offset(52, 24), const Offset(52, 58), detail);
        break;
      case GarmentKind.scarf:
        for (final y in [24.0, 40.0, 56.0, 72.0]) {
          canvas.drawLine(
            Offset(36 + (y - 6) * 0.04, y),
            Offset(64 + (y - 6) * 0.06, y),
            detail,
          );
        }
        for (final x in [36.0, 42.0, 48.0, 54.0, 60.0]) {
          canvas.drawLine(Offset(x, 94), Offset(x, 99), detail);
        }
        break;
      case GarmentKind.beanie:
        final cuff = RRect.fromLTRBR(16, 58, 84, 80, const Radius.circular(6));
        canvas.drawRRect(cuff, Paint()..color = _darken(color, 0.1));
        canvas.drawRRect(cuff, outline);
        for (final x in [28.0, 38.0, 48.0, 58.0, 68.0]) {
          canvas.drawLine(Offset(x, 62), Offset(x, 76), detail);
        }
        break;
    }

    canvas.restore();
  }

  Path _bodyPath(GarmentKind kind) {
    switch (kind) {
      case GarmentKind.tee:
        return Path()
          ..moveTo(36, 12)
          ..quadraticBezierTo(50, 24, 64, 12)
          ..lineTo(82, 20)
          ..lineTo(97, 38)
          ..lineTo(85, 50)
          ..lineTo(75, 42)
          ..lineTo(75, 90)
          ..lineTo(25, 90)
          ..lineTo(25, 42)
          ..lineTo(15, 50)
          ..lineTo(3, 38)
          ..lineTo(18, 20)
          ..close();
      case GarmentKind.shirt:
      case GarmentKind.sweater:
      case GarmentKind.jacket:
      case GarmentKind.hoodie:
        return Path()
          ..moveTo(36, 12)
          ..quadraticBezierTo(50, 24, 64, 12)
          ..lineTo(82, 20)
          ..lineTo(96, 34)
          ..lineTo(98, 82)
          ..lineTo(86, 84)
          ..lineTo(76, 46)
          ..lineTo(76, 90)
          ..lineTo(24, 90)
          ..lineTo(24, 46)
          ..lineTo(14, 84)
          ..lineTo(2, 82)
          ..lineTo(4, 34)
          ..lineTo(18, 20)
          ..close();
      case GarmentKind.pants:
        return Path()
          ..moveTo(26, 8)
          ..lineTo(74, 8)
          ..lineTo(80, 92)
          ..lineTo(55, 92)
          ..lineTo(50, 36)
          ..lineTo(45, 92)
          ..lineTo(20, 92)
          ..close();
      case GarmentKind.shorts:
        return Path()
          ..moveTo(24, 14)
          ..lineTo(76, 14)
          ..lineTo(84, 62)
          ..lineTo(55, 62)
          ..lineTo(50, 40)
          ..lineTo(45, 62)
          ..lineTo(16, 62)
          ..close();
      case GarmentKind.skirt:
        return Path()
          ..moveTo(32, 12)
          ..lineTo(68, 12)
          ..lineTo(90, 88)
          ..quadraticBezierTo(50, 96, 10, 88)
          ..close();
      case GarmentKind.dress:
        return Path()
          ..moveTo(36, 6)
          ..lineTo(42, 6)
          ..quadraticBezierTo(50, 22, 58, 6)
          ..lineTo(64, 6)
          ..lineTo(68, 34)
          ..lineTo(62, 42)
          ..lineTo(90, 92)
          ..lineTo(10, 92)
          ..lineTo(38, 42)
          ..lineTo(32, 34)
          ..close();
      case GarmentKind.socks:
        return Path()
          ..moveTo(34, 6)
          ..lineTo(62, 6)
          ..lineTo(62, 58)
          ..quadraticBezierTo(62, 66, 76, 70)
          ..quadraticBezierTo(92, 76, 92, 86)
          ..quadraticBezierTo(92, 94, 82, 94)
          ..lineTo(42, 94)
          ..quadraticBezierTo(34, 94, 34, 84)
          ..close();
      case GarmentKind.bag:
        return Path()
          ..addRRect(
            RRect.fromLTRBR(20, 36, 80, 92, const Radius.circular(4)),
          );
      case GarmentKind.cap:
        return Path()
          ..moveTo(14, 58)
          ..quadraticBezierTo(14, 22, 52, 22)
          ..quadraticBezierTo(88, 22, 88, 58)
          ..close();
      case GarmentKind.scarf:
        return Path()
          ..moveTo(34, 6)
          ..lineTo(66, 6)
          ..lineTo(70, 58)
          ..lineTo(64, 94)
          ..lineTo(34, 94)
          ..lineTo(38, 58)
          ..close();
      case GarmentKind.beanie:
        return Path()
          ..moveTo(20, 62)
          ..quadraticBezierTo(20, 14, 50, 14)
          ..quadraticBezierTo(80, 14, 80, 62)
          ..close();
    }
  }

  @override
  bool shouldRepaint(covariant GarmentPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
