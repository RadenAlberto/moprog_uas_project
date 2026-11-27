import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/member_model.dart';
import '../MODELS/pricing.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/formatters.dart';

/// Penjelasan level member, keuntungan tiap level, dan cara kerja poin.
class MemberBenefitsPage extends StatelessWidget {
  const MemberBenefitsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final currentTier = auth.isLoggedIn ? auth.tier : null;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'KEUNTUNGAN MEMBER',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Level dihitung otomatis dari total belanja kumulatif '
                    '(tanpa ongkir dan pesanan yang dibatalkan).',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final tier in MemberTier.values)
                    _TierCard(tier: tier, isCurrent: tier == currentTier),
                  const SizedBox(height: 6),
                  const Text(
                    'Cara Kerja Poin',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bullet(
                          'Dapatkan 1 poin setiap belanja '
                          '${formatRupiah(PricingRules.spendPerPoint)}, dikali pengali level.',
                        ),
                        _Bullet(
                          '1 poin bernilai ${formatRupiah(PricingRules.pointValue)} '
                          'saat ditukar di halaman checkout.',
                        ),
                        _Bullet(
                          'Poin dapat dipakai hingga '
                          '${(PricingRules.maxPointsShare * 100).round()}% dari nilai belanja.',
                        ),
                        _Bullet(
                          'Bonus pendaftaran ${PricingRules.welcomeBonusPoints} poin untuk member baru.',
                        ),
                        const _Bullet(
                          'Jika pesanan dibatalkan, poin yang dipakai dikembalikan '
                          'dan poin yang didapat dibatalkan.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.isCurrent});

  final MemberTier tier;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? tier.accent : Colors.grey.shade200,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              gradient: LinearGradient(colors: tier.gradient),
            ),
            child: Row(
              children: [
                Icon(tier.icon, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tier.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        tier.minSpend == 0
                            ? 'Otomatis saat mendaftar'
                            : 'Belanja kumulatif ${formatRupiah(tier.minSpend)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'LEVEL ANDA',
                      style: TextStyle(
                        color: tier.gradient.first,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final benefit in tier.benefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle, size: 16, color: tier.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            benefit,
                            style: const TextStyle(fontSize: 12.5, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: Color(0xFFEC1C24)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
