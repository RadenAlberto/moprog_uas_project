import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../MODELS/product_model.dart';
import '../MODELS/style_model.dart';
import 'learned_model.dart';
import 'product_attributes.dart';

double _sigmoid(double z) => 1 / (1 + math.exp(-z));

/// Model machine learning personal: regresi logistik yang dilatih langsung di
/// perangkat dari umpan balik pengguna (suka / kurang cocok / masuk keranjang).
///
/// Setiap produk diubah menjadi vektor 11 fitur bernilai 0..1 (kecocokan
/// bentuk wajah, tipe tubuh, tinggi, warna, kebutuhan, harga, popularitas,
/// dst.). Skor kecocokan = sigmoid(w . x + b).
///
/// Bobot awal ([priorWeights]) berasal dari aturan stylist (pengetahuan
/// fashion). Setiap umpan balik menggeser bobot dengan satu langkah
/// stochastic gradient descent, ditambah regularisasi agar tidak menjauh
/// terlalu jauh dari bobot awal. Selain itu model mengingat "afinitas"
/// kategori dan warna favorit tiap pengguna.
class StyleModel {
  StyleModel({
    List<double>? weights,
    double? bias,
    Map<String, double>? categoryAffinity,
    Map<String, double>? colorAffinity,
    this.samples = 0,
  })  : weights = (weights != null && weights.length == priorWeights.length)
            ? List<double>.from(weights)
            : List<double>.from(priorWeights),
        bias = bias ?? priorBias,
        categoryAffinity = {...?categoryAffinity},
        colorAffinity = {...?colorAffinity};

  static const List<String> featureNames = [
    'audience',
    'face',
    'body',
    'height',
    'color',
    'bodyColor',
    'goal',
    'popularity',
    'price',
    'categoryAffinity',
    'colorAffinity',
  ];

  /// Nama fitur yang ditampilkan ke pengguna.
  static const List<String> featureLabels = [
    'Jenis kelamin',
    'Bentuk wajah',
    'Tipe tubuh',
    'Tinggi badan',
    'Nada kulit',
    'Warna untuk tubuh',
    'Kebutuhan',
    'Tren pengguna lain',
    'Harga',
    'Jenis favorit',
    'Warna favorit',
  ];

  static const List<double> priorWeights = [
    2.5, 1.1, 1.6, 0.8, 1.2, 0.6, 1.3, 0.7, 1.4, 0.9, 0.7, //
  ];
  static const double priorBias = -8.2;
  static const List<double> _minWeight = [
    1.5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, //
  ];
  static const double _maxWeight = 5;

  final List<double> weights;
  double bias;
  final Map<String, double> categoryAffinity;
  final Map<String, double> colorAffinity;

  /// Jumlah umpan balik yang sudah dipelajari.
  int samples;

  /// Peluang cocok 0..1 untuk vektor fitur [x].
  double predict(List<double> x) {
    if (x.length != weights.length) return 0;
    var z = bias;
    for (var i = 0; i < weights.length; i++) {
      z += weights[i] * x[i];
    }
    return _sigmoid(z);
  }

  /// Satu langkah SGD. [target] 1 = cocok, 0 = tidak cocok.
  void learn(List<double> x, double target, {double rate = 0.12}) {
    if (x.length != weights.length) return;
    final error = target - predict(x);
    for (var i = 0; i < weights.length; i++) {
      final pull = rate * 0.04 * (weights[i] - priorWeights[i]);
      weights[i] = (weights[i] + rate * error * x[i] - pull)
          .clamp(_minWeight[i], _maxWeight)
          .toDouble();
    }
    bias = (bias + rate * error * 0.3 - rate * 0.04 * (bias - priorBias))
        .clamp(-10.0, -5.0)
        .toDouble();
    samples++;
  }

  /// Mengingat kategori/warna yang disukai (atau tidak) pengguna.
  void learnAffinity(Product product, {required bool positive}) {
    final target = positive ? 1.0 : 0.0;
    final category = product.category;
    final old = categoryAffinity[category] ?? 0.5;
    categoryAffinity[category] = old + 0.3 * (target - old);
    for (final family in ProductAttributes.of(product).colorFamilies) {
      final key = family.name;
      final before = colorAffinity[key] ?? 0.5;
      colorAffinity[key] = before + 0.15 * (target - before);
    }
  }

