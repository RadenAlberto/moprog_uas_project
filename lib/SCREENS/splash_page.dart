import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../WIDGETS/app_logo.dart';

/// Warna latar animasi pembuka (sama dengan latar native Android).
const Color kSplashBackground = Color(0xFF0D1213);

/// Lama animasi pembuka.
const Duration kSplashDuration = Duration(milliseconds: 3600);

const Color _red = Color(0xFFEC1C24);

/// Menampilkan animasi logo lebih dulu, lalu memudar masuk ke [child]
/// (aplikasi utama).
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});

  final Widget child;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  bool _done = false;

  void _finish() {
    if (!mounted || _done) return;
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: _done
          ? KeyedSubtree(key: const ValueKey('app'), child: widget.child)
          : SplashPage(key: const ValueKey('splash'), onFinished: _finish),
    );
  }
}

/// Mengubah waktu global [t] (0..1) menjadi progres 0..1 untuk satu tahap
/// animasi yang berlangsung dari [start] sampai [end].
double _seg(double t, double start, double end, [Curve curve = Curves.linear]) {
  final x = ((t - start) / (end - start)).clamp(0.0, 1.0).toDouble();
  return curve.transform(x);
}

/// Animasi pembuka UNIQLO PLUS (tanpa video, sepenuhnya dari kode):
///
/// 1. Grid dan cincin cahaya merah memancar dari tengah layar.
/// 2. Logo muncul membesar sambil berputar halus, lalu berpendar.
/// 3. Kilau cahaya menyapu logo.
/// 4. Titik-titik mengorbit logo.
/// 5. Tulisan UNIQLO PLUS muncul huruf demi huruf, disusul slogan.
/// 6. Garis progres terisi, lalu layar memudar masuk ke aplikasi.
///
/// Ketuk layar untuk melewati.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.onFinished});

  final VoidCallback onFinished;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: kSplashDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      })
      ..forward();
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSplashBackground,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _buildFrame(context, _controller.value),
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context, double t) {
    const logoSize = 150.0;
    // Pusat logo berada sedikit di atas tengah layar (karena ada teks di bawahnya).
    const logoOffsetY = -44.0;

    // Tahap logo.
    final pop = _seg(t, 0.06, 0.34, Curves.easeOutBack);
    final logoOpacity = _seg(t, 0.06, 0.18);
    final turn = (1 - _seg(t, 0.06, 0.34, Curves.easeOutCubic)) * -0.5;
    final glow = _seg(t, 0.2, 0.5);
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 6);
    final shine = _seg(t, 0.36, 0.62, Curves.easeInOut);

    // Tahap keluar: seluruh isi membesar sedikit lalu memudar ke aplikasi.
    final exit = _seg(t, 0.9, 1.0, Curves.easeIn);

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _BackdropPainter(t: t, centerOffsetY: logoOffsetY),
        ),
        Transform.scale(
          scale: 1 + 0.08 * exit,
          child: Opacity(
            opacity: 1 - exit,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: logoOpacity,
                    child: Transform.rotate(
                      angle: turn,
                      child: Transform.scale(
                        scale: 0.5 + 0.5 * pop,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: _red.withValues(
                                  alpha: (0.30 + 0.25 * pulse) * glow,
                                ),
                                blurRadius: 36 + 34 * pulse,
                                spreadRadius: 2 + 6 * pulse,
                              ),
                            ],
                          ),
                          child: ShaderMask(
                            blendMode: BlendMode.srcATop,
                            shaderCallback: (rect) => LinearGradient(
                              begin: const Alignment(-1, -0.4),
                              end: const Alignment(1, 0.4),
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.75),
                                Colors.white.withValues(alpha: 0),
                              ],
                              stops: const [0.38, 0.5, 0.62],
                              transform: _SlideGradient(-1 + 2 * shine),
                            ).createShader(rect),
                            child: const AppLogo(size: logoSize, radius: 6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  _LetterRow(t: t),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: _seg(t, 0.72, 0.88),
                    child: Transform.translate(
                      offset: Offset(0, 8 * (1 - _seg(t, 0.72, 0.88))),
                      child: const Text(
                        'LIFEWEAR UNTUK SEMUA',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          letterSpacing: 3.2,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _ProgressLine(progress: _seg(t, 0.1, 0.9, Curves.easeInOut)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Menggeser gradien horizontal (dipakai untuk kilau pada logo).
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.percent);

  final double percent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0, 0);
  }
}

