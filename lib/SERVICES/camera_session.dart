import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Mengelola kamera yang tersedia di perangkat.
///
/// - HP: kamera depan dan belakang (tombol ganti kamera).
/// - Laptop/desktop: webcam bawaan atau eksternal.
/// Perangkat tanpa kamera atau izin ditolak menghasilkan [error] agar layar
/// bisa menawarkan pilihan foto dari galeri.
class CameraSession extends ChangeNotifier {
  List<CameraDescription> _cameras = const [];
  int _index = 0;
  CameraController? _controller;
  String? _error;
  bool _initializing = false;
  bool _disposed = false;

  /// `true` setelah pengguna membalik tampilan (cermin) secara manual.
  bool? _mirrorOverride;

  CameraController? get controller => _controller;
  String? get error => _error;
  bool get initializing => _initializing;
  List<CameraDescription> get cameras => _cameras;
  bool get canSwitch => _cameras.length > 1;

  bool get isReady {
    final c = _controller;
    return c != null && c.value.isInitialized;
  }

  CameraDescription? get current =>
      _cameras.isEmpty ? null : _cameras[_index.clamp(0, _cameras.length - 1).toInt()];

  bool get isFront => current?.lensDirection == CameraLensDirection.front;

  String get currentLabel {
    final c = current;
    if (c == null) return 'Kamera';
    switch (c.lensDirection) {
      case CameraLensDirection.front:
        return 'Kamera depan';
      case CameraLensDirection.back:
        return 'Kamera belakang';
      case CameraLensDirection.external:
        return _cameras.length > 1 ? 'Webcam ${_index + 1}' : 'Webcam';
    }
  }

  /// Webcam laptop tidak dicerminkan oleh sistem; kamera depan HP sudah.
  bool get mirrored {
    final override = _mirrorOverride;
    if (override != null) return override;
    return current?.lensDirection == CameraLensDirection.external;
  }

  void toggleMirror() {
    _mirrorOverride = !mirrored;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Mencari kamera lalu membuka yang sesuai [prefer] (bila ada).
  Future<void> start({CameraLensDirection prefer = CameraLensDirection.front}) async {
    _initializing = true;
    _error = null;
    _notify();
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        _fail('Kamera tidak ditemukan di perangkat ini. '
            'Pilih foto dari galeri sebagai gantinya.');
        return;
      }
      final wanted = _cameras.indexWhere((c) => c.lensDirection == prefer);
      _index = wanted >= 0 ? wanted : 0;
      await _open();
    } on CameraException catch (e) {
      _failFor(e);
    } catch (_) {
      _fail('Kamera tidak bisa dibuka. Pilih foto dari galeri sebagai gantinya.');
    }
  }

  Future<void> _open() async {
    final description = _cameras[_index];
    final old = _controller;
    _controller = null;
    _mirrorOverride = null;
    _notify();
    await old?.dispose();

    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose();
      rethrow;
    }
    if (_disposed) {
      await controller.dispose();
      return;
    }
    _controller = controller;
    _initializing = false;
    _error = null;
    _notify();
  }

  /// Ganti ke kamera berikutnya (depan <-> belakang, atau webcam lain).
  Future<void> switchCamera() async {
    if (!canSwitch || _initializing) return;
    _initializing = true;
    _notify();
    _index = (_index + 1) % _cameras.length;
    try {
      await _open();
    } on CameraException catch (e) {
      _failFor(e);
    } catch (_) {
      _fail('Kamera tidak bisa dibuka.');
    }
  }

  /// Melepas kamera saat aplikasi di latar belakang.
  Future<void> pause() async {
    final old = _controller;
    if (old == null) return;
    _controller = null;
    _notify();
    await old.dispose();
  }

  /// Membuka lagi kamera setelah [pause].
  Future<void> resume() async {
    if (_disposed || _cameras.isEmpty || _controller != null || _initializing) {
      return;
    }
    _initializing = true;
    _notify();
    try {
      await _open();
    } on CameraException catch (e) {
      _failFor(e);
    } catch (_) {
      _fail('Kamera tidak bisa dibuka.');
    }
  }

  Future<Uint8List?> takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture) {
      return null;
    }
    final file = await c.takePicture();
    return file.readAsBytes();
  }

  void _failFor(CameraException e) {
    final denied = e.code.startsWith('CameraAccess');
    _fail(
      denied
          ? 'Izin kamera ditolak. Aktifkan izin kamera di Pengaturan, '
              'atau pilih foto dari galeri.'
          : 'Kamera tidak bisa dibuka. Pilih foto dari galeri sebagai gantinya.',
    );
  }

  void _fail(String message) {
    _error = message;
    _initializing = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }
}
