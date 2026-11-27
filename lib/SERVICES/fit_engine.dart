import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../MODELS/style_model.dart' show Gender;

/// Potongan (siluet) pakaian.
enum CutType {
  slim('Slim', 'Menempel di badan', -1),
  regular('Reguler', 'Pas, tidak menempel dan tidak longgar', 0),
  relaxed('Rileks', 'Agak longgar dan nyaman bergerak', 1),
  oversized('Oversized', 'Sangat longgar, bahu dan lengan turun', 2);

  const CutType(this.label, this.description, this.ease);

  final String label;
  final String description;

  /// Kelonggaran relatif: -1 slim ... 2 oversized.
  final int ease;
}

/// Menebak potongan dari nama, label, dan deskripsi produk.
CutType detectCut(Product p) {
  final t = '${p.name} ${p.features.join(' ')} ${p.description}'.toLowerCase();
  bool has(String k) => t.contains(k);
  if (has('oversize') || has('boxy') || has('over size')) return CutType.oversized;
  if (has('rileks') ||
      has('relaxed') ||
      has('longgar') ||
      has('lebar') ||
      has('wide') ||
      has('baggy') ||
      has('loose')) {
    return CutType.relaxed;
  }
  if (has('slim') || has('skinny') || has('ramping') || has('ultra stretch')) {
    return CutType.slim;
  }
  return CutType.regular;
}

/// Jenis ukuran yang dipakai produk.
enum SizeFamily { letter, inch, waistCm, kidsCm, oneSize, other }

const List<String> _letters = ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', '3XL', '4XL'];

SizeFamily _familyOf(String size) {
  final s = size.trim().toUpperCase();
  if (_letters.contains(s)) return SizeFamily.letter;
  if (s == 'ONE SIZE') return SizeFamily.oneSize;
  if (RegExp(r'^\d+(\.\d+)?INCH$').hasMatch(s)) return SizeFamily.inch;
  if (RegExp(r'^\d{2,3}CM$').hasMatch(s)) return SizeFamily.waistCm;
  if (RegExp(r'\(\d+CM\)$').hasMatch(s)) return SizeFamily.kidsCm;
  return SizeFamily.other;
}

enum FitVerdict {
  tight('Ketat'),
  snug('Pas badan'),
  regular('Pas'),
  loose('Longgar');

  const FitVerdict(this.label);

  final String label;
}

class FitResult {
  const FitResult({
    required this.supported,
    this.size,
    this.alternative,
    this.cut = CutType.regular,
    this.summary = '',
    this.notes = const [],
    this.sizeAvailable = true,
    this.verdicts = const {},
  });

  /// `false` bila jenis ukuran produk tidak bisa dihitung (sepatu, dll).
  final bool supported;
  final String? size;
  final String? alternative;
  final CutType cut;
  final String summary;
  final List<String> notes;
  final bool sizeAvailable;

  /// Perkiraan jatuhnya tiap ukuran yang tersedia.
  final Map<String, FitVerdict> verdicts;

  static FitResult unsupported(String reason, CutType cut) => FitResult(
        supported: false,
        cut: cut,
        summary: reason,
      );
}

/// Ukuran huruf dasar (indeks pada [_letters]) dari tinggi dan berat badan.
int baseLetterIndex(FitProfile p) {
  final w = p.weightKg;
  var idx = p.gender == Gender.male
      ? (w <= 52 ? 1 : w <= 60 ? 2 : w <= 70 ? 3 : w <= 80 ? 4 : w <= 90 ? 5 : w <= 100 ? 6 : 7)
      : (w <= 45 ? 1 : w <= 52 ? 2 : w <= 60 ? 3 : w <= 68 ? 4 : w <= 76 ? 5 : w <= 86 ? 6 : 7);

  final tall = p.gender == Gender.male ? 178 : 170;
  final short = p.gender == Gender.male ? 160 : 150;
  if (p.heightCm >= tall) idx += 1;
  if (p.heightCm <= short && idx > 2) idx -= 1;
  return idx.clamp(0, _letters.length - 1).toInt();
}

/// Perkiraan lingkar pinggang (inci) dari BMI.
double estimateWaistInch(FitProfile p) {
  final bmi = p.bmi.clamp(15, 40).toDouble();
  final base = p.gender == Gender.male ? 27.0 : 24.0;
  return base + (bmi - 18) * 1.0;
}

