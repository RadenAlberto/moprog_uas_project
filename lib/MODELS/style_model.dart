import 'package:flutter/material.dart';

import 'product_model.dart';

/// Jenis kelamin yang dipakai untuk memilih produk Pria/Wanita.
enum Gender {
  female('Wanita', 'Women'),
  male('Pria', 'Men');

  const Gender(this.label, this.audience);

  final String label;

  /// Nilai `Product.audience` yang cocok.
  final String audience;
}

enum FaceShape {
  oval('Oval', 'Proporsi seimbang, paling fleksibel untuk hampir semua model.'),
  round('Bulat', 'Lebar dan panjang wajah hampir sama, garis rahang lembut.'),
  square('Kotak', 'Rahang tegas dan lebar, dahi dan rahang hampir sama lebar.'),
  heart('Hati', 'Dahi lebih lebar dan dagu meruncing.'),
  oblong('Lonjong', 'Wajah lebih panjang dibanding lebarnya.');

  const FaceShape(this.label, this.description);

  final String label;
  final String description;
}

enum Undertone {
  warm('Hangat', 'Kulit cenderung keemasan/kekuningan.'),
  cool('Dingin', 'Kulit cenderung kemerahan/kebiruan.'),
  neutral('Netral', 'Perpaduan hangat dan dingin.');

  const Undertone(this.label, this.description);

  final String label;
  final String description;
}

enum SkinDepth {
  light('Cerah'),
  medium('Sedang'),
  deep('Gelap');

  const SkinDepth(this.label);

  final String label;
}

enum BodyType {
  underweight('Kurus'),
  normal('Ideal'),
  overweight('Berisi'),
  obese('Besar');

  const BodyType(this.label);

  final String label;
}

enum HeightClass {
  short('Pendek'),
  average('Sedang'),
  tall('Tinggi');

  const HeightClass(this.label);

  final String label;
}

/// Kebutuhan berpakaian yang dipilih pengguna.
enum StyleGoal {
  casual('Kasual harian'),
  work('Kerja / kampus'),
  sport('Santai & olahraga'),
  warm('Cuaca dingin / AC');

  const StyleGoal(this.label);

  final String label;
}

/// Data diri untuk rekomendasi gaya. Foto TIDAK disimpan, hanya hasil ukurnya.
class BodyProfile {
  const BodyProfile({
    required this.gender,
    required this.heightCm,
    required this.weightKg,
    this.faceShape,
    this.undertone,
    this.depth,
    this.skinColorArgb,
    this.goals = const {StyleGoal.casual},
    this.maxPrice,
    this.analyzedAt,
  });

  final Gender gender;
  final double heightCm;
  final double weightKg;
  final FaceShape? faceShape;
  final Undertone? undertone;
  final SkinDepth? depth;

  /// Warna kulit rata-rata dari foto (ARGB), untuk ditampilkan.
  final int? skinColorArgb;
  final Set<StyleGoal> goals;

  /// Batas harga per produk. `null` = tanpa batas.
  final double? maxPrice;
  final DateTime? analyzedAt;

  /// Indeks massa tubuh.
  double get bmi {
    final m = heightCm / 100;
    if (m <= 0) return 0;
    return weightKg / (m * m);
  }

  /// Klasifikasi BMI untuk populasi Asia (WHO Asia-Pasifik).
  BodyType get bodyType {
    final value = bmi;
    if (value < 18.5) return BodyType.underweight;
    if (value < 23) return BodyType.normal;
    if (value < 27.5) return BodyType.overweight;
    return BodyType.obese;
  }

  HeightClass get heightClass {
    final short = gender == Gender.male ? 163.0 : 153.0;
    final tall = gender == Gender.male ? 175.0 : 165.0;
    if (heightCm < short) return HeightClass.short;
    if (heightCm >= tall) return HeightClass.tall;
    return HeightClass.average;
  }

  bool get hasFace => faceShape != null;

  Color? get skinColor =>
      skinColorArgb == null ? null : Color(skinColorArgb!);

