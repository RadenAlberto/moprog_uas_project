import 'dart:convert';

import 'package:flutter/services.dart';

/// Model hasil pelatihan Python (`ml/train.py`) yang dimuat dari
/// `assets/data/ml_model.json` atau diunduh dari server (`/api/ml/model`).
///
/// Komponen yang tidak ada di berkas dilewati; aplikasi memakai aturan
/// bawaan. [sourceOf] menyebut asal tiap komponen (prior:theory,
/// trained:synthetic, trained:real, ...) sebagai bukti data.
class LearnedModel {
  LearnedModel._(this.version, this._tone, this._pair, this._sources, this.datasets);

  final String version;
  final Map<String, Map<String, Map<String, double>>> _tone;
  final Map<String, Map<String, double>> _pair;
  final Map<String, String> _sources;
  final List<Map<String, dynamic>> datasets;

  /// Model aktif. Null sampai [loadLearnedModel] / [install] dipanggil.
  static LearnedModel? current;

  bool get hasTone => _tone.isNotEmpty;
  bool get hasPair => _pair.isNotEmpty;
  String sourceOf(String component) => _sources[component] ?? 'tidak ada';
  Map<String, String> get sources => Map.unmodifiable(_sources);

  /// Skor 0..1 warna [family] untuk kulit [undertone]/[depth]; null bila tak ada.
  double? tone(String? undertone, String? depth, String family) {
    if (undertone == null) return null;
    final byDepth = _tone[undertone];
    if (byDepth == null) return null;
    final row = byDepth[depth ?? 'medium'] ?? byDepth['medium'];
    return row?[family];
  }

  /// Keserasian 0..1 dua keluarga warna; null bila tak ada.
  double? pair(String a, String b) => _pair[a]?[b];

  static Map<String, double> _numMap(Object? raw) {
    final out = <String, double>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num && v.isFinite) out['$k'] = v.toDouble().clamp(0.0, 1.0);
      });
    }
    return out;
  }

  /// Parse aman: berkas rusak menghasilkan null, bukan crash.
  static LearnedModel? fromJson(Object? raw) {
    try {
      if (raw is! Map) return null;
      final comps = raw['components'];
      if (comps is! Map) return null;
      final tone = <String, Map<String, Map<String, double>>>{};
      final tc = comps['tone_color'];
      if (tc is Map && tc['table'] is Map) {
        (tc['table'] as Map).forEach((u, depths) {
          if (depths is! Map) return;
          final byDepth = <String, Map<String, double>>{};
          depths.forEach((d, fams) => byDepth['$d'] = _numMap(fams));
          tone['$u'] = byDepth;
        });
      }
      final pair = <String, Map<String, double>>{};
      final pc = comps['color_pair'];
      if (pc is Map && pc['matrix'] is Map) {
        (pc['matrix'] as Map).forEach((a, row) => pair['$a'] = _numMap(row));
      }
      final sources = <String, String>{};
      comps.forEach((k, v) {
        if (v is Map && v['source'] is String) sources['$k'] = v['source'] as String;
      });
      final ds = <Map<String, dynamic>>[];
      final rawDs = raw['datasets'];
      if (rawDs is List) {
        for (final d in rawDs) {
          if (d is Map) ds.add(Map<String, dynamic>.from(d));
        }
      }
      return LearnedModel._('${raw['version'] ?? '?'}', tone, pair, sources, ds);
    } catch (_) {
      return null;
    }
  }

  /// Pasang model dari JSON (hasil unduhan server). Mengembalikan true bila sah.
  static bool install(Object? json) {
    final model = fromJson(json);
    if (model == null || (!model.hasTone && !model.hasPair)) return false;
    current = model;
    return true;
  }
}

/// Memuat model bawaan dari aset. Gagal = diam (aturan bawaan dipakai).
Future<void> loadLearnedModel({AssetBundle? bundle}) async {
  if (LearnedModel.current != null) return;
  try {
    final text = await (bundle ?? rootBundle).loadString('assets/data/ml_model.json');
    LearnedModel.install(jsonDecode(text));
  } catch (_) {}
}
