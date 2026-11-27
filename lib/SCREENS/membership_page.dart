import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../DATA/voucher_data.dart';
import '../MODELS/member_model.dart';
import '../MODELS/pricing.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../SERVICES/api_service.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/checkin_actions.dart';
import '../UTILS/formatters.dart';
import '../UTILS/nav.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/member_widgets.dart';
import '../WIDGETS/ui_kit.dart';
import 'activity_log_page.dart';
import 'edit_profile_page.dart';
import 'information_page.dart';
import 'login_page.dart';
import 'member_benefits_page.dart';
import 'news_list_page.dart';
import 'offline_photos_page.dart';
import 'notifications_page.dart';
import 'order_history_page.dart';
import 'payment_history_page.dart';
import 'point_history_page.dart';
import 'register_page.dart';
import 'size_guide_page.dart';
import 'spending_stats_page.dart';
import 'store_locator_page.dart';
import 'video_list_page.dart';
import 'vouchers_page.dart';

/// Tab "Keanggotaan": tampilan tamu (ajakan masuk/daftar) atau pusat akun member.
class MembershipPage extends StatelessWidget {
  const MembershipPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return auth.isLoggedIn ? const _MemberHub() : const _GuestView();
  }
}

// -----------------------------------------------------------------------------
// Tampilan tamu
// -----------------------------------------------------------------------------

class _GuestView extends StatelessWidget {
  const _GuestView();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('KEANGGOTAAN')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppShadows.lift,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.red, AppColors.redDark],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.card_membership,
                            color: Colors.white, size: 36),
                        const SizedBox(height: 12),
                        const Text(
                          'Jadi Member LifeWear',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Daftar gratis dan dapatkan ${PricingRules.welcomeBonusPoints} poin bonus, diskon otomatis, '
                          'voucher eksklusif, check-in harian, dan riwayat belanja lengkap.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: AppColors.red,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () =>
                                    pushPage(context, const LoginPage()),
                                child: const Text(
                                  'MASUK',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () =>
                                    pushPage(context, const RegisterPage()),
                                child: const Text(
                                  'DAFTAR',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Keuntungan Member',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const _BenefitRow(
                    icon: Icons.percent,
                    title: 'Diskon otomatis',
                    subtitle:
                        'Hemat 3% - 8% di setiap pembelian sesuai level member.',
                  ),
                  const _BenefitRow(
                    icon: Icons.stars_outlined,
                    title: 'Kumpulkan poin',
                    subtitle:
                        '1 poin tiap Rp10.000 belanja, tukar jadi potongan harga.',
                  ),
                  const _BenefitRow(
                    icon: Icons.event_available_outlined,
                    title: 'Check-in harian',
                    subtitle: 'Poin gratis setiap hari, makin banyak bila berturut-turut.',
                  ),
                  const _BenefitRow(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Pantau pembayaran',
                    subtitle:
                        'Riwayat pembelian, pembayaran, poin, dan statistik belanja.',
                  ),
                  const SizedBox(height: 6),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: Icons.menu_book_outlined,
                        title: 'Informasi',
                        subtitle: 'INSTRUCTION BOOK (Indonesia / English)',
                        onTap: () =>
                            pushPage(context, const InformationPage()),
                      ),
                      _MenuTile(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Lihat semua level member',
                        onTap: () =>
                            pushPage(context, const MemberBenefitsPage()),
                      ),
                      _MenuTile(
                        icon: Icons.newspaper_outlined,
                        title: 'Berita & Info',
                        badgeCount: appState.unreadNewsCount,
                        onTap: () => pushPage(context, const NewsListPage()),
                      ),
                      _MenuTile(
                        icon: Icons.local_offer_outlined,
                        title: 'Voucher',
                        onTap: () => pushPage(context, const VouchersPage()),
                      ),
                      _MenuTile(
                        icon: Icons.smart_display_outlined,
                        title: 'Video UNIQLO',
                        onTap: () => pushPage(context, const VideoListPage()),
                      ),
                      _MenuTile(
                        icon: Icons.storefront_outlined,
                        title: 'Temukan Toko',
                        onTap: () =>
                            pushPage(context, const StoreLocatorPage()),
                      ),
                      _MenuTile(
                        icon: Icons.straighten,
                        title: 'Panduan Ukuran',
                        onTap: () => pushPage(context, const SizeGuidePage()),
                      ),
                      _MenuTile(
                        icon: Icons.download_for_offline_outlined,
                        title: 'Foto untuk Offline',
                        subtitle: 'Simpan foto produk di perangkat',
                        onTap: () =>
                            pushPage(context, const OfflinePhotosPage()),
                      ),
                    ],
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

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    height: 1.3,
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

