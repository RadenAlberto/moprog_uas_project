import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/studio_models.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/tracker_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/toast.dart';
import 'cart_page.dart';
import 'daftarprodukpage_uniqlo.dart';
import 'homepage_uniqlo.dart';
import 'membership_page.dart';
import 'studio_page.dart';
import 'wishlist_page.dart';

/// Kerangka utama: 6 tab (Home, Katalog, Wishlist, Keranjang, Keanggotaan,
/// Studio). Tab aktif disimpan di [AppState] agar halaman lain bisa berpindah
/// tab (mis. "Beli lagi" membuka Keranjang).
///
/// Di layar lebar (laptop/tablet) navigasi pindah ke samping (NavigationRail).
class MainNavigation extends StatelessWidget {
  const MainNavigation({super.key});

  static const List<Widget> _pages = [
    UniqloHomePage(),
    ProductListPage(),
    WishlistPage(),
    CartPage(),
    MembershipPage(),
    StudioPage(),
  ];

  /// Lebar minimum untuk navigasi samping.
  static const double _wideBreakpoint = 840;

  @override
  Widget build(BuildContext context) {
    final currentTab = context.select<AppState, int>((s) => s.currentTab);
    final wishlistCount =
        context.select<AppState, int>((s) => s.wishlist.length);
    final cartCount = context.select<AppState, int>((s) => s.cartCount);
    final unreadAlerts =
        context.select<TrackerProvider, int>((t) => t.unreadCount);
    final appState = context.read<AppState>();

    Widget badged(Widget icon, int count) => Badge(
          label: Text('$count'),
          isLabelVisible: count > 0,
          child: icon,
        );

    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    final Widget body = wide
        ? Row(
            children: [
              NavigationRail(
                selectedIndex: currentTab,
                onDestinationSelected: appState.setTab,
                labelType: NavigationRailLabelType.all,
                backgroundColor: Colors.white,
                selectedIconTheme: const IconThemeData(color: AppColors.red),
                selectedLabelTextStyle: const TextStyle(
                  color: AppColors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelTextStyle: const TextStyle(
                  color: Colors.black54,
                  fontSize: 11,
                ),
                destinations: [
                  const NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text('Home'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.grid_view),
                    label: Text('Katalog'),
                  ),
                  NavigationRailDestination(
                    icon: badged(const Icon(Icons.favorite_border), wishlistCount),
                    selectedIcon: badged(const Icon(Icons.favorite), wishlistCount),
                    label: const Text('Wishlist'),
                  ),
                  NavigationRailDestination(
                    icon: badged(const Icon(Icons.shopping_bag_outlined), cartCount),
                    selectedIcon: badged(const Icon(Icons.shopping_bag), cartCount),
                    label: const Text('Keranjang'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: Text('Keanggotaan'),
                  ),
                  NavigationRailDestination(
                    icon: badged(const Icon(Icons.auto_awesome_outlined), unreadAlerts),
                    selectedIcon: badged(const Icon(Icons.auto_awesome), unreadAlerts),
                    label: const Text('Studio'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1, thickness: 1, color: AppColors.line),
              Expanded(child: IndexedStack(index: currentTab, children: _pages)),
            ],
          )
        : IndexedStack(index: currentTab, children: _pages);

    return TrackerAlertHost(
      child: PopScope(
        // Tombol kembali di tab selain Home membawa pengguna ke Home dulu.
        canPop: currentTab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) appState.setTab(0);
        },
        child: Scaffold(
          body: body,
          bottomNavigationBar: wide
              ? null
              : BottomNavigationBar(
                  currentIndex: currentTab,
                  onTap: appState.setTab,
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.white,
                  selectedItemColor: AppColors.red,
                  unselectedItemColor: Colors.black54,
                  selectedFontSize: 11,
                  unselectedFontSize: 11,
                  items: [
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.home_outlined),
                      activeIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.grid_view),
                      label: 'Katalog',
                    ),
                    BottomNavigationBarItem(
                      icon: badged(const Icon(Icons.favorite_border), wishlistCount),
                      activeIcon: badged(const Icon(Icons.favorite), wishlistCount),
                      label: 'Wishlist',
                    ),
                    BottomNavigationBarItem(
                      icon: badged(
                        const Icon(Icons.shopping_bag_outlined),
                        cartCount,
                      ),
                      activeIcon: badged(const Icon(Icons.shopping_bag), cartCount),
                      label: 'Keranjang',
                    ),
                    const BottomNavigationBarItem(
                      icon: Icon(Icons.person_outline),
                      activeIcon: Icon(Icons.person),
                      label: 'Keanggotaan',
                    ),
                    BottomNavigationBarItem(
                      icon: badged(
                        const Icon(Icons.auto_awesome_outlined),
                        unreadAlerts,
                      ),
                      activeIcon: badged(
                        const Icon(Icons.auto_awesome),
                        unreadAlerts,
                      ),
                      label: 'Studio',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Menampilkan notifikasi Price Tracker sebagai banner di atas layar
/// (seperti push notification) selama aplikasi terbuka.
class TrackerAlertHost extends StatefulWidget {
  const TrackerAlertHost({super.key, required this.child});

  final Widget child;

  @override
  State<TrackerAlertHost> createState() => _TrackerAlertHostState();
}

class _TrackerAlertHostState extends State<TrackerAlertHost> {
  StreamSubscription<TrackerAlert>? _sub;
  TrackerProvider? _tracker;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tracker = context.read<TrackerProvider>();
    if (!identical(tracker, _tracker)) {
      _sub?.cancel();
      _tracker = tracker;
      _sub = tracker.alertStream.listen(_show);
    }
  }

  void _show(TrackerAlert alert) {
    if (!mounted) return;
    showAppToast(
      context,
      '${alert.title}: ${alert.body}',
      color: alert.kind.color,
      icon: alert.kind.icon,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