/// Tulisan "UNIQLO PLUS" yang muncul huruf demi huruf.
class _LetterRow extends StatelessWidget {
  const _LetterRow({required this.t});

  final double t;

  static const String _text = 'UNIQLO PLUS';

  @override
  Widget build(BuildContext context) {
    final letters = _text.split('');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < letters.length; i++)
          () {
            final start = 0.42 + i * 0.026;
            final p = _seg(t, start, start + 0.16, Curves.easeOutCubic);
            if (letters[i] == ' ') return const SizedBox(width: 14);
            final isPlus = i >= 7;
            return Opacity(
              opacity: p,
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - p)),
                child: Text(
                  letters[i],
                  style: TextStyle(
                    color: isPlus ? _red : Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}

/// Garis progres tipis di bawah slogan.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const width = 128.0;
    return Opacity(
      opacity: _seg(progress, 0, 0.15),
      child: Stack(
        children: [
          Container(
            width: width,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            width: width * progress,
            height: 3,
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: _red.withValues(alpha: 0.7),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Latar: grid, cahaya radial, cincin yang memancar, dan titik yang mengorbit.
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({required this.t, required this.centerOffsetY});

  final double t;
  final double centerOffsetY;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + centerOffsetY);
    final maxRadius = math.sqrt(size.width * size.width + size.height * size.height) / 2;

    // Cahaya radial merah di belakang logo.
    final glow = _seg(t, 0.05, 0.5);
    final fadeOut = 1 - _seg(t, 0.9, 1.0);
    canvas.drawCircle(
      center,
      maxRadius * 0.7,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _red.withValues(alpha: 0.22 * glow * fadeOut),
            _red.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 0.7)),
    );

    // Grid tipis yang memudar ke arah tepi.
    final gridAlpha = 0.05 * _seg(t, 0.0, 0.4) * fadeOut;
    if (gridAlpha > 0) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: gridAlpha)
        ..strokeWidth = 1;
      const step = 36.0;
      for (var x = size.width / 2 % step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (var y = size.height / 2 % step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    // Tiga cincin cahaya yang memancar keluar secara berurutan.
    for (var i = 0; i < 3; i++) {
      final start = 0.08 + i * 0.09;
      final p = _seg(t, start, start + 0.5, Curves.easeOutCubic);
      if (p <= 0 || p >= 1) continue;
      canvas.drawCircle(
        center,
        maxRadius * p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _red.withValues(alpha: 0.38 * (1 - p)),
      );
    }

    // Orbit dengan titik-titik yang berputar mengelilingi logo.
    final orbitIn = _seg(t, 0.14, 0.4);
    final orbitAlpha = orbitIn * fadeOut;
    if (orbitAlpha > 0) {
      final orbitRadius = 112 + 10 * math.sin(t * math.pi * 2);
      canvas.drawCircle(
        center,
        orbitRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.08 * orbitAlpha),
      );
      const dots = 6;
      for (var i = 0; i < dots; i++) {
        final angle = i * 2 * math.pi / dots + t * 2 * math.pi * 1.1;
        final pos = center +
            Offset(math.cos(angle), math.sin(angle)) * orbitRadius;
        final isRed = i.isEven;
        canvas.drawCircle(
          pos,
          isRed ? 3.6 : 2.4,
          Paint()
            ..color = (isRed ? _red : Colors.white)
                .withValues(alpha: 0.9 * orbitAlpha),
        );
        if (isRed) {
          canvas.drawCircle(
            pos,
            9,
            Paint()..color = _red.withValues(alpha: 0.18 * orbitAlpha),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.centerOffsetY != centerOffsetY;
}