  /// Belajar dari satu umpan balik pada produk dengan fitur [x].
  void learnFrom(
    Product product,
    List<double> x, {
    required bool positive,
    double rate = 0.12,
  }) {
    learn(x, positive ? 1.0 : 0.0, rate: rate);
    learnAffinity(product, positive: positive);
  }

  /// Seberapa jauh bobot fitur ke-[index] bergeser dari bobot awal.
  double shift(int index) => weights[index] - priorWeights[index];

  Map<String, dynamic> toJson() => {
        'v': 1,
        'w': weights,
        'b': bias,
        'cat': categoryAffinity,
        'col': colorAffinity,
        'n': samples,
      };

  factory StyleModel.fromJson(Object? raw) {
    if (raw is! Map) return StyleModel();
    List<double>? weights;
    final w = raw['w'];
    if (w is List && w.every((e) => e is num)) {
      weights = [for (final e in w) (e as num).toDouble()];
    }
    Map<String, double> affinity(Object? source) {
      final out = <String, double>{};
      if (source is Map) {
        source.forEach((key, value) {
          if (key is String && value is num) {
            out[key] = value.toDouble().clamp(0.0, 1.0).toDouble();
          }
        });
      }
      return out;
    }

    final bias = raw['b'];
    final model = StyleModel(
      weights: weights,
      bias: bias is num ? bias.toDouble().clamp(-10.0, -5.0).toDouble() : null,
      categoryAffinity: affinity(raw['cat']),
      colorAffinity: affinity(raw['col']),
      samples: raw['n'] is num ? (raw['n'] as num).toInt() : 0,
    );
    // Batasi bobot hasil sinkronisasi agar data rusak tidak merusak model.
    for (var i = 0; i < model.weights.length; i++) {
      model.weights[i] =
          model.weights[i].clamp(_minWeight[i], _maxWeight).toDouble();
    }
    return model;
  }
}

/// Menghitung rekomendasi produk dari profil pengguna dan model ML.
class StyleRecommender {
  const StyleRecommender();

  // ---------------------------------------------------------------------------
  // Tabel pengetahuan stylist (bobot awal sebelum model belajar)
  // ---------------------------------------------------------------------------

  static const Map<FaceShape, Map<Neckline, double>> _necklineByFace = {
    FaceShape.oval: {
      Neckline.crew: 0.9, Neckline.collar: 0.9, Neckline.turtle: 0.85,
      Neckline.hood: 0.85, Neckline.open: 0.9, Neckline.scoop: 0.85, //
    },
    FaceShape.round: {
      Neckline.crew: 0.6, Neckline.collar: 1.0, Neckline.turtle: 0.35,
      Neckline.hood: 0.55, Neckline.open: 0.95, Neckline.scoop: 0.7, //
    },
    FaceShape.square: {
      Neckline.crew: 1.0, Neckline.collar: 0.6, Neckline.turtle: 0.8,
      Neckline.hood: 0.8, Neckline.open: 0.85, Neckline.scoop: 0.8, //
    },
    FaceShape.heart: {
      Neckline.crew: 0.95, Neckline.collar: 0.75, Neckline.turtle: 0.85,
      Neckline.hood: 0.8, Neckline.open: 0.8, Neckline.scoop: 0.85, //
    },
    FaceShape.oblong: {
      Neckline.crew: 0.95, Neckline.collar: 0.6, Neckline.turtle: 1.0,
      Neckline.hood: 0.9, Neckline.open: 0.7, Neckline.scoop: 0.6, //
    },
  };

  static const Map<FaceShape, double> _scarfByFace = {
    FaceShape.oval: 0.9,
    FaceShape.round: 0.4,
    FaceShape.square: 0.7,
    FaceShape.heart: 0.9,
    FaceShape.oblong: 1.0,
  };