// -----------------------------------------------------------------------------
// Pusat akun member
// -----------------------------------------------------------------------------

class _MemberHub extends StatelessWidget {
  const _MemberHub();

  Future<void> _confirmLogout(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Poin, level, riwayat belanja, riwayat pembayaran, keranjang, dan '
          'wishlist Anda tetap tersimpan. Semuanya akan muncul lagi saat Anda '
          'masuk kembali, dan belanja berikutnya menambah progres yang sama.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Keluar',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await auth.logout();
    if (!context.mounted) return;
    showAppToast(
      context,
      'Anda telah keluar. Progres belanja tetap tersimpan.',
      color: Colors.grey.shade900,
      icon: Icons.logout,
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ApiService>(); // refresh voucher dari control panel
    final auth = context.watch<AuthProvider>();
    final appState = context.watch<AppState>();
    final member = auth.currentMember;
    if (member == null) return const SizedBox.shrink();

    final tier = auth.tier;
    final orders = auth.myOrders;
    final eligibleVouchers = kVouchers
        .where((v) =>
            v.validate(
              subtotal: double.maxFinite,
              isMember: true,
              tier: tier,
            ) ==
            null)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AKUN SAYA'),
        actions: [
          IconButton(
            tooltip: 'Notifikasi',
            icon: Badge(
              isLabelVisible: appState.unreadNewsCount > 0,
              label: Text('${appState.unreadNewsCount}'),
              child: const Icon(Icons.notifications_none_outlined),
            ),
            onPressed: () => pushPage(context, const NotificationsPage()),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!auth.isPersistent) ...[
                    const _StorageWarning(),
                    const SizedBox(height: 12),
                  ],
                  MemberCardWidget(
                    member: member,
                    tier: tier,
                    points: auth.points,
                  ),
                  const SizedBox(height: 6),
                  const Center(
                    child: Text(
                      'Tunjukkan kartu ini saat berbelanja di toko',
                      style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _CheckInCard(),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          icon: Icons.stars_outlined,
                          label: 'Poin',
                          value: '${auth.points}',
                          caption:
                              '= ${formatRupiah(auth.points * PricingRules.pointValue)}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.payments_outlined,
                          label: 'Total Belanja',
                          value: formatRupiahCompact(auth.totalSpend),
                          caption: 'level ${tier.label}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.receipt_long_outlined,
                          label: 'Pesanan',
                          value: '${orders.length}',
                          caption: auth.activeOrderCount > 0
                              ? '${auth.activeOrderCount} aktif'
                              : 'tidak ada aktif',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TierProgressCard(
                    tier: tier,
                    totalSpend: auth.totalSpend,
                    progress: auth.tierProgress,
                    amountToNext: auth.amountToNextTier,
                  ),
                  const _GroupTitle('Belanja Saya'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: Icons.history,
                        title: 'Riwayat Pembelian',
                        subtitle: orders.isEmpty
                            ? 'Belum ada pesanan'
                            : '${orders.length} pesanan',
                        badgeCount: auth.activeOrderCount,
                        onTap: () => pushPage(context, const OrderHistoryPage()),
                      ),
                      _MenuTile(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Riwayat Pembayaran',
                        subtitle: 'Status, metode, dan nomor referensi',
                        onTap: () =>
                            pushPage(context, const PaymentHistoryPage()),
                      ),
                      _MenuTile(
                        icon: Icons.insights_outlined,
                        title: 'Statistik Belanja',
                        subtitle: 'Grafik bulanan dan kategori favorit',
                        onTap: () =>
                            pushPage(context, const SpendingStatsPage()),
                      ),
                    ],
                  ),
                  const _GroupTitle('Poin & Reward'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: Icons.stars_outlined,
                        title: 'Riwayat Poin',
                        subtitle: '${auth.points} poin tersedia',
                        onTap: () => pushPage(context, const PointHistoryPage()),
                      ),
                      _MenuTile(
                        icon: Icons.local_offer_outlined,
                        title: 'Voucher Saya',
                        subtitle: '$eligibleVouchers voucher bisa dipakai',
                        onTap: () => pushPage(context, const VouchersPage()),
                      ),
                      _MenuTile(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Keuntungan Member',
                        onTap: () =>
                            pushPage(context, const MemberBenefitsPage()),
                      ),
                    ],
                  ),
                  const _GroupTitle('Jelajahi'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: Icons.menu_book_outlined,
                        title: 'Informasi',
                        subtitle: 'INSTRUCTION BOOK (Indonesia / English)',
                        onTap: () =>
                            pushPage(context, const InformationPage()),
                      ),
                      _MenuTile(
                        icon: Icons.newspaper_outlined,
                        title: 'Berita & Info',
                        subtitle: 'Promo, koleksi, dan informasi terbaru',
                        badgeCount: appState.unreadNewsCount,
                        onTap: () => pushPage(context, const NewsListPage()),
                      ),
                      _MenuTile(
                        icon: Icons.smart_display_outlined,
                        title: 'Video UNIQLO',
                        onTap: () => pushPage(context, const VideoListPage()),
                      ),
                      _MenuTile(
                        icon: Icons.storefront_outlined,
                        title: 'Temukan Toko',
                        onTap: () =>
                            pushPage(context, const StoreLocatorPage()),
                      ),
                      _MenuTile(
                        icon: Icons.straighten,
                        title: 'Panduan Ukuran',
                        onTap: () => pushPage(context, const SizeGuidePage()),
                      ),
                      _MenuTile(
                        icon: Icons.download_for_offline_outlined,
                        title: 'Foto untuk Offline',
                        subtitle: 'Simpan foto produk di perangkat',
                        onTap: () =>
                            pushPage(context, const OfflinePhotosPage()),
                      ),
                    ],
                  ),
                  const _GroupTitle('Akun'),
                  _MenuGroup(
                    children: [
                      _MenuTile(
                        icon: Icons.person_outline,
                        title: 'Edit Profil & Password',
                        subtitle: member.email,
                        onTap: () => pushPage(context, const EditProfilePage()),
                      ),
                      _MenuTile(
                        icon: Icons.manage_history,
                        title: 'Aktivitas Akun',
                        subtitle: 'Catatan masuk, belanja, dan ulasan',
                        onTap: () => pushPage(context, const ActivityLogPage()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.red,
                      side: const BorderSide(color: AppColors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => _confirmLogout(context),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text(
                      'KELUAR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Data akun dan progres belanja Anda tetap tersimpan setelah keluar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5),
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

class _StorageWarning extends StatelessWidget {
  const _StorageWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: Color(0xFFEF6C00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Penyimpanan permanen tidak tersedia, jadi data hanya bertahan '
              'selama aplikasi terbuka. Jalankan "flutter pub get" lalu '
              'restart penuh (bukan hot reload) agar data tersimpan.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canCheckIn = auth.canCheckInToday();
    final streak = auth.currentStreak();
    final nextReward = AuthProvider.checkInReward(streak + 1);

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(
            icon: canCheckIn
                ? Icons.event_available_outlined
                : Icons.check_circle_outline,
            color: canCheckIn ? AppColors.red : AppColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canCheckIn ? 'Check-in harian' : 'Sudah check-in hari ini',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  canCheckIn
                      ? 'Dapatkan +$nextReward poin sekarang'
                      : 'Besok dapat +$nextReward poin',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                if (streak > 0)
                  Text(
                    '$streak hari berturut-turut',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.line,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: canCheckIn ? () => performCheckIn(context) : null,
            child: const Text(
              'CHECK-IN',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.red),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(const Divider(height: 1, indent: 56));
      items.add(children[i]);
    }
    return Container(
      decoration: cardDecoration(radius: 16),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(children: items),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.ink),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badgeCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }
}
