import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:project_uts/APP/app_providers.dart';
import 'package:project_uts/DATA/product_data.dart';
import 'package:project_uts/MODELS/product_model.dart';
import 'package:project_uts/MODELS/style_model.dart';
import 'package:project_uts/SCREENS/style_advisor_page.dart';
import 'package:project_uts/WIDGETS/app_network_image.dart';
import 'package:project_uts/SERVICES/api_service.dart';
import 'package:project_uts/SERVICES/face_analyzer.dart';
import 'package:project_uts/SERVICES/product_attributes.dart';
import 'package:project_uts/SERVICES/product_json.dart';
import 'package:project_uts/SERVICES/style_recommender.dart';
import 'package:project_uts/UTILS/key_value_store.dart';

/// Wajah sintetis (elips kulit + leher) di latar gelap, untuk menguji
/// pengukuran rasio wajah tanpa kamera.
Uint8List _synthFace(double lengthRatio, {int w = 240, int h = 320}) {
  final data = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    data[i * 4] = 20;
    data[i * 4 + 1] = 20;
    data[i * 4 + 2] = 30;
    data[i * 4 + 3] = 255;
  }
  final cx = w / 2;
  final fw = w * 0.5;
  final fh = fw * lengthRatio;
  final top = h * 0.22;
  for (var y = 0; y < h; y++) {
    final t = (y - top) / fh;
    var half = 0.0;
    if (t >= 0 && t <= 1) {
      final inside = 1 - math.pow(2 * t - 1, 2);
      half = 0.5 * fw * math.sqrt(math.max(0.0, inside.toDouble()));
    }
    if (t >= 0.55 && t <= 1.5) half = math.max(half, 0.5 * fw * 0.55);
    if (half <= 0) continue;
    for (var x = (cx - half).toInt(); x <= (cx + half).toInt(); x++) {
      if (x < 0 || x >= w) continue;
      final i = (y * w + x) * 4;
      data[i] = 224;
      data[i + 1] = 172;
      data[i + 2] = 140;
    }
  }
  return data;
}

Product _product(String id) => kProducts.firstWhere((p) => p.id == id);