  static const Map<FaceShape, double> _headwearByFace = {
    FaceShape.oval: 0.85,
    FaceShape.round: 0.65,
    FaceShape.square: 0.8,
    FaceShape.heart: 0.75,
    FaceShape.oblong: 0.5,
  };

  static const Map<BodyType, Map<GarmentFit, double>> _fitByBody = {
    BodyType.underweight: {
      GarmentFit.slim: 0.55, GarmentFit.regular: 0.85,
      GarmentFit.relaxed: 1.0, GarmentFit.oversized: 1.0, //
    },
    BodyType.normal: {
      GarmentFit.slim: 1.0, GarmentFit.regular: 1.0,
      GarmentFit.relaxed: 0.9, GarmentFit.oversized: 0.8, //
    },
    BodyType.overweight: {
      GarmentFit.slim: 0.45, GarmentFit.regular: 0.9,
      GarmentFit.relaxed: 1.0, GarmentFit.oversized: 0.7, //
    },
    BodyType.obese: {
      GarmentFit.slim: 0.25, GarmentFit.regular: 0.75,
      GarmentFit.relaxed: 1.0, GarmentFit.oversized: 0.65, //
    },
  };

  static const Map<HeightClass, Map<GarmentFit, double>> _fitByHeight = {
    HeightClass.short: {
      GarmentFit.slim: 0.95, GarmentFit.regular: 0.9,
      GarmentFit.relaxed: 0.7, GarmentFit.oversized: 0.55, //
    },
    HeightClass.average: {
      GarmentFit.slim: 0.95, GarmentFit.regular: 0.95,
      GarmentFit.relaxed: 0.95, GarmentFit.oversized: 0.9, //
    },
    HeightClass.tall: {
      GarmentFit.slim: 0.8, GarmentFit.regular: 0.9,
      GarmentFit.relaxed: 1.0, GarmentFit.oversized: 1.0, //
    },
  };

  static const Map<ColorFamily, double> _warmTone = {
    ColorFamily.black: 0.75, ColorFamily.white: 0.85, ColorFamily.grey: 0.65,
    ColorFamily.blue: 0.6, ColorFamily.teal: 0.55, ColorFamily.purple: 0.45,
    ColorFamily.pink: 0.5, ColorFamily.red: 0.85, ColorFamily.green: 0.9,
    ColorFamily.earth: 1.0, //
  };

  static const Map<ColorFamily, double> _coolTone = {
    ColorFamily.black: 0.95, ColorFamily.white: 1.0, ColorFamily.grey: 0.9,
    ColorFamily.blue: 1.0, ColorFamily.teal: 0.85, ColorFamily.purple: 0.95,
    ColorFamily.pink: 0.85, ColorFamily.red: 0.7, ColorFamily.green: 0.6,
    ColorFamily.earth: 0.45, //
  };

  static const Map<ColorFamily, double> _neutralTone = {
    ColorFamily.black: 0.9, ColorFamily.white: 0.9, ColorFamily.grey: 0.9,
    ColorFamily.blue: 0.9, ColorFamily.teal: 0.85, ColorFamily.purple: 0.8,
    ColorFamily.pink: 0.8, ColorFamily.red: 0.85, ColorFamily.green: 0.85,
    ColorFamily.earth: 0.9, //
  };

  static const Map<ColorFamily, double> _lightBody = {
    ColorFamily.black: 0.55, ColorFamily.white: 0.9, ColorFamily.grey: 0.8,
    ColorFamily.blue: 0.85, ColorFamily.teal: 0.85, ColorFamily.purple: 0.8,
    ColorFamily.pink: 0.9, ColorFamily.red: 0.85, ColorFamily.green: 0.85,
    ColorFamily.earth: 0.85, //
  };

  static const Map<ColorFamily, double> _darkBody = {
    ColorFamily.black: 1.0, ColorFamily.white: 0.6, ColorFamily.grey: 0.8,
    ColorFamily.blue: 0.85, ColorFamily.teal: 0.7, ColorFamily.purple: 0.75,
    ColorFamily.pink: 0.5, ColorFamily.red: 0.5, ColorFamily.green: 0.7,
    ColorFamily.earth: 0.75, //
  };

