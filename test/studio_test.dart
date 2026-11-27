import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_uts/DATA/product_data.dart';
import 'package:project_uts/MODELS/studio_models.dart';
import 'package:project_uts/MODELS/style_model.dart' show Gender;
import 'package:project_uts/PROVIDERS/app_state.dart';
import 'package:project_uts/PROVIDERS/tracker_provider.dart';
import 'package:project_uts/SERVICES/color_utils.dart';
import 'package:project_uts/SERVICES/fit_engine.dart';
import 'package:project_uts/SERVICES/outfit_engine.dart';
import 'package:project_uts/SERVICES/stylist_engine.dart';
import 'package:project_uts/SERVICES/weather_service.dart';
import 'package:project_uts/UTILS/key_value_store.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadProductCatalog();
  });

  test('Nama dan keserasian warna', () {
    expect(colorNameId(const Color(0xFF000000)), 'Hitam');
    expect(colorNameId(const Color(0xFFFFFFFF)), 'Putih');
    expect(colorHarmony(const Color(0xFF000000), const Color(0xFFEC1C24)).kind,
        HarmonyKind.neutral);
  });

  test('Mix & match memberi produk bawahan/luaran untuk atasan', () {
    final item = WardrobeItem(
      id: 'w1',
      name: 'Kaos putih',
      slot: ClothingSlot.top,
      colorArgb: 0xFFFFFFFF,
      photo: 'x.png',
      createdAt: 0,
    );
    final result = mixAndMatch(anchor: item, catalog: kProducts, gender: Gender.male);
    expect(result.keys, contains(ClothingSlot.bottom));
    for (final m in result[ClothingSlot.bottom]!) {
      expect(slotOfProduct(m.product), ClothingSlot.bottom);
      expect(m.product.audience, anyOf('Men', 'Unisex'));
    }
  });

  test('Stylist: hujan + meeting formal menyertakan luaran', () {
    final outfit = buildOutfit(
      catalog: kProducts,
      gender: Gender.female,
      dress: DressCode.formal,
      rainy: true,
      tMax: 28,
    );
    final slots = outfit.picks.map((p) => p.slot).toSet();
    expect(slots, containsAll([ClothingSlot.top, ClothingSlot.bottom, ClothingSlot.outer]));
    expect(outfit.tips, isNotEmpty);
  });

  test('Ukuran: preferensi longgar tidak menurunkan ukuran lebih dari reguler', () {
    expect(sizeShift(FitPreference.regular, CutType.oversized), -1);
    expect(sizeShift(FitPreference.loose, CutType.oversized), 0);
    expect(sizeShift(FitPreference.snug, CutType.slim), 0);
    final product = kProducts.firstWhere(
      (p) => p.availableSizes.contains('M') && p.audience == 'Women',
    );
    final r = recommendSize(
      const FitProfile(gender: Gender.female, heightCm: 160, weightKg: 55),
      product,
    );
    expect(r.supported, isTrue);
    expect(product.availableSizes, contains(r.size));
  });

  test('Parser cuaca Open-Meteo', () {
    const body = '{"daily":{"time":["2026-11-13"],"weather_code":[61],'
        '"temperature_2m_max":[30.5],"temperature_2m_min":[24],'
        '"precipitation_probability_max":[80]}}';
    final days = WeatherService.parseForecast(body);
    expect(days.length, 1);
    expect(days.first.isRainy, isTrue);
    expect(days.first.tMax, 30.5);
  });

  test('Price tracker: harga turun, stok habis, stok kembali', () {
    final app = AppState(store: MemoryStore());
    final tracker = TrackerProvider(store: MemoryStore(), app: app);
    tracker.setActiveMember(null);
    final product = app.allProducts.first;
    final size = product.availableSizes.first;
    tracker.track(product, size);
    final item = tracker.items.first;

    tracker.simulate(item, TrackerSimulation.priceDrop);
    expect(tracker.alerts.first.kind, AlertKind.priceDrop);

    tracker.simulate(tracker.items.first, TrackerSimulation.soldOut);
    expect(tracker.items.first.sizeAvailable, isFalse);

    tracker.simulate(tracker.items.first, TrackerSimulation.restock);
    expect(tracker.alerts.first.kind, AlertKind.restock);
    expect(tracker.unreadCount, 3);
    tracker.dispose();
  });
}
