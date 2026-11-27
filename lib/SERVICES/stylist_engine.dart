import 'package:flutter/material.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../MODELS/style_model.dart' show Gender;
import 'color_utils.dart';
import 'outfit_engine.dart';

/// Rekomendasi satu pakaian pada outfit hari itu.
class OutfitPick {
  const OutfitPick({required this.slot, required this.match, required this.why});

  final ClothingSlot slot;
  final OutfitMatch match;
  final String why;
}

/// Pakaian di lemari pengguna yang serasi dengan outfit hari itu.
class WardrobeIdea {
  const WardrobeIdea({
    required this.item,
    required this.partner,
    required this.harmony,
  });

  final WardrobeItem item;
  final OutfitPick partner;
  final Harmony harmony;
}

class StylistOutfit {
  const StylistOutfit({
    required this.dress,
    required this.rainy,
    required this.hot,
    required this.cold,
    required this.picks,
    required this.tips,
  });

  final DressCode dress;
  final bool rainy;
  final bool hot;
  final bool cold;
  final List<OutfitPick> picks;
  final List<String> tips;
}

const double kHotThreshold = 32;
const double kColdThreshold = 23;

const List<String> _waterKeywords = [
  'water',
  'blocktech',
  'pufftech',
  'parka',
  'windproof',
  'tahan air',
  'penolak air',
  'anti air',
  'tahan angin',
  'hujan',
];

String _corpus(Product p) =>
    '${p.name} ${p.description} ${p.features.join(' ')}'.toLowerCase();

/// Menyusun outfit dari katalog berdasarkan acara, cuaca, dan target pengguna.
///
/// Murni aturan (tanpa jaringan): hasil sama untuk masukan yang sama.
StylistOutfit buildOutfit({
  required List<Product> catalog,
  required Gender? gender,
  required DressCode dress,
  required bool rainy,
  double? tMax,
  double? maxPrice,
}) {
  final hot = tMax != null && tMax >= kHotThreshold;
  final cold = tMax != null && tMax < kColdThreshold;

  final slots = <ClothingSlot>[
    ClothingSlot.top,
    ClothingSlot.bottom,
    if (rainy || cold) ClothingSlot.outer,
  ];

  final picks = <OutfitPick>[];
  final chosenColors = <Color>[];

  for (final slot in slots) {
    OutfitMatch? best;
    var bestScore = -1e9;
    var bestWhy = '';

    for (final product in catalog) {
      if (slotOfProduct(product) != slot) continue;
      if (!audienceMatches(product, gender)) continue;
      if (maxPrice != null && product.price > maxPrice) continue;

      final reasons = <String>[];
      var score = _productScore(
        product,
        slot,
        dress,
        rainy: rainy,
        hot: hot,
        cold: cold,
        gender: gender,
        reasons: reasons,
      );
      if (product.ratingCount >= 3) score += product.ratingAverage * 0.15;
      if (product.isOnSale) score += 0.3;
      if (score <= bestScore) continue;

      final colorIndex = _pickColor(product, dress, rainy, hot, slot, chosenColors);
      bestScore = score;
      bestWhy = reasons.take(2).join(' • ');
      best = OutfitMatch(
        product: product,
        colorIndex: colorIndex,
        score: score,
        reason: bestWhy,
      );
    }

    if (best != null) {
      picks.add(OutfitPick(slot: slot, match: best, why: bestWhy));
      final c = best.color;
      if (c != null) chosenColors.add(c);
    }
  }

  return StylistOutfit(
    dress: dress,
    rainy: rainy,
    hot: hot,
    cold: cold,
    picks: picks,
    tips: _tips(dress, rainy, hot, cold),
  );
}