  // ---------------------------------------------------------------------------
  // Komponen fitur
  // ---------------------------------------------------------------------------

  double _face(BodyProfile p, ProductAttributes a) {
    final face = p.faceShape;
    if (face == null) return 0.6;
    if (a.isScarf) return _scarfByFace[face] ?? 0.6;
    if (a.isHeadwear) return _headwearByFace[face] ?? 0.6;
    if (a.group == GarmentGroup.accessory || a.group == GarmentGroup.bottom) {
      return 0.65;
    }
    return _necklineByFace[face]?[a.neckline] ?? 0.7;
  }

  double _body(BodyProfile p, ProductAttributes a) {
    if (a.group == GarmentGroup.accessory || a.group == GarmentGroup.inner) {
      return 0.8;
    }
    return _fitByBody[p.bodyType]?[a.fit] ?? 0.8;
  }

  double _height(BodyProfile p, ProductAttributes a) {
    if (a.group == GarmentGroup.accessory) return 0.8;
    final cls = p.heightClass;
    var score = _fitByHeight[cls]?[a.fit] ?? 0.9;
    if (cls == HeightClass.short) {
      if (a.isAnkle) score = 1.0;
      if (a.isLong) score = 0.55;
    } else if (cls == HeightClass.tall && a.isLong) {
      score = 1.0;
    }
    return score;
  }

  double _tone(BodyProfile p, ColorFamily family) {
    // Tabel hasil pelatihan (ml/train.py) bila ada; sudah mencakup kedalaman kulit.
    final learned = LearnedModel.current?.tone(p.undertone?.name, p.depth?.name, family.name);
    if (learned != null) return learned.clamp(0.0, 1.0).toDouble();
    final table = switch (p.undertone) {
      Undertone.warm => _warmTone,
      Undertone.cool => _coolTone,
      Undertone.neutral => _neutralTone,
      null => null,
    };
    var value = table?[family] ?? 0.75;
    if (p.depth == SkinDepth.deep) {
      switch (family) {
        case ColorFamily.white:
          value += 0.10;
        case ColorFamily.red:
        case ColorFamily.pink:
        case ColorFamily.blue:
        case ColorFamily.teal:
          value += 0.06;
        default:
          break;
      }
    } else if (p.depth == SkinDepth.light) {
      switch (family) {
        case ColorFamily.grey:
        case ColorFamily.blue:
        case ColorFamily.pink:
          value += 0.05;
        default:
          break;
      }
    }
    return value.clamp(0.0, 1.0).toDouble();
  }

  double _bodyColor(BodyProfile p, ColorFamily family) {
    switch (p.bodyType) {
      case BodyType.underweight:
        return _lightBody[family] ?? 0.8;
      case BodyType.normal:
        return 0.8;
      case BodyType.overweight:
      case BodyType.obese:
        return _darkBody[family] ?? 0.7;
    }
  }

  double _goal(BodyProfile p, ProductAttributes a) {
    if (a.group == GarmentGroup.accessory) {
      if ((a.isScarf || a.isHeadwear) && p.goals.contains(StyleGoal.warm)) {
        return 1.0;
      }
      return 0.6;
    }
    for (final goal in p.goals) {
      if (a.goals.contains(goal.name)) return 1.0;
    }
    return 0.35;
  }

  double _price(BodyProfile p, Product product) {
    final max = p.maxPrice;
    double value;
    if (max == null || max <= 0) {
      value = 0.75;
    } else if (product.price <= max) {
      value = 1.0;
    } else {
      value = (1 - (product.price - max) / max).clamp(0.0, 1.0).toDouble();
    }
    if (product.isOnSale) value = math.min(1.0, value + 0.12);
    return value;
  }