/// Pergeseran ukuran: selisih keinginan pengguna dan kelonggaran bawaan produk.
int sizeShift(FitPreference pref, CutType cut) {
  final diff = pref.level - cut.ease;
  return (diff / 2).truncate();
}

/// Memperkirakan ukuran paling pas untuk [product].
FitResult recommendSize(FitProfile profile, Product product) {
  final cut = detectCut(product);
  final sizes = product.availableSizes;
  if (sizes.isEmpty) {
    return FitResult.unsupported('Ukuran produk belum tersedia.', cut);
  }
  if (product.audience == 'Kids' || product.audience == 'Baby') {
    return _recommendKids(profile, product, cut);
  }

  final families = {for (final s in sizes) _familyOf(s)};
  final notes = <String>[];
  final shift = sizeShift(profile.preference, cut);

  final String summary;
  if (shift < 0) {
    summary = 'Potongan ${cut.label.toLowerCase()} lebih longgar dari yang kamu '
        'suka, jadi ukuran diturunkan.';
  } else if (shift > 0) {
    summary = 'Potongan ${cut.label.toLowerCase()} lebih pas badan dari yang '
        'kamu suka, jadi ukuran dinaikkan.';
  } else {
    summary = 'Potongan ${cut.label.toLowerCase()} sudah sesuai pilihan '
        '"${profile.preference.label}" kamu.';
  }

  if (families.contains(SizeFamily.letter)) {
    return _recommendLetter(profile, product, cut, shift, summary, notes);
  }
  if (families.contains(SizeFamily.inch) || families.contains(SizeFamily.waistCm)) {
    return _recommendWaist(profile, product, cut, summary, notes);
  }
  if (families.contains(SizeFamily.oneSize)) {
    return FitResult(
      supported: true,
      size: sizes.first,
      cut: cut,
      summary: 'Produk ini hanya satu ukuran.',
      notes: const ['Cek panduan ukuran untuk dimensi produk.'],
    );
  }
  return FitResult.unsupported(
    'Ukuran produk ini (misalnya sepatu atau kaus kaki) mengikuti panduan '
    'ukuran, belum bisa dihitung dari tinggi dan berat.',
    cut,
  );
}

FitResult _recommendLetter(
  FitProfile profile,
  Product product,
  CutType cut,
  int shift,
  String summary,
  List<String> notes,
) {
  final available = <MapEntry<String, int>>[];
  for (final s in product.availableSizes) {
    final i = _letters.indexOf(s.trim().toUpperCase());
    if (i >= 0) available.add(MapEntry(s, i));
  }
  available.sort((a, b) => a.value.compareTo(b.value));

  final base = baseLetterIndex(profile);
  final target = (base + shift).clamp(0, _letters.length - 1).toInt();

  // Ukuran tersedia terdekat; bila sama dekat, condong ke pilihan pengguna.
  MapEntry<String, int>? best;
  for (final e in available) {
    if (best == null) {
      best = e;
      continue;
    }
    final d = (e.value - target).abs();
    final bd = (best.value - target).abs();
    if (d < bd) {
      best = e;
    } else if (d == bd) {
      final preferLarger = profile.preference != FitPreference.snug;
      if (preferLarger ? e.value > best.value : e.value < best.value) best = e;
    }
  }
  if (best == null) {
    return FitResult.unsupported('Ukuran produk belum tersedia.', cut);
  }

  String? alternative;
  for (final e in available) {
    if (e.key == best.key) continue;
    if ((e.value - best.value).abs() == 1) {
      // Alternatif: arah yang dekat dengan preferensi pengguna.
      final wantLarger = profile.preference == FitPreference.loose;
      if (alternative == null || (wantLarger ? e.value > best.value : e.value < best.value)) {
        alternative = e.key;
      }
    }
  }

  if (best.value != target) {
    notes.add('Ukuran ${_letters[target]} tidak tersedia, dipilih ${best.key}.');
  }
  notes.add('Perkiraan dasar dari ${profile.heightCm.round()} cm dan '
      '${profile.weightKg.round()} kg: ${_letters[base]}.');

  final verdicts = <String, FitVerdict>{
    for (final e in available) e.key: _verdict(e.value - best.value, profile, cut),
  };

  return FitResult(
    supported: true,
    size: best.key,
    alternative: alternative,
    cut: cut,
    summary: summary,
    notes: notes,
    verdicts: verdicts,
  );
}