double _productScore(
  Product p,
  ClothingSlot slot,
  DressCode dress, {
  required bool rainy,
  required bool hot,
  required bool cold,
  required Gender? gender,
  required List<String> reasons,
}) {
  final t = _corpus(p);
  bool has(String k) => t.contains(k);
  var s = 0.0;

  switch (slot) {
    case ClothingSlot.top:
      switch (dress) {
        case DressCode.formal:
          s += switch (p.category) {
            'Shirts' => 5,
            'Knitwear' => 1,
            'T-Shirts' => -5,
            'Sweatshirts' => -6,
            _ => 0,
          };
          if (has('rayon')) {
            s += 3;
            reasons.add('Rayon jatuh rapi untuk acara formal');
          }
          if (has('oxford') || has('broadcloth') || has('non-iron')) s += 2;
          if (has('blus') || has('kemeja')) s += 1;
          if (p.features.contains('UT')) s -= 6;
          break;
        case DressCode.smart:
          s += switch (p.category) {
            'Shirts' => 4,
            'Knitwear' => 3,
            'T-Shirts' => has('polo') ? 3 : 1,
            'Sweatshirts' => -3,
            _ => 0,
          };
          if (p.features.contains('UT')) s -= 4;
          if (s > 0) reasons.add('Rapi tapi tetap santai');
          break;
        case DressCode.casual:
          s += switch (p.category) {
            'T-Shirts' => 4,
            'Shirts' => 2,
            'Sweatshirts' => 2,
            'Knitwear' => 1,
            _ => 0,
          };
          if (s > 0) reasons.add('Nyaman untuk aktivitas harian');
          break;
        case DressCode.sport:
          s += switch (p.category) {
            'T-Shirts' => 3,
            'Sweatshirts' => 0,
            'Shirts' => -3,
            'Knitwear' => -4,
            _ => 0,
          };
          if (has('dry-ex')) {
            s += 4;
            reasons.add('DRY-EX cepat kering saat berkeringat');
          }
          if (has('airism')) {
            s += 3;
            reasons.add('AIRism sejuk dan ringan');
          }
          if (p.features.contains('UT')) s -= 2;
          break;
      }
      break;

    case ClothingSlot.bottom:
      switch (dress) {
        case DressCode.formal:
          s += switch (p.category) {
            'Pants' => 5,
            'Skirts' => gender == Gender.female ? 3 : -6,
            'Jeans' => -3,
            'Shorts' => -8,
            _ => 0,
          };
          if (has('smart')) s += 3;
          if (has('ankle')) s += 2;
          if (has('chino') || has('slack') || has('ezy')) s += 1;
          if (s > 3) reasons.add('Potongan rapi untuk meeting');
          break;
        case DressCode.smart:
          s += switch (p.category) {
            'Pants' => 4,
            'Jeans' => 2,
            'Skirts' => gender == Gender.female ? 3 : -6,
            'Shorts' => -5,
            _ => 0,
          };
          if (has('smart') || has('ankle')) s += 1;
          break;
        case DressCode.casual:
          s += switch (p.category) {
            'Jeans' => 3,
            'Pants' => 2,
            'Shorts' => hot ? 3 : 1,
            'Skirts' => gender == Gender.female ? 2 : -6,
            _ => 0,
          };
          break;
        case DressCode.sport:
          s += switch (p.category) {
            'Shorts' => 4,
            'Pants' => 1,
            'Jeans' => -5,
            'Skirts' => -4,
            _ => 0,
          };
          if (has('jogger') || has('dry')) {
            s += 3;
            reasons.add('Bahan lentur untuk bergerak');
          }
          break;
      }
      if (rainy) {
        if (p.category == 'Shorts' || p.category == 'Skirts') s -= 2;
        if (has('ankle')) {
          s += 2;
          reasons.add('Model ankle tidak menyapu genangan');
        }
        if (has('dry') || has('quick') || has('kering')) s += 2;
      }
      break;

    case ClothingSlot.outer:
      s += 1;
      if (rainy) {
        var water = 0;
        for (final k in _waterKeywords) {
          if (has(k)) water++;
        }
        if (water > 0) {
          s += 4 + water;
          reasons.add('Tahan air untuk hari hujan');
        }
        if (has('padded') || has('down') || has('fleece')) s -= 4; // gerah & berat
      }
      if (cold) {
        if (has('fleece') || has('heattech') || has('wol') || has('down')) {
          s += 3;
          reasons.add('Hangat untuk udara dingin');
        }
      }
      if (dress == DressCode.formal && (has('blazer') || has('kemeja'))) s += 2;
      if (dress == DressCode.sport && has('dry')) s += 2;
      break;

    case ClothingSlot.dress:
    case ClothingSlot.accessory:
      break;
  }

  // Bahan menurut suhu.
  if (hot) {
    if (has('airism')) {
      s += 3;
      reasons.add('AIRism menyerap keringat');
    }
    if (has('linen')) {
      s += 3;
      reasons.add('Linen sejuk di cuaca panas');
    }
    if (has('katun') && slot != ClothingSlot.outer) s += 1;
    for (final k in const ['heattech', 'fleece', 'wol', 'kasmir', 'padded', 'down']) {
      if (has(k)) s -= 8;
    }
    if (has('rajut') && slot == ClothingSlot.top) s -= 2;
  } else if (cold && slot != ClothingSlot.outer) {
    if (has('heattech') || has('fleece') || has('wol') || has('rajut')) {
      s += 2;
      reasons.add('Bahan hangat');
    }
  }
  if (rainy && has('linen')) s -= 2;

  return s;
}

