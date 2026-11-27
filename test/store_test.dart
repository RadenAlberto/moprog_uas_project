import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:project_uts/DATA/store_data.dart';
import 'package:project_uts/MODELS/store_model.dart';
import 'package:project_uts/SCREENS/store_locator_page.dart';
import 'package:project_uts/SERVICES/api_service.dart';
import 'package:project_uts/UTILS/key_value_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StoreLocation', () {
    test('data toko fallback tersedia dan ID unik', () {
      expect(kStores, isNotEmpty);
      final ids = kStores.map((store) => store.id).toSet();
      expect(ids.length, kStores.length);
    });

    test('semua toko memiliki informasi dasar', () {
      for (final store in kStores) {
        expect(store.id, isNotEmpty);
        expect(store.name, isNotEmpty);
        expect(store.mall, isNotEmpty);
        expect(store.city, isNotEmpty);
        expect(store.address, isNotEmpty);
      }
    });

    test('format jam operasional benar', () {
      const store = StoreLocation(
        id: 'test1',
        name: 'UNIQLO Test',
        mall: 'Test Mall',
        city: 'Jakarta',
        address: 'Jl. Test',
        openHour: 10,
        closeHour: 22,
      );

      expect(store.hoursLabel, '10.00 - 22.00');
    });

    test('status toko mengikuti jam operasional', () {
      const store = StoreLocation(
        id: 'test2',
        name: 'UNIQLO Test',
        mall: 'Test Mall',
        city: 'Jakarta',
        address: 'Jl. Test',
        openHour: 10,
        closeHour: 22,
      );

      expect(store.isOpenAt(DateTime(2026, 1, 1, 12)), isTrue);
      expect(store.isOpenAt(DateTime(2026, 1, 1, 9)), isFalse);
      expect(store.isOpenAt(DateTime(2026, 1, 1, 22)), isFalse);
    });

    test('mapsQuery memuat nama mall dan kota', () {
      const store = StoreLocation(
        id: 'test3',
        name: 'UNIQLO Test',
        mall: 'Grand Indonesia',
        city: 'Jakarta Pusat',
        address: 'Jl. Thamrin',
      );

      expect(store.mapsQuery, contains('Grand Indonesia'));
      expect(store.mapsQuery, contains('Jakarta Pusat'));
    });

    test('data toko server dapat dikonversi dari JSON', () {
      final store = StoreLocation.fromJson({
        'id': 'ID001',
        'name': 'UNIQLO Test Mall',
        'mall': 'Test Mall',
        'city': 'Jakarta Selatan',
        'province': 'DKI Jakarta',
        'address': 'Jl. Contoh',
        'phone': '021123456',
        'lat': -6.2,
        'lng': 106.8,
        'open_hour': 10,
        'close_hour': 22,
        'services': ['Pickup pesanan'],
      });

      expect(store.id, 'ID001');
      expect(store.province, 'DKI Jakarta');
      expect(store.latitude, -6.2);
      expect(store.longitude, 106.8);
      expect(store.services, contains('Pickup pesanan'));
    });
  });

  group('StoreLocatorPage', () {
    testWidgets('menampilkan daftar toko fallback', (tester) async {
      final api = ApiService(store: MemoryStore());
      addTearDown(api.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ApiService>.value(
          value: api,
          child: const MaterialApp(home: StoreLocatorPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TEMUKAN TOKO'), findsOneWidget);
      expect(find.text('${kStores.length} toko'), findsOneWidget);
      expect(find.text('UNIQLO Grand Indonesia'), findsOneWidget);
    });

    testWidgets('pencarian toko berdasarkan nama mall berfungsi',
        (tester) async {
      final api = ApiService(store: MemoryStore());
      addTearDown(api.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ApiService>.value(
          value: api,
          child: const MaterialApp(home: StoreLocatorPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Grand Indonesia');
      await tester.pumpAndSettle();

      expect(find.text('UNIQLO Grand Indonesia'), findsOneWidget);
      expect(find.text('1 toko'), findsOneWidget);
    });

    testWidgets('menampilkan pesan saat toko tidak ditemukan',
        (tester) async {
      final api = ApiService(store: MemoryStore());
      addTearDown(api.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<ApiService>.value(
          value: api,
          child: const MaterialApp(home: StoreLocatorPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'toko tidak tersedia');
      await tester.pumpAndSettle();

      expect(find.text('Toko tidak ditemukan'), findsOneWidget);
    });
  });
}
