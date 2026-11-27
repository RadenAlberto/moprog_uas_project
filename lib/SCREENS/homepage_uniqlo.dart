import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/checkin_actions.dart';
import '../UTILS/nav.dart';
import '../UTILS/time_utils.dart';
import '../WIDGETS/app_logo.dart';
import '../WIDGETS/flash_sale.dart';
import '../WIDGETS/hero_carousel.dart';
import '../WIDGETS/news_widgets.dart';
import '../WIDGETS/product_card.dart';
import '../WIDGETS/section_header.dart';
import '../WIDGETS/ui_kit.dart';
import '../WIDGETS/style_banner.dart';
import '../WIDGETS/video_widgets.dart';
import 'information_page.dart';
import 'news_list_page.dart';
import 'notifications_page.dart';
import 'search_page.dart';
import 'size_guide_page.dart';
import 'store_locator_page.dart';
import 'video_list_page.dart';
import 'vouchers_page.dart';

const List<String> _homeCategories = [
  'Men',
  'Women',
  'Kids',
  'Baby',
  'Outerwear',
  'Innerwear',
  'Accessories',
];

/// Beranda: banner promo, aksi cepat, Flash Sale, produk, video, dan berita.
class UniqloHomePage extends StatelessWidget {
  const UniqloHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final heroItems = appState.news.where((n) => n.isPinned).take(5).toList();
    final hero = heroItems.isEmpty ? appState.news.take(3).toList() : heroItems;
    final recentlyViewed = appState.recentlyViewed;
    final newArrivals = appState.newArrivals;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                const _HomeHeader(),
                const _SearchField(),
                const SizedBox(height: 14),
                HeroCarousel(items: hero),
                const SizedBox(height: 18),
                const StyleBanner(),
                const SizedBox(height: 18),
                const _QuickActions(),
                const SizedBox(height: 22),
                const SectionHeader(title: 'Kategori'),
                const SizedBox(height: 10),
                _CategoryChips(onSelected: appState.showCategory),
                const SizedBox(height: 22),
                const FlashSaleSection(),
                const SizedBox(height: 22),
                const SectionHeader(
                  title: 'Terlaris',
                  subtitle: 'Produk dengan rating terbaik',
                ),
                HorizontalProductList(
                  products: appState.topRated(),
                  showRank: true,
                ),
                if (newArrivals.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const SectionHeader(
                    title: 'Produk Baru',
                    subtitle: 'Baru masuk koleksi',
                  ),
                  HorizontalProductList(products: newArrivals),
                ],
                if (recentlyViewed.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const SectionHeader(title: 'Terakhir Dilihat'),
                  HorizontalProductList(products: recentlyViewed),
                ],
                const SizedBox(height: 16),
                SectionHeader(
                  title: 'Video UNIQLO',
                  subtitle: 'Teknologi dan filosofi LifeWear',
                  actionLabel: 'Lihat semua',
                  onAction: () => pushPage(context, const VideoListPage()),
                ),
                const SizedBox(height: 8),
                const VideoStrip(),
                const SizedBox(height: 16),
                SectionHeader(
                  title: 'Berita & Info',
                  actionLabel: 'Lihat semua',
                  onAction: () => pushPage(context, const NewsListPage()),
                ),
                const SizedBox(height: 10),
                NewsCarousel(items: appState.news.take(6).toList()),
                const SizedBox(height: 22),
                SectionHeader(
                  title: 'Rekomendasi Produk',
                  actionLabel: 'Lihat semua',
                  onAction: () => appState.showCategory('Semua'),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const ProductGridDelegate(),
                    itemCount: appState.allProducts.take(8).length,
                    itemBuilder: (context, index) =>
                        ProductCard(product: appState.allProducts[index]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo, sapaan, dan tombol notifikasi.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final member = context.select<AuthProvider, String?>(
      (auth) => auth.currentMember?.firstName,
    );
    final unread = context.select<AppState, int>((s) => s.unreadNewsCount);
    final greeting = greetingFor(DateTime.now());

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const AppLogo(size: 42, radius: 4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UNIQLO PLUS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.4,
                  ),
                ),
                Text(
                  member == null ? 'LifeWear untuk semua' : '$greeting, $member',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Informasi',
            icon: const Icon(Icons.info_outline, color: Colors.black87),
            onPressed: () => pushPage(context, const InformationPage()),
          ),
          IconButton(
            tooltip: 'Notifikasi',
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(
                Icons.notifications_none_outlined,
                color: Colors.black87,
              ),
            ),
            onPressed: () => pushPage(context, const NotificationsPage()),
          ),
        ],
      ),
    );
  }
}

/// Kolom pencarian palsu: ketuk untuk membuka halaman pencarian.
class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () => pushPage(context, const SearchPage()),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(Icons.search, color: Colors.black54),
              SizedBox(width: 8),
              Text(
                'Cari AIRism, HEATTECH, Kemeja...',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _QuickAction(
            icon: Icons.auto_awesome,
            label: 'Stylist',
            onTap: () => openStylist(context),
          ),
          _QuickAction(
            icon: Icons.event_available_outlined,
            label: 'Check-in',
            onTap: () => performCheckIn(context),
          ),
          _QuickAction(
            icon: Icons.local_offer_outlined,
            label: 'Voucher',
            onTap: () => pushPage(context, const VouchersPage()),
          ),
          _QuickAction(
            icon: Icons.storefront_outlined,
            label: 'Toko',
            onTap: () => pushPage(context, const StoreLocatorPage()),
          ),
          _QuickAction(
            icon: Icons.straighten,
            label: 'Ukuran',
            onTap: () => pushPage(context, const SizeGuidePage()),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              IconBadge(icon: icon, size: 50),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _homeCategories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _homeCategories[index];
          return ActionChip(
            label: Text(category),
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.line),
            labelStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
            onPressed: () => onSelected(category),
          );
        },
      ),
    );
  }
}
