import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Penyimpanan foto lokal (lemari digital, OOTD). Foto TIDAK dikirim ke server.
abstract class PhotoStore {
  /// Menyimpan [bytes] dan mengembalikan nama berkasnya.
  Future<String> save(Uint8List bytes, {String prefix = 'img', String ext = 'png'});

  Future<Uint8List?> read(String name);

  Future<void> delete(String name);
}

/// Penyimpanan di memori (untuk pengujian).
class MemoryPhotoStore implements PhotoStore {
  final Map<String, Uint8List> _files = {};
  int _counter = 0;

  @override
  Future<String> save(Uint8List bytes,
      {String prefix = 'img', String ext = 'png'}) async {
    final name = '${prefix}_${_counter++}.$ext';
    _files[name] = bytes;
    return name;
  }

  @override
  Future<Uint8List?> read(String name) async => _files[name];

  @override
  Future<void> delete(String name) async => _files.remove(name);
}

/// Penyimpanan berkas di folder dokumen aplikasi (Android, iOS, Windows, dst).
class FilePhotoStore implements PhotoStore {
  Directory? _dir;
  int _counter = 0;

  Future<Directory> _root() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}studio_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Hanya nama berkas biasa yang diterima (cegah akses ke folder lain).
  bool _safe(String name) =>
      name.isNotEmpty &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains('..');

  @override
  Future<String> save(Uint8List bytes,
      {String prefix = 'img', String ext = 'png'}) async {
    final dir = await _root();
    final name =
        '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.$ext';
    await File('${dir.path}${Platform.pathSeparator}$name').writeAsBytes(bytes);
    return name;
  }

  @override
  Future<Uint8List?> read(String name) async {
    if (!_safe(name)) return null;
    try {
      final dir = await _root();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String name) async {
    if (!_safe(name)) return;
    try {
      final dir = await _root();
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
