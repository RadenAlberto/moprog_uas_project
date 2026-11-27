import 'package:flutter/material.dart';

import '../DATA/product_data.dart';
import '../SERVICES/image_cache.dart';
import '../UTILS/app_theme.dart';

/// Menyimpan foto produk ke perangkat supaya tetap tampil tanpa internet.
/// Foto yang pernah dibuka otomatis tersimpan; halaman ini untuk mengunduh
/// sekaligus (sebaiknya lewat Wi-Fi).
class OfflinePhotosPage extends StatefulWidget {
  const OfflinePhotosPage({super.key});

  @override
  State<OfflinePhotosPage> createState() => _OfflinePhotosPageState();
}

class _OfflinePhotosPageState extends State<OfflinePhotosPage> {
  final ImagePrefetcher _prefetcher = ImagePrefetcher();

  late final List<String> _mainPhotos = [
    for (final p in kProducts) p.image,
  ].where((u) => u.isNotEmpty).toSet().toList();

  late final List<String> _colorPhotos = [
    for (final p in kProducts) ...p.colorImages,
  ].where((u) => u.isNotEmpty).toSet().toList();

  @override
  void initState() {
    super.initState();
    _prefetcher.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _prefetcher.removeListener(_refresh);
    _prefetcher.cancel();
    _prefetcher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _prefetcher;
    return Scaffold(
      appBar: AppBar(title: const Text('Foto untuk Offline')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Foto produk diunduh dari server Uniqlo satu kali, lalu disimpan '
            'di perangkat. Setelah itu foto tampil tanpa internet. Foto yang '
            'pernah kamu buka sudah tersimpan otomatis.',
            style: TextStyle(height: 1.4),
          ),
          const SizedBox(height: 16),
          if (p.running || p.total > 0) ...[
            LinearProgressIndicator(value: p.running ? p.progress : 1),
            const SizedBox(height: 8),
            Text(
              '${p.done} dari ${p.total} foto tersimpan'
              '${p.failed > 0 ? ' - ${p.failed} gagal (coba lagi)' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
          ],
          FilledButton.icon(
            onPressed: p.running ? null : () => p.start(_mainPhotos),
            icon: const Icon(Icons.download),
            label: Text('Simpan foto utama (${_mainPhotos.length} foto)'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: p.running ? null : () => p.start(_colorPhotos),
            icon: const Icon(Icons.palette_outlined),
            label: Text('Simpan semua warna (${_colorPhotos.length} foto)'),
          ),
          if (p.running) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: p.cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Hentikan'),
            ),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.ink),
            onPressed: p.running ? null : p.clear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Hapus foto tersimpan'),
          ),
        ],
      ),
    );
  }
}