  /// Warna terbaik dari pilihan warna produk untuk profil ini.
  ({Color color, ColorFamily family, double tone, double body}) _bestColor(
    BodyProfile p,
    Product product,
  ) {
    Color best = Colors.black;
    var bestFamily = ColorFamily.black;
    var bestTone = 0.75;
    var bestBody = 0.8;
    var bestScore = -1.0;
    for (final color in product.availableColors) {
      final family = colorFamilyOf(color);
      final tone = _tone(p, family);
      final body = _bodyColor(p, family);
      final score = 0.65 * tone + 0.35 * body;
      if (score > bestScore) {
        bestScore = score;
        best = color;
        bestFamily = family;
        bestTone = tone;
        bestBody = body;
      }
    }
    return (color: best, family: bestFamily, tone: bestTone, body: bestBody);
  }

  /// Vektor fitur (0..1) sebuah produk untuk profil [p].
  List<double> featureVector(
    BodyProfile p,
    Product product,
    StyleModel model, {
    double Function(Product product)? popularity,
  }) {
    final a = ProductAttributes.of(product);
    final color = _bestColor(p, product);
    final categoryAffinity = model.categoryAffinity[product.category] ?? 0.5;
    final families = a.colorFamilies;
    var colorAffinity = 0.5;
    if (families.isNotEmpty) {
      var sum = 0.0;
      for (final family in families) {
        sum += model.colorAffinity[family.name] ?? 0.5;
      }
      colorAffinity = sum / families.length;
    }
    final pop = (popularity?.call(product) ?? 0.5).clamp(0.0, 1.0).toDouble();
    return [
      1.0,
      _face(p, a),
      _body(p, a),
      _height(p, a),
      color.tone,
      color.body,
      _goal(p, a),
      pop,
      _price(p, product),
      categoryAffinity,
      colorAffinity,
    ];
  }

  // ---------------------------------------------------------------------------
  // Rekomendasi
  // ---------------------------------------------------------------------------

  /// Apakah [product] boleh direkomendasikan untuk [p] (Pria/Wanita/Unisex).
  bool isEligible(BodyProfile p, Product product) {
    return product.audience == p.gender.audience ||
        product.audience == 'Unisex';
  }

