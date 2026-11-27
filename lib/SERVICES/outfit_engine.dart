import 'package:flutter/material.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../MODELS/style_model.dart' show Gender;
import 'color_utils.dart';

/// Kategori katalog -> posisi pakaian. `null` = tidak dipakai untuk padu padan.
ClothingSlot? slotOfProduct(Product p) {
  switch (p.category) {
    case 'T-Shirts':
    case 'Shirts':
    case 'Knitwear':
    case 'Sweatshirts':
      return ClothingSlot.top;
    case 'Pants':
    case 'Jeans':
    case 'Shorts':
    case 'Skirts':
      return ClothingSlot.bottom;
    case 'Outerwear':
      return ClothingSlot.outer;
    case 'Dresses':
      return ClothingSlot.dress;
    case 'Accessories':
      return ClothingSlot.accessory;
  }
  return null;
}

/// Target pengguna produk yang cocok. Produk anak/bayi tidak ditampilkan.
bool audienceMatches(Product p, Gender? gender) {
  switch (p.audience) {
    case 'Unisex':
      return true;
    case 'Men':
      return gender == null || gender == Gender.male;
    case 'Women':
      return gender == null || gender == Gender.female;
  }
  return false;
}

/// Satu rekomendasi produk (dengan warna terbaik).
class OutfitMatch {
  const OutfitMatch({
    required this.product,
    required this.colorIndex,
    required this.score,
    required this.reason,
  });

  final Product product;
  final int colorIndex;
  final double score;
  final String reason;

  Color? get color =>
      colorIndex >= 0 && colorIndex < product.availableColors.length
          ? product.availableColors[colorIndex]
          : null;

  String get colorName {
    final c = color;
    if (c == null) return '';
    return product.colorNameOf(c) ?? colorNameId(c);
  }

  /// Foto produk sesuai warna yang direkomendasikan.
  String get image => product.imageFor(color);
}

/// Slot yang melengkapi [slot] dalam satu outfit.
List<ClothingSlot> complementarySlots(ClothingSlot slot) {
  switch (slot) {
    case ClothingSlot.top:
      return const [ClothingSlot.bottom, ClothingSlot.outer];
    case ClothingSlot.bottom:
      return const [ClothingSlot.top, ClothingSlot.outer];
    case ClothingSlot.outer:
      return const [ClothingSlot.top, ClothingSlot.bottom];
    case ClothingSlot.dress:
      return const [ClothingSlot.outer, ClothingSlot.accessory];
    case ClothingSlot.accessory:
      return const [ClothingSlot.top, ClothingSlot.bottom];
  }
}

/// Mencari produk katalog yang cocok dipadukan dengan pakaian [anchor] milik
/// pengguna. Hasil dikelompokkan per posisi pakaian.
Map<ClothingSlot, List<OutfitMatch>> mixAndMatch({
  required WardrobeItem anchor,
  required List<Product> catalog,
  Gender? gender,
  int perSlot = 4,
}) {
  final result = <ClothingSlot, List<OutfitMatch>>{};
  for (final slot in complementarySlots(anchor.slot)) {
    final matches = <OutfitMatch>[];
    for (final product in catalog) {
      if (slotOfProduct(product) != slot) continue;
      if (!audienceMatches(product, gender)) continue;
      final best = _bestColor(product, anchor.color);
      if (best == null) continue;
      var score = best.harmony.score;
      if (product.ratingCount >= 3) score += (product.ratingAverage / 5) * 0.06;
      if (product.isOnSale) score += 0.03;
      matches.add(
        OutfitMatch(
          product: product,
          colorIndex: best.index,
          score: score,
          reason: best.harmony.kind.description,
        ),
      );
    }
    matches.sort((a, b) => b.score.compareTo(a.score));

    // Satu nama produk hanya sekali, supaya hasil tidak monoton.
    final seen = <String>{};
    final picked = <OutfitMatch>[];
    for (final m in matches) {
      if (seen.add(m.product.name)) picked.add(m);
      if (picked.length >= perSlot) break;
    }
    if (picked.isNotEmpty) result[slot] = picked;
  }
  return result;
}

class _BestColor {
  const _BestColor(this.index, this.harmony);

  final int index;
  final Harmony harmony;
}

_BestColor? _bestColor(Product product, Color against) {
  if (product.availableColors.isEmpty) return null;
  var bestIndex = 0;
  Harmony? best;
  for (var i = 0; i < product.availableColors.length; i++) {
    final h = colorHarmony(against, product.availableColors[i]);
    if (best == null || h.score > best.score) {
      best = h;
      bestIndex = i;
    }
  }
  return best == null ? null : _BestColor(bestIndex, best);
}