void main() {
  // Katalog Uniqlo dimuat dari assets/data/products.json.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppNetworkImage.useCache = false; // tanpa plugin penyimpanan di test
    await loadProductCatalog();
  });

  group('Analisis wajah', () {
    test('classifyFaceShape mengikuti aturan rasio', () {
      expect(
        classifyFaceShape(
          lengthRatio: 1.45,
          foreheadRatio: 0.85,
          jawRatio: 0.9,
          chinRatio: 0.75,
          taperRatio: 0.95,
        ),
        FaceShape.oblong,
      );
      expect(
        classifyFaceShape(
          lengthRatio: 1.1,
          foreheadRatio: 0.85,
          jawRatio: 0.98,
          chinRatio: 0.85,
          taperRatio: 1.0,
        ),
        FaceShape.square,
      );
      expect(
        classifyFaceShape(
          lengthRatio: 0.95,
          foreheadRatio: 0.85,
          jawRatio: 0.9,
          chinRatio: 0.75,
          taperRatio: 0.88,
        ),
        FaceShape.round,
      );
      expect(
        classifyFaceShape(
          lengthRatio: 1.2,
          foreheadRatio: 0.88,
          jawRatio: 0.78,
          chinRatio: 0.66,
          taperRatio: 0.7,
        ),
        FaceShape.heart,
      );
    });

    test('analyzeRgba membaca bentuk wajah sintetis', () {
      const analyzer = FaceAnalyzer();
      final round = analyzer.analyzeRgba(_synthFace(1.0), 240, 320);
      final oval = analyzer.analyzeRgba(_synthFace(1.4), 240, 320);
      final oblong = analyzer.analyzeRgba(_synthFace(1.7), 240, 320);
      expect(round.ok, isTrue);
      expect(oval.ok, isTrue);
      expect(oblong.ok, isTrue);
      expect(round.faceShape, FaceShape.round);
      expect(oval.faceShape, FaceShape.oval);
      expect(oblong.faceShape, FaceShape.oblong);
      expect(oval.depth, isNotNull);
      expect(oval.undertone, isNotNull);
      expect(oval.confidence, inInclusiveRange(0.0, 1.0));
    });

    test('foto tanpa wajah ditolak dengan pesan', () {
      final blank = Uint8List(240 * 320 * 4);
      for (var i = 0; i < 240 * 320; i++) {
        blank[i * 4] = 10;
        blank[i * 4 + 1] = 10;
        blank[i * 4 + 2] = 10;
        blank[i * 4 + 3] = 255;
      }
      final result = const FaceAnalyzer().analyzeRgba(blank, 240, 320);
      expect(result.ok, isFalse);
      expect(result.message, isNotEmpty);
    });

    test('rgbToLab: putih = L 100, hitam = L 0', () {
      expect(rgbToLab(255, 255, 255)[0], closeTo(100, 0.5));
      expect(rgbToLab(0, 0, 0)[0], closeTo(0, 0.5));
    });
  });

  group('Profil tubuh', () {
    test('BMI, tipe tubuh, dan kelas tinggi', () {
      const p = BodyProfile(
        gender: Gender.male,
        heightCm: 170,
        weightKg: 60,
      );
      expect(p.bmi, closeTo(20.76, 0.05));
      expect(p.bodyType, BodyType.normal);
      expect(p.heightClass, HeightClass.average);

      const heavy = BodyProfile(
        gender: Gender.female,
        heightCm: 150,
        weightKg: 70,
      );
      expect(heavy.bodyType, BodyType.obese);
      expect(heavy.heightClass, HeightClass.short);
    });

    test('JSON bolak-balik dan data rusak ditolak', () {
      final original = BodyProfile(
        gender: Gender.female,
        heightCm: 160,
        weightKg: 52.5,
        faceShape: FaceShape.heart,
        undertone: Undertone.cool,
        depth: SkinDepth.light,
        skinColorArgb: 0xFFF1D1B5,
        goals: const {StyleGoal.work, StyleGoal.warm},
        maxPrice: 400000,
        analyzedAt: DateTime(2026, 11, 11),
      );
      final restored = BodyProfile.fromJson(
        jsonDecode(jsonEncode(original.toJson())),
      );
      expect(restored, isNotNull);
      expect(restored!.gender, Gender.female);
      expect(restored.faceShape, FaceShape.heart);
      expect(restored.goals, {StyleGoal.work, StyleGoal.warm});
      expect(restored.maxPrice, 400000);
      expect(restored.heightCm, 160);

      expect(BodyProfile.fromJson('bukan map'), isNull);
      expect(BodyProfile.fromJson({'gender': 'male'}), isNull);
      expect(
        BodyProfile.fromJson({'gender': 'male', 'heightCm': 5, 'weightKg': 60}),
        isNull,
      );
    });
  });

  group('Mesin rekomendasi ML', () {
    const recommender = StyleRecommender();
    const male = BodyProfile(
      gender: Gender.male,
      heightCm: 170,
      weightKg: 62,
      faceShape: FaceShape.round,
      undertone: Undertone.warm,
      depth: SkinDepth.medium,
    );

    test('hanya produk sesuai jenis kelamin (dan unisex) yang muncul', () {
      final recs = recommender.recommend(
        profile: male,
        products: kProducts,
        model: StyleModel(),
      );
      expect(recs, isNotEmpty);
      for (final rec in recs) {
        expect(['Men', 'Unisex'], contains(rec.product.audience));
        expect(rec.score, inInclusiveRange(0.01, 0.99));
        expect(rec.reasons, isNotEmpty);
        expect(rec.product.availableSizes, contains(rec.suggestedSize));
        expect(rec.product.availableColors, contains(rec.bestColor));
      }
      for (var i = 1; i < recs.length; i++) {
        expect(recs[i - 1].score >= recs[i].score, isTrue);
      }
    });

    test('wajah bulat lebih cocok dengan kerah daripada leher bulat', () {
      final collar = recommender.featureVector(
        male,
        _product('E486491-000'), // Kemeja Slim Fit Kerah Reguler (kerah)
        StyleModel(),
      );
      final crew = recommender.featureVector(
        male,
        _product('E450179-000'), // T-Shirt Kerah Bulat (leher bulat)
        StyleModel(),
      );
      expect(collar[1], greaterThan(crew[1]));
    });

    test('tubuh berisi: potongan longgar lebih cocok dari skinny', () {
      const heavy = BodyProfile(
        gender: Gender.female,
        heightCm: 160,
        weightKg: 72,
      );
      final skinny = recommender.featureVector(
        heavy,
        _product('E455471-000'), // Jeans Skinny Fit
        StyleModel(),
      );
      final wide = recommender.featureVector(
        heavy,
        _product('E488462-000'), // Jeans Lebar Lurus
        StyleModel(),
      );
      expect(wide[2], greaterThan(skinny[2]));
    });

    test('ukuran disarankan mengikuti berat badan dan potongan slim', () {
      const normal = BodyProfile(
        gender: Gender.male,
        heightCm: 170,
        weightKg: 60,
      );
      const bigger = BodyProfile(
        gender: Gender.male,
        heightCm: 170,
        weightKg: 70,
      );
      final chino = _product('E486491-000'); // Slim Fit, XS-3XL
      expect(recommender.suggestSize(normal, chino), 'M');
      expect(recommender.suggestSize(bigger, chino), 'XL');
      expect(recommender.suggestSize(normal, _product('E493539-000')), 'One Size');
    });

    test('set pakaian memuat atasan dan bawahan', () {
      final recs = recommender.recommend(
        profile: male,
        products: kProducts,
        model: StyleModel(),
      );
      final outfits = recommender.buildOutfits(male, recs);
      expect(outfits, isNotEmpty);
      final groups = outfits.first.items
          .map((r) => ProductAttributes.of(r.product).group)
          .toSet();
      expect(groups, contains(GarmentGroup.top));
      expect(groups, contains(GarmentGroup.bottom));
    });

    test('model belajar: tidak cocok menurunkan skor, cocok menaikkan', () {
      final recs = recommender.recommend(
        profile: male,
        products: kProducts,
        model: StyleModel(),
      );
      final target = recs.first;

      final disliker = StyleModel();
      final before = disliker.predict(target.features);
      for (var i = 0; i < 6; i++) {
        disliker.learnFrom(target.product, target.features, positive: false);
      }
      expect(disliker.predict(target.features), lessThan(before));
      expect(disliker.samples, 6);

      final liker = StyleModel();
      final low = recs.last;
      final lowBefore = liker.predict(low.features);
      for (var i = 0; i < 6; i++) {
        liker.learnFrom(low.product, low.features, positive: true);
      }
      expect(liker.predict(low.features), greaterThan(lowBefore));
      expect(liker.categoryAffinity[low.product.category], greaterThan(0.5));
    });

    test('bobot tetap dalam batas dan JSON model bolak-balik', () {
      final model = StyleModel();
      final x = List<double>.filled(StyleModel.priorWeights.length, 1.0);
      for (var i = 0; i < 500; i++) {
        model.learn(x, 0);
      }
      for (final w in model.weights) {
        expect(w, inInclusiveRange(0.0, 5.0));
      }
      expect(model.weights.first, greaterThanOrEqualTo(1.5));

      final restored = StyleModel.fromJson(jsonDecode(jsonEncode(model.toJson())));
      expect(restored.weights.length, model.weights.length);
      expect(restored.samples, model.samples);
      expect(restored.predict(x), closeTo(model.predict(x), 1e-9));

      // Data rusak -> model awal, bukan crash.
      expect(StyleModel.fromJson('rusak').samples, 0);
      expect(StyleModel.fromJson({'w': [1, 2]}).weights.length,
          StyleModel.priorWeights.length);
    });

    test('keluarga warna', () {
      expect(colorFamilyOf(Colors.black), ColorFamily.black);
      expect(colorFamilyOf(Colors.white), ColorFamily.white);
      expect(colorFamilyOf(Colors.blue), ColorFamily.blue);
      expect(colorFamilyOf(Colors.brown), ColorFamily.earth);
    });
  });

  group('Server & JSON produk', () {
    test('productFromJson membaca produk valid dan menolak yang rusak', () {
      final good = productFromJson({
        'id': '99',
        'name': 'Kaos Tes',
        'price': 99000,
        'original_price': 129000,
        'image': '',
        'category': 'T-Shirts',
        'audience': 'Unisex',
        'description': 'Deskripsi',
        'features': ['AIRism'],
        'is_new': true,
        'sizes': ['S', 'M'],
        'colors': [0xFF000000, 0xFFFFFFFF],
      });
      expect(good, isNotNull);
      expect(good!.isOnSale, isTrue);
      expect(good.availableColors.length, 2);
      expect(good.isNew, isTrue);

      expect(productFromJson({'id': '1'}), isNull);
      expect(productFromJson('x'), isNull);
      expect(
        productFromJson({
          'id': '1',
          'name': 'A',
          'price': 0,
          'category': 'x',
          'audience': 'Men',
          'sizes': ['S'],
          'colors': [1],
        }),
        isNull,
      );
    });

    test('ApiService: koneksi sukses mengambil produk dan popularitas', () async {
      final client = MockClient((request) async {
        if (request.url.path == '/api/health') {
          return http.Response('{"status":"ok"}', 200);
        }
        if (request.url.path == '/api/products') {
          return http.Response(
            jsonEncode({
              'products': [
                {
                  'id': '1',
                  'name': 'AIRism',
                  'price': 199000,
                  'category': 'T-Shirts',
                  'audience': 'Men',
                  'sizes': ['M'],
                  'colors': [4278190080],
                  'popularity': 0.8,
                },
                {'id': 'rusak'},
              ],
            }),
            200,
          );
        }
        return http.Response('{"error":"tidak ada"}', 404);
      });
      final api = ApiService(store: MemoryStore(), client: client);
      expect(await api.ping(), isTrue);
      expect(api.isOnline, isTrue);

      final popularity = <String, double>{};
      final products = await api.fetchProducts(popularity: popularity);
      expect(products, isNotNull);
      expect(products!.length, 1, reason: 'produk rusak dilewati');
      expect(popularity['1'], 0.8);
      api.dispose();
    });

    test('ApiService: server mati -> offline tanpa error', () async {
      final client = MockClient((request) async {
        throw http.ClientException('tidak ada koneksi');
      });
      final api = ApiService(store: MemoryStore(), client: client);
      expect(await api.ping(), isFalse);
      expect(api.isOnline, isFalse);
      expect(await api.fetchProducts(), isNull);
      final login = await api.login('a@b.com', 'secret1');
      expect(login.ok, isFalse);
      expect(login.offline, isTrue);
      api.dispose();
    });

    test('ApiService: login menyimpan sesi dan alamat server bisa diubah',
        () async {
      final store = MemoryStore();
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          return http.Response(
            jsonEncode({
              'token': 'abc',
              'user': {'id': 1},
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final api = ApiService(store: store, client: client);
      await api.setBaseUrl('192.168.1.10:8000/');
      expect(api.baseUrl, 'http://192.168.1.10:8000');

      final response = await api.login('A@B.com', 'secret1');
      expect(response.ok, isTrue);
      expect(api.hasSession, isTrue);
      expect(api.sessionEmail, 'a@b.com');

      // Sesi dipulihkan oleh instance baru dari penyimpanan yang sama.
      final again = ApiService(store: store, client: client);
      expect(again.hasSession, isTrue);
      expect(again.baseUrl, 'http://192.168.1.10:8000');

      await again.clearSession();
      expect(again.hasSession, isFalse);
      api.dispose();
      again.dispose();
    });
  });

  group('Layar Stylist', () {
    testWidgets('wizard: validasi data diri sampai hasil rekomendasi',
        (tester) async {
      await tester.pumpWidget(
        AppProviders(
          store: MemoryStore(),
          autoSync: false,
          child: const MaterialApp(home: StyleAdvisorPage()),
        ),
      );

      expect(find.text('Bingung memilih baju yang cocok?'), findsOneWidget);
      await tester.tap(find.text('Mulai'));
      await tester.pumpAndSettle();
      expect(find.text('Data dirimu'), findsOneWidget);

      // Data kosong ditolak dengan pesan.
      await tester.tap(find.text('Lanjut ke foto'));
      await tester.pumpAndSettle();
      expect(find.text('Pilih jenis kelamin terlebih dahulu.'), findsOneWidget);

      await tester.tap(find.text('Pria'));
      await tester.enterText(find.byType(TextField).first, '170');
      await tester.enterText(find.byType(TextField).last, '62');
      await tester.pump();
      expect(find.textContaining('BMI'), findsOneWidget);

      await tester.tap(find.text('Lanjut ke foto'));
      await tester.pumpAndSettle();
      expect(find.text('Lewati foto, pilih manual'), findsOneWidget);

      await tester.tap(find.text('Lewati foto, pilih manual'));
      await tester.pumpAndSettle();
      expect(find.text('Periksa hasilnya'), findsOneWidget);

      await tester.tap(find.text('Lihat rekomendasi'));
      await tester.pumpAndSettle();
      expect(find.text('Profil gayamu'), findsOneWidget);

      // Bongkar pohon widget agar tidak ada timer tersisa.
      await tester.pumpWidget(const SizedBox());
    });
  });
}
