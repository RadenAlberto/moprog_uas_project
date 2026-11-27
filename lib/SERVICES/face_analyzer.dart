import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../MODELS/style_model.dart';

/// Analisis foto wajah di perangkat (tanpa mengirim foto ke server).
///
/// Cara kerja:
///  1. Foto diperkecil lalu tiap piksel diuji dengan model warna kulit
///     (YCbCr + aturan RGB) untuk membuat topeng kulit.
///  2. Dari topeng, lebar wajah diukur baris demi baris (dahi, pipi, rahang,
///     dagu) dan rasio panjang/lebar dihitung. Rasio itu diklasifikasi menjadi
///     oval, bulat, kotak, hati, atau lonjong.
///  3. Piksel kulit di area pipi dirata-rata, diubah ke ruang warna CIE Lab,
///     lalu diturunkan menjadi kedalaman warna (ITA) dan nada kulit (hue).
///
/// Ini estimasi berbasis aturan, bukan pengganti penilaian ahli. Hasilnya
/// selalu bisa dikoreksi pengguna pada layar konfirmasi.
class FaceAnalyzer {
  const FaceAnalyzer();

  /// Menganalisis foto (JPEG/PNG) dari [bytes].
  Future<FaceAnalysisResult> analyze(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 240);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      codec.dispose();
      if (data == null) {
        return const FaceAnalysisResult.failure(
          'Foto tidak bisa dibaca. Coba ambil foto lagi.',
        );
      }
      return analyzeRgba(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width,
        height,
      );
    } catch (_) {
      return const FaceAnalysisResult.failure(
        'Foto tidak bisa diproses. Coba ambil foto lagi.',
      );
    }
  }

  /// Inti analisis pada piksel RGBA mentah (mudah diuji tanpa kamera).
  FaceAnalysisResult analyzeRgba(Uint8List rgba, int width, int height) {
    if (width < 40 || height < 40 || rgba.length < width * height * 4) {
      return const FaceAnalysisResult.failure('Foto terlalu kecil.');
    }

    final x0 = (width * 0.15).round();
    final x1 = (width * 0.85).round();
    final y0 = (height * 0.10).round();
    final y1 = (height * 0.84).round();

    final mask = Uint8List(width * height);
    var skinCount = 0;
    var sumX = 0.0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final i = (y * width + x) * 4;
        if (_isSkin(rgba[i], rgba[i + 1], rgba[i + 2])) {
          mask[y * width + x] = 1;
          skinCount++;
          sumX += x;
        }
      }
    }

    final windowArea = (x1 - x0) * (y1 - y0);
    if (skinCount < windowArea * 0.06) {
      return const FaceAnalysisResult.failure(
        'Wajah belum terdeteksi. Pastikan wajah berada di dalam bingkai, '
        'cahaya cukup terang, dan tidak tertutup masker/kacamata gelap.',
      );
    }
    final cx = sumX / skinCount;

    // Lebar wajah per baris: pilih segmen kulit yang paling dekat ke pusat.
    final widths = List<double>.filled(height, 0);
    for (var y = y0; y < y1; y++) {
      var bestWidth = 0;
      var bestDist = double.infinity;
      var x = x0;
      while (x < x1) {
        if (mask[y * width + x] == 0) {
          x++;
          continue;
        }
        final start = x;
        var end = x;
        var gap = 0;
        while (x < x1) {
          if (mask[y * width + x] == 1) {
            end = x;
            gap = 0;
          } else {
            gap++;
            if (gap > 2) break;
          }
          x++;
        }
        final dist = (cx >= start && cx <= end)
            ? 0.0
            : math.min((cx - start).abs(), (cx - end).abs());
        final runWidth = end - start + 1;
        if (dist < bestDist || (dist == bestDist && runWidth > bestWidth)) {
          bestDist = dist;
          bestWidth = runWidth;
        }
      }
      widths[y] = bestWidth.toDouble();
    }

    // Haluskan dengan rata-rata 5 baris.
    final sm = List<double>.filled(height, 0);
    for (var y = y0; y < y1; y++) {
      final lo = math.max(y0, y - 2);
      final hi = math.min(y1 - 1, y + 2);
      var sum = 0.0;
      for (var k = lo; k <= hi; k++) {
        sum += widths[k];
      }
      sm[y] = sum / (hi - lo + 1);
    }

    var maxAll = 0.0;
    for (var y = y0; y < y1; y++) {
      if (sm[y] > maxAll) maxAll = sm[y];
    }
    if (maxAll < width * 0.12) {
      return const FaceAnalysisResult.failure(
        'Wajah terlalu kecil di foto. Dekatkan wajah ke kamera.',
      );
    }

    // Batas atas wajah (garis rambut/dahi).
    var top = y0;
    for (var y = y0; y < y1; y++) {
      if (sm[y] >= 0.40 * maxAll) {
        top = y;
        break;
      }
    }

    // Baris pipi: lebar maksimum pada 70% bagian atas area wajah.
    final limit = math.min(y1, top + ((y1 - top) * 0.7).floor());
    var cheek = top;
    for (var y = top; y < limit; y++) {
      if (sm[y] > sm[cheek]) cheek = y;
    }
    final maxW = sm[cheek];
    if (maxW <= 0) {
      return const FaceAnalysisResult.failure('Wajah tidak terdeteksi.');
    }

    // Batas bawah: titik saat lebar wajah menyatu dengan lebar leher.
    var stop = y1;
    var runMin = sm[cheek];
    for (var y = cheek; y < y1; y++) {
      if (sm[y] < 0.45 * maxW || sm[y] > runMin * 1.5 + 3) {
        stop = y;
        break;
      }
      runMin = math.min(runMin, sm[y]);
    }
    var neckW = maxW;
    if (stop - cheek >= 4) {
      final tail = sm.sublist(
        cheek + ((stop - cheek) * 0.7).floor(),
        stop,
      )..sort();
      neckW = tail[tail.length ~/ 2];
    }
    var bottom = stop - 1;
    for (var y = cheek; y < stop; y++) {
      if (sm[y] <= neckW * 1.08 + 1.0) {
        bottom = y;
        break;
      }
    }

    final faceHeight = bottom - top;
    if (faceHeight < height * 0.18) {
      return const FaceAnalysisResult.failure(
        'Wajah tidak terlihat utuh. Pastikan dahi sampai dagu masuk bingkai.',
      );
    }

    double widthAtFraction(double t) {
      final yy = (top + t * faceHeight).round();
      final lo = math.max(y0, yy - 1);
      final hi = math.min(y1 - 1, yy + 1);
      var sum = 0.0;
      for (var k = lo; k <= hi; k++) {
        sum += sm[k];
      }
      return sum / (hi - lo + 1);
    }

    double widthBelowCheek(double d) {
      final yy = math.min(y1 - 1, cheek + (d * maxW).round());
      final lo = math.max(y0, yy - 1);
      final hi = math.min(y1 - 1, yy + 1);
      var sum = 0.0;
      for (var k = lo; k <= hi; k++) {
        sum += sm[k];
      }
      return sum / (hi - lo + 1);
    }

    final lengthRatio = faceHeight / maxW;
    final shape = classifyFaceShape(
      lengthRatio: lengthRatio,
      foreheadRatio: widthAtFraction(0.22) / maxW,
      jawRatio: widthAtFraction(0.78) / maxW,
      chinRatio: widthAtFraction(0.92) / maxW,
      taperRatio: widthBelowCheek(0.35) / maxW,
    );

    // ---- Warna kulit: area pipi, di antara baris 35%..65% tinggi wajah ----
    final rowA = (top + 0.35 * faceHeight).round();
    final rowB = (top + 0.65 * faceHeight).round();
    final halfBand = (0.28 * maxW).round();
    final reds = <int>[];
    final greens = <int>[];
    final blues = <int>[];
    final lumas = <double>[];
    for (var y = rowA; y <= rowB && y < y1; y++) {
      final xa = math.max(x0, (cx - halfBand).round());
      final xb = math.min(x1 - 1, (cx + halfBand).round());
      for (var x = xa; x <= xb; x++) {
        if (mask[y * width + x] == 0) continue;
        final i = (y * width + x) * 4;
        reds.add(rgba[i]);
        greens.add(rgba[i + 1]);
        blues.add(rgba[i + 2]);
        lumas.add(0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2]);
      }
    }
    if (reds.length < 30) {
      return const FaceAnalysisResult.failure(
        'Warna kulit tidak terbaca jelas. Coba di tempat yang lebih terang.',
      );
    }
    final r = _median(reds);
    final g = _median(greens);
    final b = _median(blues);
    final meanLuma = lumas.reduce((a, c) => a + c) / lumas.length;

    final lab = rgbToLab(r, g, b);
    final ita = math.atan2(lab[0] - 50, lab[2]) * 180 / math.pi;
    final SkinDepth depth;
    if (ita > 41) {
      depth = SkinDepth.light;
    } else if (ita > -5) {
      depth = SkinDepth.medium;
    } else {
      depth = SkinDepth.deep;
    }
    final hue = math.atan2(lab[2], lab[1]) * 180 / math.pi;
    final Undertone undertone;
    if (hue >= 68) {
      undertone = Undertone.warm;
    } else if (hue <= 44) {
      undertone = Undertone.cool;
    } else {
      undertone = Undertone.neutral;
    }

    // Keyakinan: bergantung cakupan kulit dan pencahayaan.
    var confidence = 0.55;
    final coverage = skinCount / windowArea;
    if (coverage > 0.15) confidence += 0.15;
    if (meanLuma > 70 && meanLuma < 225) confidence += 0.2;
    if (faceHeight > height * 0.3) confidence += 0.1;
    confidence = confidence.clamp(0.0, 0.95).toDouble();

    var message = '';
    if (meanLuma <= 70) {
      message = 'Foto agak gelap, warna kulit bisa kurang akurat.';
    } else if (meanLuma >= 225) {
      message = 'Foto terlalu terang, warna kulit bisa kurang akurat.';
    }

    return FaceAnalysisResult.success(
      faceShape: shape,
      undertone: undertone,
      depth: depth,
      skinColorArgb: 0xFF000000 | (r << 16) | (g << 8) | b,
      confidence: confidence,
      lengthRatio: lengthRatio,
      message: message,
    );
  }
}