FitVerdict _verdict(int stepsFromBest, FitProfile profile, CutType cut) {
  // Titik tengah: ukuran terbaik jatuh sesuai preferensi pengguna.
  final level = profile.preference.level + stepsFromBest;
  if (level <= -2) return FitVerdict.tight;
  if (level == -1) return FitVerdict.snug;
  if (level >= 1) return FitVerdict.loose;
  return FitVerdict.regular;
}

FitResult _recommendWaist(
  FitProfile profile,
  Product product,
  CutType cut,
  String summary,
  List<String> notes,
) {
  final waist = estimateWaistInch(profile);
  // Celana: pinggang ditambah kelonggaran sesuai preferensi dan potongan.
  final target = waist + profile.preference.level + cut.ease * 0.5;

  final entries = <MapEntry<String, double>>[];
  for (final s in product.availableSizes) {
    final u = s.trim().toUpperCase();
    final value = double.tryParse(u.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (value == null) continue;
    if (u.endsWith('INCH')) {
      entries.add(MapEntry(s, value));
    } else if (u.endsWith('CM')) {
      entries.add(MapEntry(s, value / 2.54));
    }
  }
  if (entries.isEmpty) {
    return FitResult.unsupported('Ukuran produk belum tersedia.', cut);
  }
  entries.sort((a, b) => a.value.compareTo(b.value));

  var best = entries.first;
  for (final e in entries) {
    if ((e.value - target).abs() < (best.value - target).abs()) best = e;
  }

  String? alternative;
  final idx = entries.indexWhere((e) => e.key == best.key);
  final wantLarger = profile.preference == FitPreference.loose;
  final neighbor = wantLarger ? idx + 1 : idx - 1;
  if (neighbor >= 0 && neighbor < entries.length) {
    alternative = entries[neighbor].key;
  } else if (idx + 1 < entries.length) {
    alternative = entries[idx + 1].key;
  } else if (idx - 1 >= 0) {
    alternative = entries[idx - 1].key;
  }

  notes.add('Perkiraan lingkar pinggang ${waist.toStringAsFixed(1)} inci dari '
      'tinggi dan berat badan. Ukur pinggang asli untuk hasil lebih akurat.');

  final verdicts = <String, FitVerdict>{
    for (final e in entries)
      e.key: _waistVerdict(e.value - (waist + cut.ease * 0.5)),
  };

  return FitResult(
    supported: true,
    size: best.key,
    alternative: alternative,
    cut: cut,
    summary: summary,
    notes: notes,
    verdicts: verdicts,
  );
}

FitVerdict _waistVerdict(double diffInch) {
  if (diffInch < -1) return FitVerdict.tight;
  if (diffInch < 0.5) return FitVerdict.snug;
  if (diffInch < 2.5) return FitVerdict.regular;
  return FitVerdict.loose;
}

/// Ukuran anak berdasarkan tinggi (cm) yang tertulis di label, mis. "(110cm)".
FitResult _recommendKids(FitProfile profile, Product product, CutType cut) {
  final entries = <MapEntry<String, double>>[];
  for (final s in product.availableSizes) {
    final m = RegExp(r'\((\d+)\s*cm\)', caseSensitive: false).firstMatch(s);
    if (m == null) continue;
    final cm = double.tryParse(m.group(1) ?? '');
    if (cm != null) entries.add(MapEntry(s, cm));
  }
  if (entries.isEmpty) {
    return FitResult.unsupported(
      'Ukuran anak mengikuti tinggi badan. Lihat panduan ukuran produk.',
      cut,
    );
  }
  entries.sort((a, b) => a.value.compareTo(b.value));

  // Isi tinggi badan ANAK pada kolom tinggi.
  final target = profile.heightCm + (profile.preference.level > 0 ? 5 : 0);
  var best = entries.first;
  for (final e in entries) {
    if ((e.value - target).abs() <= (best.value - target).abs()) best = e;
  }
  return FitResult(
    supported: true,
    size: best.key,
    cut: cut,
    summary: 'Untuk produk anak, ukuran dipilih dari tinggi badan anak '
        '(isi tinggi anak pada kolom tinggi).',
    notes: const ['Pilih satu ukuran lebih besar bila anak sedang tumbuh.'],
  );
}
