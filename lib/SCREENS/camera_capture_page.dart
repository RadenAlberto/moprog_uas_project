import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../SERVICES/camera_session.dart';
import '../UTILS/app_theme.dart';

/// Kamera untuk memotret (selfie, pakaian, OOTD).
///
/// Berjalan di HP (kamera depan dan belakang, tombol ganti kamera) maupun
/// laptop/desktop (webcam). Mengembalikan byte foto lewat `Navigator.pop`,
/// atau `null` bila dibatalkan. Bila kamera tidak tersedia atau izin ditolak,
/// pengguna bisa memilih foto dari galeri/berkas.
///
/// Foto hanya dipakai di memori oleh pemanggil; halaman ini tidak menyimpan
/// atau mengirim foto ke mana pun.
class CameraCapturePage extends StatefulWidget {
  const CameraCapturePage({
    super.key,
    this.title = 'Foto selfie',
    this.hint = 'Posisikan wajah di dalam bingkai, tatap kamera, '
        'wajah terlihat utuh dan cahaya merata.',
    this.showFaceGuide = true,
    this.preferFront = true,
    this.useTimer = true,
  });

  final String title;
  final String hint;

  /// Bingkai oval untuk selfie. Matikan untuk memotret pakaian/OOTD.
  final bool showFaceGuide;
  final bool preferFront;
  final bool useTimer;

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
  final CameraSession _session = CameraSession();
  bool _capturing = false;
  late bool _useTimer = widget.useTimer;
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSession);
    unawaited(
      _session.start(
        prefer: widget.preferFront
            ? CameraLensDirection.front
            : CameraLensDirection.back,
      ),
    );
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _session.removeListener(_onSession);
    _session.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_session.pause());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_session.resume());
    }
  }

  Future<void> _onShutter() async {
    if (_capturing) return;
    if (!_useTimer) {
      await _capture();
      return;
    }
    setState(() {
      _capturing = true;
      _countdown = 3;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown--);
        return;
      }
      timer.cancel();
      setState(() => _countdown = 0);
      await _capture();
    });
  }

  Future<void> _capture() async {
    if (mounted) setState(() => _capturing = true);
    try {
      final bytes = await _session.takePicture();
      if (bytes == null) {
        if (mounted) setState(() => _capturing = false);
        return;
      }
      if (mounted) Navigator.of(context).pop<Uint8List>(bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengambil foto. Coba lagi.')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        imageQuality: 90,
      );
      if (picked == null) return;
      final Uint8List bytes = await picked.readAsBytes();
      if (mounted) Navigator.of(context).pop<Uint8List>(bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto tidak bisa dibuka.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _session.controller;
    final ready = _session.isReady && controller != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready) _buildPreview(controller),
            if (ready && widget.showFaceGuide)
              const IgnorePointer(child: CustomPaint(painter: _FaceGuidePainter())),
            if (_session.initializing)
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_session.error != null && !_session.initializing) _buildError(),
            _buildTopBar(),
            if (ready) _buildBottomBar(),
            if (_countdown > 0)
              Center(
                child: Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 96,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Pratinjau utuh (tanpa terpotong) di tengah layar. Bentuk dan arah
  /// pratinjau diatur oleh plugin kamera, jadi tidak ada gambar yang melar.
  Widget _buildPreview(CameraController controller) {
    Widget preview = CameraPreview(controller);
    if (_session.mirrored) {
      preview = Transform.flip(flipX: true, child: preview);
    }
    return Center(child: preview);
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 4,
      left: 4,
      right: 4,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop<Uint8List>(),
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Tutup',
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (_session.isReady)
                  Text(
                    _session.currentLabel,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (_session.canSwitch)
            IconButton(
              onPressed: _capturing ? null : _session.switchCamera,
              icon: const Icon(Icons.flip_camera_android, color: Colors.white),
              tooltip: 'Ganti kamera',
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Colors.white70, size: 56),
            const SizedBox(height: 14),
            Text(
              _session.error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, height: 1.4),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Pilih dari galeri'),
            ),
            TextButton(
              onPressed: () => _session.start(
                prefer: widget.preferFront
                    ? CameraLensDirection.front
                    : CameraLensDirection.back,
              ),
              child: const Text(
                'Coba kamera lagi',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.hint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _RoundButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Galeri',
                  onTap: _capturing ? null : _pickFromGallery,
                ),
                GestureDetector(
                  onTap: _capturing ? null : _onShutter,
                  child: Container(
                    width: 74,
                    height: 74,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _capturing ? Colors.white38 : Colors.white,
                      ),
                    ),
                  ),
                ),
                _RoundButton(
                  icon: _useTimer ? Icons.timer : Icons.timer_off_outlined,
                  label: _useTimer ? 'Timer 3s' : 'Timer mati',
                  onTap: _capturing
                      ? null
                      : () => setState(() => _useTimer = !_useTimer),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap == null ? Colors.white38 : Colors.white),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bingkai oval panduan wajah dengan latar digelapkan.
class _FaceGuidePainter extends CustomPainter {
  const _FaceGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * 0.74;
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.40),
      width: width,
      height: width * 1.25,
    );
    final overlay = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(oval),
    );
    canvas.drawPath(overlay, Paint()..color = Colors.black54);
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) => false;
}