/// Aturan klasifikasi bentuk wajah dari rasio yang sudah diukur.
///
/// * [lengthRatio]: panjang wajah / lebar pipi
/// * [foreheadRatio], [jawRatio], [chinRatio]: lebar dahi, rahang, dagu / lebar pipi
/// * [taperRatio]: lebar sedikit di bawah pipi / lebar pipi (kecil = meruncing)
FaceShape classifyFaceShape({
  required double lengthRatio,
  required double foreheadRatio,
  required double jawRatio,
  required double chinRatio,
  required double taperRatio,
}) {
  if (lengthRatio >= 1.33) return FaceShape.oblong;
  if (foreheadRatio >= 0.84 && taperRatio <= 0.78) return FaceShape.heart;
  if (jawRatio >= 0.93 && chinRatio >= 0.70) return FaceShape.square;
  if (lengthRatio < 1.05) return FaceShape.round;
  return FaceShape.oval;
}

/// Uji warna kulit: YCbCr + aturan RGB sederhana.
bool _isSkin(int r, int g, int b) {
  final y = 0.299 * r + 0.587 * g + 0.114 * b;
  final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
  final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
  return cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173 && y >= 40 &&
      r > g && r > b * 0.9;
}

int _median(List<int> values) {
  final sorted = List<int>.from(values)..sort();
  return sorted[sorted.length ~/ 2];
}

/// sRGB (0..255) -> CIE Lab (D65). Mengembalikan [L, a, b].
List<double> rgbToLab(int r, int g, int b) {
  double lin(int v) {
    final c = v / 255.0;
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  final rl = lin(r);
  final gl = lin(g);
  final bl = lin(b);
  final x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047;
  final y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl;
  final z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883;

  double f(double t) {
    return t > 0.008856
        ? math.pow(t, 1 / 3).toDouble()
        : (7.787 * t) + 16 / 116;
  }

  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}
