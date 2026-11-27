import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'image_cache.dart';

/// Hasil pemotretan pakaian: gambar tanpa latar + warna dominan.
class CutoutResult {
  const CutoutResult({
    required this.image,
    required this.png,
    required this.dominantArgb,
    required this.backgroundRemoved,
  });

  final ui.Image image;
  final Uint8List png;

  /// Warna dominan pakaian (ARGB).
  final int dominantArgb;

  /// `false` bila latar tidak bisa dipisahkan dan gambar dipakai apa adanya.
  final bool backgroundRemoved;
}

Future<ui.Image> decodeToImage(Uint8List bytes, {int? targetWidth}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List?> encodePng(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

Future<ui.Image> imageFromRgba(Uint8List pixels, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Mengecilkan foto (sisi terpanjang [maxWidth] piksel) lalu menyimpannya PNG.
Future<Uint8List> downscalePhoto(Uint8List bytes, {int maxWidth = 900}) async {
  final image = await decodeToImage(bytes, targetWidth: maxWidth);
  final png = await encodePng(image);
  image.dispose();
  if (png == null) throw StateError('Foto tidak bisa diproses');
  return png;
}

/// Memisahkan pakaian dari latar polos (foto produk/foto di atas kasur, dsb).
///
/// Latar diperkirakan dari warna rata-rata tepi gambar, lalu area yang mirip
/// dan tersambung ke tepi dihapus (flood fill). Hasilnya dipangkas ke ukuran
/// pakaian. Bila latar tidak bisa dipisahkan, gambar dipakai apa adanya.
Future<CutoutResult> cutoutGarment(
  Uint8List bytes, {
  int maxWidth = 520,
  int tolerance = 34,
  bool removeBackground = true,
}) async {
  final src = await decodeToImage(bytes, targetWidth: maxWidth);
  final w = src.width;
  final h = src.height;
  final data = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
  src.dispose();
  if (data == null || w < 4 || h < 4) {
    throw StateError('Gambar tidak bisa dibaca');
  }
  final px = Uint8List.fromList(data.buffer.asUint8List());

  if (removeBackground) {
    final result = _tryCutout(px, w, h, tolerance) ??
        _tryCutout(Uint8List.fromList(data.buffer.asUint8List()), w, h, 14);
    if (result != null) {
      final image = await imageFromRgba(result.pixels, result.width, result.height);
      final png = await encodePng(image);
      if (png != null) {
        return CutoutResult(
          image: image,
          png: png,
          dominantArgb: result.dominant,
          backgroundRemoved: true,
        );
      }
    }
  }

  // Tanpa pemisahan latar: pakai gambar utuh.
  final plain = Uint8List.fromList(data.buffer.asUint8List());
  final image = await imageFromRgba(plain, w, h);
  final png = await encodePng(image);
  if (png == null) throw StateError('Gambar tidak bisa disimpan');
  return CutoutResult(
    image: image,
    png: png,
    dominantArgb: _dominant(plain, w * h, null),
    backgroundRemoved: false,
  );
}

class _CutPixels {
  _CutPixels(this.pixels, this.width, this.height, this.dominant);

  final Uint8List pixels;
  final int width;
  final int height;
  final int dominant;
}

_CutPixels? _tryCutout(Uint8List px, int w, int h, int tol) {
  final total = w * h;

  // Perkiraan warna latar dari piksel tepi.
  var sr = 0, sg = 0, sb = 0, n = 0, transparentEdge = 0;
  void sample(int x, int y) {
    final i = (y * w + x) * 4;
    sr += px[i];
    sg += px[i + 1];
    sb += px[i + 2];
    if (px[i + 3] < 20) transparentEdge++;
    n++;
  }

  for (var x = 0; x < w; x++) {
    sample(x, 0);
    sample(x, h - 1);
  }
  for (var y = 1; y < h - 1; y++) {
    sample(0, y);
    sample(w - 1, y);
  }
  // Gambar sudah punya latar transparan: tidak perlu dipotong lagi.
  if (transparentEdge > n ~/ 2) return null;

  final bgR = sr ~/ n;
  final bgG = sg ~/ n;
  final bgB = sb ~/ n;

  bool nearBackground(int p) {
    final i = p * 4;
    return (px[i] - bgR).abs() <= tol &&
        (px[i + 1] - bgG).abs() <= tol &&
        (px[i + 2] - bgB).abs() <= tol;
  }

  final removed = Uint8List(total);
  final queue = Int32List(total);
  var head = 0;
  var tail = 0;

  void push(int x, int y) {
    final p = y * w + x;
    if (removed[p] == 1 || !nearBackground(p)) return;
    removed[p] = 1;
    queue[tail++] = p;
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (head < tail) {
    final p = queue[head++];
    final x = p % w;
    final y = p ~/ w;
    if (x > 0) push(x - 1, y);
    if (x < w - 1) push(x + 1, y);
    if (y > 0) push(x, y - 1);
    if (y < h - 1) push(x, y + 1);
  }

  final fraction = tail / total;
  // Terlalu sedikit = latar tidak polos; terlalu banyak = pakaian semirip latar.
  if (fraction < 0.05 || fraction > 0.93) return null;

  // Kotak pembatas pakaian.
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (removed[y * w + x] == 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  const pad = 6;
  minX = (minX - pad).clamp(0, w - 1).toInt();
  minY = (minY - pad).clamp(0, h - 1).toInt();
  maxX = (maxX + pad).clamp(0, w - 1).toInt();
  maxY = (maxY + pad).clamp(0, h - 1).toInt();
  final cw = maxX - minX + 1;
  final ch = maxY - minY + 1;
  if (cw < w * 0.1 || ch < h * 0.1) return null;

  final out = Uint8List(cw * ch * 4);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      final sx = x + minX;
      final sy = y + minY;
      final p = sy * w + sx;
      final o = (y * cw + x) * 4;
      if (removed[p] == 1) continue; // tetap transparan (0,0,0,0)
      final i = p * 4;
      out[o] = px[i];
      out[o + 1] = px[i + 1];
      out[o + 2] = px[i + 2];

      // Tepi dilembutkan agar tidak bergerigi.
      var edge = false;
      if (sx > 0 && removed[p - 1] == 1) edge = true;
      if (sx < w - 1 && removed[p + 1] == 1) edge = true;
      if (sy > 0 && removed[p - w] == 1) edge = true;
      if (sy < h - 1 && removed[p + w] == 1) edge = true;
      out[o + 3] = edge ? 190 : 255;
    }
  }

  return _CutPixels(out, cw, ch, _dominant(out, cw * ch, 200));
}

/// Warna dominan dari piksel yang cukup buram (modus histogram 4 bit/kanal).
int _dominant(Uint8List px, int count, int? minAlpha) {
  final counts = Int32List(4096);
  final sumR = Int32List(4096);
  final sumG = Int32List(4096);
  final sumB = Int32List(4096);
  var any = false;
  for (var p = 0; p < count; p++) {
    final i = p * 4;
    if (minAlpha != null && px[i + 3] < minAlpha) continue;
    final r = px[i], g = px[i + 1], b = px[i + 2];
    final bucket = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
    counts[bucket]++;
    sumR[bucket] += r;
    sumG[bucket] += g;
    sumB[bucket] += b;
    any = true;
  }
  if (!any) return 0xFF9E9E9E;
  var best = 0;
  for (var k = 1; k < 4096; k++) {
    if (counts[k] > counts[best]) best = k;
  }
  final c = counts[best];
  final r = sumR[best] ~/ c;
  final g = sumG[best] ~/ c;
  final b = sumB[best] ~/ c;
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}

/// Mengambil foto produk dari cache perangkat (mengunduh bila belum ada).
Future<Uint8List> loadNetworkBytes(String url) async {
  final File file = await kImageCache.getSingleFile(url);
  return file.readAsBytes();
}

/// Cache hasil pemotretan foto produk agar tidak diproses ulang.
class GarmentCutoutCache {
  GarmentCutoutCache._();

  static final Map<String, Future<CutoutResult>> _cache = {};

  static Future<CutoutResult> forUrl(String url) {
    return _cache.putIfAbsent(url, () async {
      final bytes = await loadNetworkBytes(url);
      return cutoutGarment(bytes);
    }).catchError((Object e) {
      _cache.remove(url);
      throw e;
    });
  }
}
