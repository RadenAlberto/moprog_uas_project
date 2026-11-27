import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Penyimpanan foto di perangkat. Foto diunduh sekali dari server gambar
/// Uniqlo, lalu dibaca dari penyimpanan lokal (tetap tampil saat offline).
final CacheManager kImageCache = CacheManager(
  Config(
    'uniqloImages',
    stalePeriod: const Duration(days: 90),
    maxNrOfCacheObjects: 8000,
  ),
);

/// Mengunduh banyak foto sekaligus ke [kImageCache] di latar belakang
/// (4 unduhan paralel). Foto yang sudah tersimpan dilewati, foto yang gagal
/// dihitung terpisah dan bisa dicoba lagi dengan menjalankan ulang.
class ImagePrefetcher extends ChangeNotifier {
  ImagePrefetcher({this.concurrency = 4});

  final int concurrency;

  int total = 0;
  int done = 0; // sudah tersimpan (termasuk yang sudah ada sebelumnya)
  int failed = 0;
  bool running = false;
  bool _cancel = false;

  double get progress => total == 0 ? 0 : (done + failed) / total;

  Future<void> start(Iterable<String> urls) async {
    if (running) return;
    final queue = urls.where((u) => u.isNotEmpty).toSet().toList();
    total = queue.length;
    done = 0;
    failed = 0;
    running = true;
    _cancel = false;
    notifyListeners();

    var next = 0;
    Future<void> worker() async {
      while (!_cancel) {
        if (next >= queue.length) return;
        final url = queue[next++];
        try {
          final cached = await kImageCache.getFileFromCache(url);
          if (cached == null) await kImageCache.downloadFile(url);
          done++;
        } catch (_) {
          failed++;
        }
        notifyListeners();
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
    running = false;
    notifyListeners();
  }

  void cancel() => _cancel = true;

  /// Menghapus semua foto tersimpan.
  Future<void> clear() async {
    await kImageCache.emptyCache();
    done = 0;
    failed = 0;
    total = 0;
    notifyListeners();
  }
}
