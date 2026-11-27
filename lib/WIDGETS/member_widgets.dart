import 'package:flutter/material.dart';

import '../MODELS/member_model.dart';
import '../UTILS/formatters.dart';
import 'app_logo.dart';

/// Lencana kecil level member.
class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier, this.dark = false});

  final MemberTier tier;

  /// `true` untuk latar terang (teks berwarna), `false` untuk di atas kartu
  /// gelap (teks putih).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? tier.gradient.first : Colors.white;
    final background = dark
        ? tier.accent.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.18);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tier.icon, size: 14, color: foreground),
          const SizedBox(width: 4),
          Text(
            tier.label.toUpperCase(),
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu member digital (gaya kartu keanggotaan di toko).
///
/// Barcode hanya hiasan visual yang dibentuk dari ID member, bukan barcode
/// yang bisa dipindai kasir.
class MemberCardWidget extends StatelessWidget {
  const MemberCardWidget({
    super.key,
    required this.member,
    required this.tier,
    required this.points,
  });

  final Member member;
  final MemberTier tier;
  final int points;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.55,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tier.gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: tier.gradient.first.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const AppLogo(size: 34, radius: 4),
                TierBadge(tier: tier),
              ],
            ),
            const Spacer(),
            Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              member.id,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13,
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POIN',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        '$points',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MEMBER SEJAK',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 10,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        formatDate(member.joinedAt),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              height: 30,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: CustomPaint(
                painter: _BarcodePainter(member.id, Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.data, this.color);

  final String data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    final widths = <int>[];
    for (final unit in data.codeUnits) {
      widths.add(1 + (unit % 3));
      widths.add(1 + ((unit ~/ 3) % 2));
    }
    final total = widths.fold<int>(0, (a, b) => a + b);
    if (total == 0) return;

    final unitWidth = size.width / total;
    var x = 0.0;
    for (var i = 0; i < widths.length; i++) {
      final w = widths[i] * unitWidth;
      if (i.isEven) {
        canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), paint);
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.color != color;
  }
}

/// Kartu progres menuju level berikutnya.
class TierProgressCard extends StatelessWidget {
  const TierProgressCard({
    super.key,
    required this.tier,
    required this.totalSpend,
    required this.progress,
    required this.amountToNext,
  });

  final MemberTier tier;
  final double totalSpend;
  final double progress;
  final double amountToNext;

  @override
  Widget build(BuildContext context) {
    final next = tier.next;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Progres Level',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              TierBadge(tier: tier, dark: true),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(tier.accent),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            next == null
                ? 'Selamat! Anda berada di level tertinggi (${tier.label}).'
                : 'Belanja ${formatRupiah(amountToNext)} lagi untuk naik ke ${next.label}.',
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total belanja kumulatif: ${formatRupiah(totalSpend)}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}