  /// Daftar rekomendasi terurut dari yang paling cocok.
  List<StyleRecommendation> recommend({
    required BodyProfile profile,
    required List<Product> products,
    required StyleModel model,
    double Function(Product product)? popularity,
  }) {
    final out = <StyleRecommendation>[];
    for (final product in products) {
      if (!isEligible(profile, product)) continue;
      final x = featureVector(profile, product, model, popularity: popularity);
      final color = _bestColor(profile, product);
      final score = model.predict(x).clamp(0.01, 0.99).toDouble();
      out.add(StyleRecommendation(
        product: product,
        score: score,
        reasons: _reasons(profile, product, x, color.family),
        features: x,
        suggestedSize: suggestSize(profile, product),
        bestColor: color.color,
      ));
    }
    out.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.product.id.compareTo(b.product.id);
    });
    return out;
  }

  List<String> _reasons(
    BodyProfile p,
    Product product,
    List<double> x,
    ColorFamily bestFamily,
  ) {
    final a = ProductAttributes.of(product);
    final reasons = <String>[];

    final faceApplies = p.faceShape != null &&
        (a.isScarf ||
            a.isHeadwear ||
            (a.neckline != Neckline.none &&
                a.group != GarmentGroup.accessory &&
                a.group != GarmentGroup.bottom));
    if (faceApplies && x[1] >= 0.85) {
      final face = p.faceShape!.label;
      if (a.isScarf || a.isHeadwear || a.neckline.label.isEmpty) {
        reasons.add('Cocok untuk bentuk wajah $face');
      } else {
        reasons.add('Leher ${a.neckline.label} serasi dengan wajah $face');
      }
    }
    final fitApplies = a.group == GarmentGroup.top ||
        a.group == GarmentGroup.bottom ||
        a.group == GarmentGroup.outer ||
        a.group == GarmentGroup.set;
    if (fitApplies && x[2] >= 0.9) {
      reasons.add(
        'Potongan ${a.fit.label} nyaman untuk tubuh ${p.bodyType.label.toLowerCase()}',
      );
    }
    if (p.undertone != null && x[4] >= 0.85) {
      reasons.add(
        'Warna ${bestFamily.label.toLowerCase()} serasi dengan kulit ${p.undertone!.label.toLowerCase()}',
      );
    }
    if (a.isAnkle && p.heightClass == HeightClass.short) {
      reasons.add('Potongan ankle membuat kaki tampak lebih jenjang');
    } else if (p.heightClass != HeightClass.average &&
        fitApplies &&
        x[3] >= 0.95) {
      reasons.add(
        'Proporsional untuk tinggi badan ${p.heightClass.label.toLowerCase()}',
      );
    }
    if (x[6] >= 1.0) {
      for (final goal in p.goals) {
        if (a.goals.contains(goal.name) ||
            (a.group == GarmentGroup.accessory && goal == StyleGoal.warm)) {
          reasons.add('Pas untuk ${goal.label.toLowerCase()}');
          break;
        }
      }
    }
    if (p.maxPrice != null && x[8] >= 1.0) {
      reasons.add('Sesuai budget');
    } else if (product.isOnSale) {
      reasons.add('Sedang diskon ${product.discountPercent}%');
    }
    if (x[7] >= 0.7) reasons.add('Banyak dipilih pengguna lain');
    if (x[9] >= 0.7 || x[10] >= 0.7) {
      reasons.add('Mirip produk yang kamu sukai');
    }

    if (reasons.isEmpty) reasons.add('Cukup sesuai dengan kebutuhan gayamu');
    return reasons.take(3).toList();
  }

  // ---------------------------------------------------------------------------
  // Ukuran
  // ---------------------------------------------------------------------------

  static const List<String> _letterSizes = [
    'XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', //
  ];

  int _sizeIndex(BodyProfile p) {
    final w = p.weightKg;
    if (p.gender == Gender.male) {
      if (w < 55) return 2;
      if (w < 68) return 3;
      if (w < 80) return 4;
      if (w < 92) return 5;
      return 6;
    }
    if (w < 45) return 1;
    if (w < 53) return 2;
    if (w < 62) return 3;
    if (w < 72) return 4;
    if (w < 82) return 5;
    return 6;
  }

  /// Ukuran yang disarankan dari tinggi/berat (perkiraan, bukan ukuran pasti).
  String suggestSize(BodyProfile p, Product product) {
    final sizes = product.availableSizes;
    if (sizes.isEmpty) return '-';
    if (sizes.length == 1) return sizes.first;

    var index = _sizeIndex(p);
    final a = ProductAttributes.of(product);
    if (a.fit == GarmentFit.slim && p.bmi >= 23) index++;
    index = index.clamp(0, _letterSizes.length - 1);

    final letters = <String>[
      for (final s in sizes)
        if (_letterSizes.contains(s)) s,
    ];
    if (letters.isNotEmpty) {
      var best = letters.first;
      var bestDistance = 999;
      for (final s in letters) {
        final distance = (_letterSizes.indexOf(s) - index).abs();
        if (distance < bestDistance) {
          bestDistance = distance;
          best = s;
        }
      }
      return best;
    }

    final numeric = <int>[];
    for (final s in sizes) {
      final n = int.tryParse(s);
      if (n != null) numeric.add(n);
    }
    if (numeric.length == sizes.length) {
      numeric.sort();
      final fraction = ((index - 1) / 5).clamp(0.0, 1.0).toDouble();
      final pick = (fraction * (numeric.length - 1)).round();
      return '${numeric[pick]}';
    }
    // Ukuran lain (mis. "26inch", "L (Tinggi)"): daftar Uniqlo sudah berurutan
    // dari kecil ke besar, jadi pilih posisi yang sepadan dengan tubuhnya.
    final fraction = ((index - 1) / 5).clamp(0.0, 1.0).toDouble();
    return sizes[(fraction * (sizes.length - 1)).round()];
  }

  // ---------------------------------------------------------------------------
  // Outfit
  // ---------------------------------------------------------------------------

  static const Set<ColorFamily> _neutralFamilies = {
    ColorFamily.black,
    ColorFamily.white,
    ColorFamily.grey,
  };

  ColorFamily _familyOf(StyleRecommendation r) => colorFamilyOf(r.bestColor);

  double _harmony(StyleRecommendation a, StyleRecommendation b) {
    final fa = _familyOf(a);
    final fb = _familyOf(b);
    if (fa == fb) return 0.1;
    if (_neutralFamilies.contains(fa) || _neutralFamilies.contains(fb)) {
      return 0.15;
    }
    return 0.0;
  }

  /// Menyusun set pakaian lengkap (atasan + bawahan + luaran/aksesori) dari
  /// daftar [ranked]. Setiap look mengikuti satu kebutuhan gaya pengguna.
  List<OutfitSuggestion> buildOutfits(
    BodyProfile profile,
    List<StyleRecommendation> ranked, {
    int count = 3,
  }) {
    List<StyleRecommendation> pool(GarmentGroup group) => [
          for (final r in ranked)
            if (ProductAttributes.of(r.product).group == group) r,
        ];

    final tops = pool(GarmentGroup.top);
    final bottoms = pool(GarmentGroup.bottom);
    final outers = pool(GarmentGroup.outer);
    final sets = pool(GarmentGroup.set);
    final accessories = [
      for (final r in ranked)
        if (ProductAttributes.of(r.product).isScarf ||
            ProductAttributes.of(r.product).isHeadwear)
          r,
    ];
    if (tops.isEmpty && sets.isEmpty) return const [];

    final goals = profile.goals.isEmpty
        ? <StyleGoal>[StyleGoal.casual]
        : (profile.goals.toList()..sort((a, b) => a.index.compareTo(b.index)));
    final usedIds = <String>{};
    final outfits = <OutfitSuggestion>[];

    List<StyleRecommendation> forGoal(
      List<StyleRecommendation> source,
      StyleGoal goal,
    ) {
      final matched = [
        for (final r in source)
          if (!usedIds.contains(r.product.id) &&
              ProductAttributes.of(r.product).goals.contains(goal.name))
            r,
      ];
      if (matched.isNotEmpty) return matched;
      return [
        for (final r in source)
          if (!usedIds.contains(r.product.id)) r,
      ];
    }

    for (var i = 0; i < count; i++) {
      final goal = goals[i % goals.length];
      final items = <StyleRecommendation>[];

      final topCandidates = forGoal(tops, goal);
      StyleRecommendation? top;
      if (topCandidates.isNotEmpty) top = topCandidates.first;

      if (top != null) {
        items.add(top);
        final bottomCandidates = forGoal(bottoms, goal);
        StyleRecommendation? bottom;
        var bestValue = -1.0;
        for (final candidate in bottomCandidates.take(8)) {
          final value = candidate.score + _harmony(top, candidate);
          if (value > bestValue) {
            bestValue = value;
            bottom = candidate;
          }
        }
        if (bottom != null) items.add(bottom);
      } else {
        final setCandidates = forGoal(sets, goal);
        if (setCandidates.isNotEmpty) items.add(setCandidates.first);
      }

      if (goal == StyleGoal.warm || (i == 0 && goals.length == 1)) {
        final outerCandidates = forGoal(outers, goal);
        if (outerCandidates.isNotEmpty) items.add(outerCandidates.first);
      }
      if (goal == StyleGoal.warm) {
        final extras = [
          for (final r in accessories)
            if (!usedIds.contains(r.product.id)) r,
        ];
        if (extras.isNotEmpty) items.add(extras.first);
      }

      if (items.isEmpty) break;
      for (final r in items) {
        usedIds.add(r.product.id);
      }
      outfits.add(OutfitSuggestion(
        title: 'Look ${i + 1}: ${goal.label}',
        items: items,
      ));
    }
    return outfits;
  }

  // ---------------------------------------------------------------------------
  // Saran teks untuk pengguna awam
  // ---------------------------------------------------------------------------

  /// Tips gaya dalam bahasa sederhana berdasarkan profil.
  List<String> styleTips(BodyProfile p) {
    final tips = <String>[];
    switch (p.faceShape) {
      case FaceShape.round:
        tips.add(
          'Wajah bulat: pilih kerah atau leher V/terbuka dan garis vertikal '
          'agar wajah tampak lebih tegas. Hindari turtleneck tinggi.',
        );
      case FaceShape.square:
        tips.add(
          'Wajah kotak: leher bulat dan bahan lembut (rajut, katun) '
          'melembutkan garis rahang.',
        );
      case FaceShape.heart:
        tips.add(
          'Wajah hati: leher bulat atau turtleneck menyeimbangkan dagu yang '
          'meruncing. Hindari detail besar di bahu.',
        );
      case FaceShape.oblong:
        tips.add(
          'Wajah lonjong: turtleneck, syal, dan hoodie memberi kesan lebih '
          'lebar. Hindari V-neck yang terlalu dalam.',
        );
      case FaceShape.oval:
        tips.add(
          'Wajah oval: hampir semua model leher cocok, jadi bebas '
          'bereksperimen.',
        );
      case null:
        break;
    }
    switch (p.bodyType) {
      case BodyType.underweight:
        tips.add(
          'Tubuh kurus: layering (kemeja + jaket) dan potongan longgar '
          'menambah volume. Hindari skinny dan warna serba hitam.',
        );
      case BodyType.normal:
        tips.add(
          'Tubuh ideal: potongan slim maupun regular sama-sama pas. Mainkan '
          'warna sesuai selera.',
        );
      case BodyType.overweight:
      case BodyType.obese:
        tips.add(
          'Tubuh berisi: pilih potongan regular/longgar berbahan jatuh dan '
          'warna gelap polos. Hindari pakaian yang terlalu ketat.',
        );
    }
    switch (p.heightClass) {
      case HeightClass.short:
        tips.add(
          'Tinggi badan pendek: padukan atasan dan bawahan satu warna serta '
          'celana ankle agar tampak lebih jenjang.',
        );
      case HeightClass.tall:
        tips.add(
          'Tinggi badan jangkung: celana lebar, layering, dan luaran panjang '
          'terlihat proporsional.',
        );
      case HeightClass.average:
        break;
    }
    switch (p.undertone) {
      case Undertone.warm:
        tips.add(
          'Nada kulit hangat: warna krem, cokelat, olive, dan merah bata '
          'membuat kulit tampak cerah.',
        );
      case Undertone.cool:
        tips.add(
          'Nada kulit dingin: biru, abu-abu, ungu, pink, dan putih bersih '
          'paling serasi.',
        );
      case Undertone.neutral:
        tips.add('Nada kulit netral: sebagian besar warna cocok untukmu.');
      case null:
        break;
    }
    return tips;
  }

  /// Warna yang disarankan untuk profil (urut dari paling serasi).
  List<ColorFamily> bestColorFamilies(BodyProfile p, {int count = 5}) {
    final scored = <MapEntry<ColorFamily, double>>[
      for (final family in ColorFamily.values)
        MapEntry(family, 0.65 * _tone(p, family) + 0.35 * _bodyColor(p, family)),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in scored.take(count)) e.key];
  }
}

/// Warna perwakilan tiap [ColorFamily] untuk ditampilkan sebagai swatch.
Color swatchOf(ColorFamily family) {
  switch (family) {
    case ColorFamily.black:
      return const Color(0xFF1A1A1A);
    case ColorFamily.white:
      return const Color(0xFFF4F4F4);
    case ColorFamily.grey:
      return const Color(0xFF9E9E9E);
    case ColorFamily.blue:
      return const Color(0xFF2F5DA8);
    case ColorFamily.teal:
      return const Color(0xFF1F9C93);
    case ColorFamily.purple:
      return const Color(0xFF7B4FA3);
    case ColorFamily.pink:
      return const Color(0xFFE58AA8);
    case ColorFamily.red:
      return const Color(0xFFC62828);
    case ColorFamily.green:
      return const Color(0xFF4E8C4A);
    case ColorFamily.earth:
      return const Color(0xFF9C6B4A);
  }
}
