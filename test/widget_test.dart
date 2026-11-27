import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_uts/APP/app_providers.dart';
import 'package:project_uts/DATA/product_data.dart';
import 'package:project_uts/WIDGETS/app_network_image.dart';
import 'package:project_uts/MODELS/member_model.dart';
import 'package:project_uts/MODELS/pricing.dart';
import 'package:project_uts/PROVIDERS/app_state.dart';
import 'package:project_uts/SCREENS/main_navigation.dart';
import 'package:project_uts/SERVICES/photo_store.dart';
import 'package:project_uts/UTILS/key_value_store.dart';

/// Membangun [AppState] dan mengambil [BuildContext] (dibutuhkan untuk toast).
Future<(AppState, BuildContext)> _setup(WidgetTester tester) async {
  final state = AppState(store: MemoryStore());
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return (state, captured);
}

void main() {
  // Katalog Uniqlo dimuat dari assets/data/products.json.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppNetworkImage.useCache = false; // tanpa plugin penyimpanan di test
    await loadProductCatalog();
  });

  group('UNIQLO PLUS', () {
    testWidgets('Navigasi utama tampil dengan 6 tab', (tester) async {
      await tester.pumpWidget(
        AppProviders(
          store: MemoryStore(),
          autoSync: false,
          photoStore: MemoryPhotoStore(),
          child: const MaterialApp(home: MainNavigation()),
        ),
      );

      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Katalog'), findsOneWidget);
      expect(find.text('Wishlist'), findsOneWidget);
      expect(find.text('Keranjang'), findsOneWidget);
      expect(find.text('Keanggotaan'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);

      // Bongkar pohon widget agar timer (Flash Sale, banner) dibatalkan.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Keranjang: tambah, ubah jumlah, hapus', (tester) async {
      final (state, context) = await _setup(tester);
      final product = state.allProducts.first;
      final size = product.availableSizes.first;
      final color = product.availableColors.first;

      state.addToCart(product, size, color, context);
      state.addToCart(product, size, color, context);
      expect(state.cart.length, 1, reason: 'produk yang sama digabung');
      expect(state.cartCount, 2);

      state.updateQuantity(0, 1);
      expect(state.cartCount, 3);
      expect(state.selectedCartTotal, product.price * 3);

      state.updateQuantity(0, -3);
      expect(state.cart, isEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Keranjang tamu digabung ke akun saat login', (tester) async {
      final (state, context) = await _setup(tester);
      final product = state.allProducts.first;

      state.setActiveMember(null);
      state.addToCart(
        product,
        product.availableSizes.first,
        product.availableColors.first,
        context,
      );

      state.setActiveMember('UNQ12345678');
      expect(state.cart.length, 1);

      state.setActiveMember(null);
      expect(state.cart, isEmpty, reason: 'keranjang tamu sudah pindah ke akun');

      state.setActiveMember('UNQ12345678');
      expect(state.cart.length, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Pencarian dan pindah tab', (tester) async {
      final (state, _) = await _setup(tester);

      expect(state.searchProducts('jaket'), isNotEmpty);
      expect(state.searchProducts('zzzzqqq'), isEmpty);

      state.showCategory('Women');
      expect(state.currentTab, 1);
      expect(state.catalogCategory, 'Women');
      expect(state.catalogProducts('Women'), isNotEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    test('Harga: tamu tidak mendapat diskon level', () {
      final guest = calculatePrice(subtotal: 500000, isMember: false);
      expect(guest.memberDiscount, 0);
      expect(guest.pointsEarned, 0);

      final member = calculatePrice(
        subtotal: 500000,
        isMember: true,
        tier: MemberTier.platinum,
      );
      expect(member.memberDiscount, greaterThan(0));
    });
  });
}