int _pickColor(
  Product p,
  DressCode dress,
  bool rainy,
  bool hot,
  ClothingSlot slot,
  List<Color> chosen,
) {
  if (p.availableColors.isEmpty) return -1;
  var bestIndex = 0;
  var bestScore = -1e9;
  for (var i = 0; i < p.availableColors.length; i++) {
    final c = p.availableColors[i];
    final l = HSLColor.fromColor(c).lightness;
    var s = isNeutralColor(c) ? 1.0 : 0.0;
    if (dress == DressCode.formal && l < 0.35) s += 1;
    if (rainy && slot == ClothingSlot.bottom && l < 0.5) s += 1;
    if (hot && slot == ClothingSlot.top && l > 0.6) s += 1;
    for (final other in chosen) {
      s += colorHarmony(other, c).score * 2;
    }
    if (s > bestScore) {
      bestScore = s;
      bestIndex = i;
    }
  }
  return bestIndex;
}

List<String> _tips(DressCode dress, bool rainy, bool hot, bool cold) {
  return [
    if (rainy) 'Bawa payung atau jas hujan, dan pilih alas kaki yang cepat kering.',
    if (hot) 'Pilih warna terang dan bahan yang menyerap keringat.',
    if (cold) 'Lapis dengan outer agar tetap hangat, terutama di ruangan ber-AC.',
    if (dress == DressCode.formal) 'Setrika pakaian malam sebelumnya agar tampil rapi.',
    if (dress == DressCode.sport) 'Bawa baju ganti dan handuk kecil.',
    if (!rainy && !hot && !cold) 'Cuaca bersahabat, kombinasi ini nyaman seharian.',
  ];
}

/// Pakaian milik pengguna yang serasi dengan [picks] (urut dari terserasi).
List<WardrobeIdea> wardrobeIdeas({
  required List<OutfitPick> picks,
  required List<WardrobeItem> wardrobe,
  int limit = 4,
}) {
  final ideas = <WardrobeIdea>[];
  for (final item in wardrobe) {
    WardrobeIdea? best;
    for (final pick in picks) {
      if (pick.slot == item.slot) continue;
      if (!complementarySlots(item.slot).contains(pick.slot)) continue;
      final c = pick.match.color;
      if (c == null) continue;
      final h = colorHarmony(item.color, c);
      if (best == null || h.score > best.harmony.score) {
        best = WardrobeIdea(item: item, partner: pick, harmony: h);
      }
    }
    if (best != null && best.harmony.score >= 0.7) ideas.add(best);
  }
  ideas.sort((a, b) => b.harmony.score.compareTo(a.harmony.score));
  return ideas.take(limit).toList();
}
