import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/tracker_provider.dart';
import '../PROVIDERS/wardrobe_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';
import 'fit_calculator_page.dart';
import 'ootd_page.dart';
import 'price_tracker_page.dart';
import 'stylist_page.dart';
import 'try_on_page.dart';
import 'wardrobe_page.dart';

/// Pusat fitur gaya: lemari digital, stylist, pelacak harga, ukuran, OOTD,
/// dan coba pakaian virtual.
class StudioPage extends StatelessWidget {
  const StudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<TrackerProvider, int>((t) => t.unreadCount);
    final trackedCount =
        context.select<TrackerProvider, int>((t) => t.items.length);
    final wardrobeCount =
        context.select<WardrobeProvider, int>((w) => w.items.length);

    final cards = <_FeatureCard>[
      _FeatureCard(
        icon: Icons.view_in_ar_outlined,
        title: 'Coba Virtual',
        subtitle: 'Tempelkan pakaian ke tubuhmu lewat kamera depan, belakang, '
            'atau webcam laptop.',
        onTap: () => pushPage(context, const TryOnPage()),
      ),
      _FeatureCard(
        icon: Icons.checkroom,
        title: 'Lemari Digital',
        subtitle: wardrobeCount == 0
            ? 'Foto pakaianmu, lalu dapatkan padu padan dengan produk baru.'
            : '$wardrobeCount pakaian tersimpan. Lihat padu padannya.',
        onTap: () => pushPage(context, const WardrobePage()),
      ),
      _FeatureCard(
        icon: Icons.auto_awesome,
        title: 'AI Stylist',
        subtitle: 'Outfit sesuai cuaca dan agenda harianmu.',
        onTap: () => pushPage(context, const StylistPage()),
      ),
      _FeatureCard(
        icon: Icons.notifications_active_outlined,
        title: 'Pelacak Harga & Stok',
        subtitle: trackedCount == 0
            ? 'Dapat kabar saat harga turun atau ukuranmu tersedia lagi.'
            : '$trackedCount produk dilacak'
                '${unread > 0 ? ', $unread notifikasi baru' : ''}.',
        badge: unread,
        onTap: () => pushPage(context, const PriceTrackerPage()),
      ),
      _FeatureCard(
        icon: Icons.straighten,
        title: 'Kalkulator Ukuran',
        subtitle: 'Prediksi ukuran dari tinggi, berat, dan gaya favoritmu.',
        onTap: () => pushPage(context, const FitCalculatorPage()),
      ),
      _FeatureCard(
        icon: Icons.groups_2_outlined,
        title: 'Komunitas OOTD',
        subtitle: 'Lihat dan bagikan outfit orang biasa, lengkap dengan '
            'produk dan ukuran yang dipakai.',
        onTap: () => pushPage(context, const OotdPage()),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('STUDIO')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 3
              : (constraints.maxWidth >= 560 ? 2 : 1);
          const gap = 12.0;
          final width = constraints.maxWidth - 32;
          final cardWidth = (width - gap * (columns - 1)) / columns;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Padukan pakaian lamamu dengan koleksi baru.',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Semua fitur berjalan di HP, tablet, dan laptop.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final c in cards) SizedBox(width: cardWidth, child: c),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(radius: 16, border: true, shadow: false),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.redSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.red),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (badge > 0) ...[
                          const SizedBox(width: 8),
                          Badge(label: Text('$badge')),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
