import 'package:flutter/material.dart';

import 'learned_model.dart';
import 'product_attributes.dart' show colorFamilyOf;

/// Nama warna dalam bahasa Indonesia untuk sebuah [Color].
String colorNameId(Color c) {
  final hsl = HSLColor.fromColor(c);
  final h = hsl.hue;
  final s = hsl.saturation;
  final l = hsl.lightness;

  if (l < 0.12) return 'Hitam';
  if (l > 0.92 && s < 0.4) return 'Putih';
  if (s < 0.12) {
    if (l < 0.3) return 'Abu tua';
    if (l < 0.65) return 'Abu-abu';
    return 'Abu muda';
  }
  if (h < 15 || h >= 345) {
    if (l > 0.72) return 'Pink muda';
    if (l < 0.3) return 'Marun';
    return 'Merah';
  }
  if (h < 45) {
    if (l < 0.42) return 'Cokelat';
    if (l > 0.75) return 'Krem';
    return 'Oranye';
  }
  if (h < 70) {
    if (l > 0.75) return 'Krem';
    if (s < 0.5 && l < 0.5) return 'Olive';
    return 'Kuning';
  }
  if (h < 165) {
    if (h < 100 && s < 0.5 && l < 0.5) return 'Olive';
    return l < 0.3 ? 'Hijau tua' : 'Hijau';
  }
  if (h < 200) return 'Tosca';
  if (h < 255) {
    if (l < 0.3) return 'Navy';
    return l > 0.75 ? 'Biru muda' : 'Biru';
  }
  if (h < 290) return 'Ungu';
  return l > 0.7 ? 'Pink muda' : 'Pink';
}

/// Warna netral (mudah dipadukan): hitam, putih, abu, navy, krem, cokelat.
bool isNeutralColor(Color c) {
  final hsl = HSLColor.fromColor(c);
  if (hsl.saturation < 0.15 || hsl.lightness < 0.12 || hsl.lightness > 0.92) {
    return true;
  }
  const neutralNames = {'Navy', 'Krem', 'Cokelat', 'Olive'};
  return neutralNames.contains(colorNameId(c));
}

enum HarmonyKind {
  neutral('Netral, mudah dipadukan'),
  tonal('Satu keluarga warna'),
  analogous('Warna berdekatan, tampil harmonis'),
  complementary('Warna berlawanan, kontras menarik'),
  triadic('Kombinasi berani'),
  clash('Kurang serasi');

  const HarmonyKind(this.description);

  final String description;
}

class Harmony {
  const Harmony(this.score, this.kind);

  /// 0..1, makin tinggi makin serasi.
  final double score;
  final HarmonyKind kind;
}

/// Seberapa serasi dua warna bila dipakai bersamaan.
Harmony colorHarmony(Color a, Color b) {
  final base = _ruleHarmony(a, b);
  final learned = LearnedModel.current?.pair(colorFamilyOf(a).name, colorFamilyOf(b).name);
  return learned == null ? base : Harmony(learned.clamp(0.0, 1.0).toDouble(), base.kind);
}

Harmony _ruleHarmony(Color a, Color b) {
  final ha = HSLColor.fromColor(a);
  final hb = HSLColor.fromColor(b);
  final na = isNeutralColor(a);
  final nb = isNeutralColor(b);

  if (na && nb) {
    final contrast = (ha.lightness - hb.lightness).abs();
    return Harmony(0.72 + contrast * 0.2, HarmonyKind.neutral);
  }
  if (na || nb) return const Harmony(0.88, HarmonyKind.neutral);

  var diff = (ha.hue - hb.hue).abs();
  if (diff > 180) diff = 360 - diff;
  if (diff < 15) return const Harmony(0.7, HarmonyKind.tonal);
  if (diff <= 40) return const Harmony(0.78, HarmonyKind.analogous);
  if (diff >= 150) return const Harmony(0.74, HarmonyKind.complementary);
  if (diff >= 100) return const Harmony(0.6, HarmonyKind.triadic);
  return const Harmony(0.3, HarmonyKind.clash);
}

/// Palet warna yang bisa dipilih saat mengedit item lemari.
const List<Color> kWardrobePalette = [
  Color(0xFF111111),
  Color(0xFFFFFFFF),
  Color(0xFF9E9E9E),
  Color(0xFF1F2A44),
  Color(0xFFE8DCC8),
  Color(0xFF6D4C41),
  Color(0xFF556B2F),
  Color(0xFFEC1C24),
  Color(0xFFEF8A3C),
  Color(0xFFF2C94C),
  Color(0xFF2E7D32),
  Color(0xFF1E88E5),
  Color(0xFF7E57C2),
  Color(0xFFF48FB1),
];
