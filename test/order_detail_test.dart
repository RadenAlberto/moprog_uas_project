import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:project_uts/DATA/product_data.dart';
import 'package:project_uts/MODELS/product_model.dart';
import 'package:project_uts/MODELS/pricing.dart';
import 'package:project_uts/PROVIDERS/auth_provider.dart';
import 'package:project_uts/SCREENS/order_history_page.dart';
import 'package:project_uts/SERVICES/api_service.dart';
import 'package:project_uts/UTILS/key_value_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthProvider auth;

  setUpAll(() async {
    await loadProductCatalog();
  });

  setUp(() async {
    auth = AuthProvider(store: MemoryStore());
    final error = await auth.register(
      name: 'Detail Tester',
      email: 'detail@example.com',
      phone: '081234567890',
      password: 'password123',
    );
    expect(error, isNull);

    final product = kProducts.first;
    final item = CartItem(
      product: product,
      selectedSize: product.availableSizes.first,
      selectedColor: product.availableColors.first,
    );
    final pricing = calculatePrice(
      subtotal: item.lineTotal,
      isMember: true,
      tier: auth.tier,
    );
    final order = await auth.placeOrder(
      items: [item],
      pricing: pricing,
      paymentMethod: 'Virtual Account BCA',
      recipient: 'Detail Tester',
      phone: '081234567890',
      address: 'Jl. Contoh No. 10, Jakarta',
      gatewayRef: 'TRX-DETAIL-1',
      paymentInfo: 'VA BCA 123456',
    );
    expect(order, isNotNull);
  });

  testWidgets('tombol Lihat Detail membuka rincian pesanan lengkap',
      (tester) async {
    final api = ApiService(store: MemoryStore());
    addTearDown(api.dispose);
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider<ApiService>.value(value: api),
        ],
        child: const MaterialApp(home: OrderHistoryPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lihat Detail'), findsOneWidget);
    await tester.tap(find.text('Lihat Detail'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL PESANAN'), findsOneWidget);
    expect(find.text('Informasi Pesanan'), findsOneWidget);
    expect(find.text('Status Pembayaran'), findsOneWidget);
    expect(find.text('Status Pesanan'), findsOneWidget);
    expect(find.textContaining('Detail Tester'), findsWidgets);
    expect(find.textContaining('Virtual Account BCA'), findsWidgets);
    expect(find.textContaining('Jl. Contoh No. 10'), findsWidgets);
    expect(find.textContaining('Produk ('), findsOneWidget);
    expect(find.text('Rincian Pembayaran'), findsOneWidget);
    expect(find.text('BATALKAN'), findsOneWidget);
    expect(find.text('BELI LAGI'), findsOneWidget);
  });
}