  BodyProfile copyWith({
    Gender? gender,
    double? heightCm,
    double? weightKg,
    FaceShape? faceShape,
    Undertone? undertone,
    SkinDepth? depth,
    int? skinColorArgb,
    Set<StyleGoal>? goals,
    double? maxPrice,
    bool clearMaxPrice = false,
    DateTime? analyzedAt,
  }) {
    return BodyProfile(
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      faceShape: faceShape ?? this.faceShape,
      undertone: undertone ?? this.undertone,
      depth: depth ?? this.depth,
      skinColorArgb: skinColorArgb ?? this.skinColorArgb,
      goals: goals ?? this.goals,
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      analyzedAt: analyzedAt ?? this.analyzedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'gender': gender.name,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'faceShape': faceShape?.name,
        'undertone': undertone?.name,
        'depth': depth?.name,
        'skinColor': skinColorArgb,
        'goals': goals.map((g) => g.name).toList(),
        'maxPrice': maxPrice,
        'analyzedAt': analyzedAt?.toIso8601String(),
      };

  /// Membaca JSON; mengembalikan `null` bila data rusak/tidak lengkap.
  static BodyProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final gender = _byName(Gender.values, json['gender']);
    final height = (json['heightCm'] as num?)?.toDouble();
    final weight = (json['weightKg'] as num?)?.toDouble();
    if (gender == null || height == null || weight == null) return null;
    if (height < 50 || height > 250 || weight < 10 || weight > 300) return null;

    final goals = <StyleGoal>{};
    final rawGoals = json['goals'];
    if (rawGoals is List) {
      for (final item in rawGoals) {
        final goal = _byName(StyleGoal.values, item);
        if (goal != null) goals.add(goal);
      }
    }
    return BodyProfile(
      gender: gender,
      heightCm: height,
      weightKg: weight,
      faceShape: _byName(FaceShape.values, json['faceShape']),
      undertone: _byName(Undertone.values, json['undertone']),
      depth: _byName(SkinDepth.values, json['depth']),
      skinColorArgb: (json['skinColor'] as num?)?.toInt(),
      goals: goals.isEmpty ? {StyleGoal.casual} : goals,
      maxPrice: (json['maxPrice'] as num?)?.toDouble(),
      analyzedAt: DateTime.tryParse('${json['analyzedAt'] ?? ''}'),
    );
  }
}

T? _byName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Hasil analisis foto (bentuk wajah dan warna kulit).
class FaceAnalysisResult {
  const FaceAnalysisResult.failure(this.message)
      : ok = false,
        faceShape = null,
        undertone = null,
        depth = null,
        skinColorArgb = null,
        confidence = 0,
        lengthRatio = 0;

  const FaceAnalysisResult.success({
    required FaceShape this.faceShape,
    required Undertone this.undertone,
    required SkinDepth this.depth,
    required int this.skinColorArgb,
    required this.confidence,
    required this.lengthRatio,
    this.message = '',
  }) : ok = true;

  final bool ok;
  final String message;
  final FaceShape? faceShape;
  final Undertone? undertone;
  final SkinDepth? depth;
  final int? skinColorArgb;

  /// Keyakinan 0..1 (kualitas foto dan seberapa jelas bentuk wajah).
  final double confidence;
  final double lengthRatio;
}

/// Satu rekomendasi produk beserta alasannya.
class StyleRecommendation {
  const StyleRecommendation({
    required this.product,
    required this.score,
    required this.reasons,
    required this.features,
    required this.suggestedSize,
    required this.bestColor,
  });

  final Product product;

  /// Peluang cocok 0..1 (keluaran model).
  final double score;

  /// Alasan singkat dalam bahasa Indonesia.
  final List<String> reasons;

  /// Vektor fitur yang dipakai model (untuk belajar dari feedback).
  final List<double> features;
  final String suggestedSize;
  final Color bestColor;

  int get percent => (score * 100).round();
}

/// Satu set pakaian (atasan + bawahan + luaran).
class OutfitSuggestion {
  const OutfitSuggestion({required this.title, required this.items});

  final String title;
  final List<StyleRecommendation> items;
}
