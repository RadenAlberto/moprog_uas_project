import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/style_provider.dart';
import '../PROVIDERS/wardrobe_provider.dart';
import '../SERVICES/camera_session.dart';
import '../SERVICES/color_utils.dart';
import '../SERVICES/image_tools.dart';
import '../SERVICES/outfit_engine.dart';
import '../SERVICES/photo_store.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/studio_widgets.dart';
import 'ootd_page.dart';

class _Garment {
  const _Garment({
    required this.image,
    required this.slot,
    required this.label,
    required this.color,
    this.product,
    this.colorIndex = 0,
  });

  final ui.Image image;
  final ClothingSlot slot;
  final String label;
  final Color? color;
  final Product? product;
  final int colorIndex;
}

/// Posisi awal tiap jenis pakaian: (pusat x, pusat y, lebar relatif).
(double, double, double) _placementFor(ClothingSlot slot) {
  switch (slot) {
    case ClothingSlot.top:
      return (0.5, 0.40, 0.62);
    case ClothingSlot.bottom:
      return (0.5, 0.70, 0.48);
    case ClothingSlot.outer:
      return (0.5, 0.42, 0.74);
    case ClothingSlot.dress:
      return (0.5, 0.56, 0.60);
    case ClothingSlot.accessory:
      return (0.5, 0.20, 0.30);
  }
}

/// Coba pakaian virtual: pakaian ditempel di atas pratinjau kamera.
///
/// Kamera mengikuti perangkat: depan/belakang di HP, webcam di laptop. Pakaian
/// digeser, diperbesar, dan diputar dengan jari atau mouse (roda untuk zoom).
/// Ini overlay 2D (bukan pelacakan tubuh/AR penuh): pengguna menyelaraskannya
/// sendiri dengan garis bantu.
class TryOnPage extends StatefulWidget {
  const TryOnPage({super.key, this.product, this.wardrobeItem});

  final Product? product;
  final WardrobeItem? wardrobeItem;

  @override
  State<TryOnPage> createState() => _TryOnPageState();
}

class _TryOnPageState extends State<TryOnPage> with WidgetsBindingObserver {
  final CameraSession _session = CameraSession();
  final GlobalKey _captureKey = GlobalKey();

  _Garment? _garment;
  bool _loadingGarment = false;
  String? _garmentError;

  // Foto dari galeri bila kamera tidak tersedia.
  Uint8List? _still;
  double _stillAspect = 3 / 4;

  Offset _center = const Offset(0.5, 0.4);
  double _scale = 1;
  double _rotation = 0;
  double _opacity = 0.95;
  double _baseScale = 1;
  double _baseRotation = 0;
  bool _guide = true;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSession);
    unawaited(_session.start(prefer: CameraLensDirection.front));
    final product = widget.product;
    final item = widget.wardrobeItem;
    if (product != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useProduct(product, 0));
    } else if (item != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _useWardrobe(item));
    }
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    _session.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_still != null) return;
    if (state == AppLifecycleState.inactive) {
      unawaited(_session.pause());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_session.resume());
    }
  }

  void _place(ClothingSlot slot) {
    final p = _placementFor(slot);
    _center = Offset(p.$1, p.$2);
    _scale = 1;
    _rotation = 0;
  }

  // --- Memilih pakaian -------------------------------------------------------

  Future<void> _useProduct(Product p, int colorIndex) async {
    final urls = p.colorImages;
    final url = colorIndex >= 0 && colorIndex < urls.length && urls[colorIndex].isNotEmpty
        ? urls[colorIndex]
        : p.image;
    setState(() {
      _loadingGarment = true;
      _garmentError = null;
    });
    try {
      final cut = await GarmentCutoutCache.forUrl(url);
      if (!mounted) return;
      final slot = slotOfProduct(p) ?? ClothingSlot.top;
      final keepPlacement = _garment?.slot == slot && _garment?.product?.id == p.id;
      setState(() {
        _garment = _Garment(
          image: cut.image,
          slot: slot,
          label: p.name,
          color: colorIndex >= 0 && colorIndex < p.availableColors.length
              ? p.availableColors[colorIndex]
              : null,
          product: p,
          colorIndex: colorIndex,
        );
        if (!keepPlacement) _place(slot);
        _loadingGarment = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGarment = false;
        _garmentError = 'Foto produk belum bisa dimuat. Periksa koneksi internet.';
      });
    }
  }

  Future<void> _useWardrobe(WardrobeItem item) async {
    setState(() {
      _loadingGarment = true;
      _garmentError = null;
    });
    try {
      final bytes = await context.read<PhotoStore>().read(item.photo);
      if (bytes == null) throw StateError('foto hilang');
      final image = await decodeToImage(bytes);
      if (!mounted) return;
      setState(() {
        _garment = _Garment(
          image: image,
          slot: item.slot,
          label: item.name,
          color: item.color,
        );
        _place(item.slot);
        _loadingGarment = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGarment = false;
        _garmentError = 'Foto pakaian tidak bisa dibuka.';
      });
    }
  }

  Future<void> _chooseGarment() async {
    final wardrobe = context.read<WardrobeProvider>().items;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pilih pakaian', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.storefront_outlined, color: AppColors.red),
              title: const Text('Dari katalog UNIQLO'),
              subtitle: const Text('Atasan, bawahan, luaran, atau terusan'),
              onTap: () => Navigator.of(sheetContext).pop('catalog'),
            ),
            const Divider(),
            const Text('Dari lemari digitalmu', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (wardrobe.isEmpty)
              const Text(
                'Lemarimu masih kosong. Tambahkan pakaian lewat Lemari Digital.',
                style: TextStyle(color: AppColors.muted),
              )
            else
              SizedBox(
                height: 110,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: wardrobe.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => InkWell(
                    onTap: () => Navigator.of(sheetContext).pop(wardrobe[i]),
                    child: Container(
                      width: 90,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F1F3),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: StoredImage(wardrobe[i].photo, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice is WardrobeItem) {
      await _useWardrobe(choice);
    } else if (choice == 'catalog') {
      final catalog = context.read<AppState>().allProducts;
      final p = await pickCatalogProduct(
        context,
        catalog,
        title: 'Pilih produk untuk dicoba',
        filter: (p) {
          final slot = slotOfProduct(p);
          return slot != null &&
              slot != ClothingSlot.accessory &&
              (p.audience == 'Men' || p.audience == 'Women' || p.audience == 'Unisex');
        },
      );
      if (p != null && mounted) await _useProduct(p, 0);
    }
  }

  // --- Foto & hasil ------------------------------------------------------------

  Future<void> _pickStill() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
      final bytes = await picked?.readAsBytes();
      if (bytes == null) return;
      final image = await decodeToImage(bytes, targetWidth: 800);
      final aspect = image.width / image.height;
      image.dispose();
      await _session.pause();
      if (!mounted) return;
      setState(() {
        _still = bytes;
        _stillAspect = aspect;
      });
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'Foto tidak bisa dibuka.',
            color: AppColors.red, icon: Icons.error_outline);
      }
    }
  }

  Future<void> _useCameraAgain() async {
    setState(() => _still = null);
    await _session.resume();
    if (!_session.isReady) await _session.start();
  }

  Future<void> _capture() async {
    if (_capturing) return;
    if (_garment == null) {
      showAppToast(context, 'Pilih pakaian dulu.',
          color: AppColors.red, icon: Icons.info_outline);
      return;
    }
    setState(() => _capturing = true);
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('stage');
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('png');
      if (!mounted) return;
      await _showResult(data.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        showAppToast(context, 'Gagal mengambil gambar. Coba lagi.',
            color: AppColors.red, icon: Icons.error_outline);
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _showResult(Uint8List png) async {
    final productId = _garment?.product?.id;
    final post = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Image.memory(png, fit: BoxFit.contain)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Ulangi'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Bagikan ke OOTD'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (post == true && mounted) {
      await startOotdPost(
        context,
        photo: png,
        productIds: productId == null ? const [] : [productId],
      );
    }
  }

  // --- Tampilan ------------------------------------------------------------------

  Widget _stage() {
    final controller = _session.controller;
    Widget background;
    if (_still != null) {
      background = AspectRatio(
        aspectRatio: _stillAspect,
        child: Image.memory(_still!, fit: BoxFit.fill),
      );
    } else if (_session.isReady && controller != null) {
      Widget preview = CameraPreview(controller);
      if (_session.mirrored) preview = Transform.flip(flipX: true, child: preview);
      background = preview;
    } else {
      background = AspectRatio(
        aspectRatio: 3 / 4,
        child: Container(
          color: const Color(0xFF1B1B1D),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: _session.initializing
              ? const CircularProgressIndicator(color: Colors.white)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, color: Colors.white54, size: 44),
                    const SizedBox(height: 10),
                    Text(
                      _session.error ?? 'Kamera belum siap.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _pickStill,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Pakai foto dari galeri'),
                    ),
                    TextButton(
                      onPressed: () => _session.start(),
                      child: const Text('Coba kamera lagi', style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ),
        ),
      );
    }

    return Center(
      child: RepaintBoundary(
        key: _captureKey,
        child: Stack(
          children: [
            background,
            Positioned.fill(child: _overlay()),
          ],
        ),
      ),
    );
  }

  Widget _overlay() {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final g = _garment;
        final base = g == null ? 0.0 : _placementFor(g.slot).$3;
        Widget? garment;
        if (g != null && w.isFinite && h.isFinite) {
          final bw = w * base * _scale;
          final bh = bw * g.image.height / g.image.width;
          garment = Positioned(
            left: _center.dx * w - bw / 2,
            top: _center.dy * h - bh / 2,
            width: bw,
            height: bh,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: _rotation,
                child: Opacity(
                  opacity: _opacity,
                  child: RawImage(image: g.image, fit: BoxFit.fill),
                ),
              ),
            ),
          );
        }
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              setState(() {
                _scale = (_scale * (event.scrollDelta.dy > 0 ? 0.95 : 1.05))
                    .clamp(0.3, 3.0)
                    .toDouble();
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) {
              _baseScale = _scale;
              _baseRotation = _rotation;
            },
            onScaleUpdate: (d) {
              if (w <= 0 || h <= 0) return;
              setState(() {
                _center = Offset(
                  (_center.dx + d.focalPointDelta.dx / w).clamp(0.0, 1.0).toDouble(),
                  (_center.dy + d.focalPointDelta.dy / h).clamp(0.0, 1.0).toDouble(),
                );
                _scale = (_baseScale * d.scale).clamp(0.3, 3.0).toDouble();
                _rotation = _baseRotation + d.rotation;
              });
            },
            child: Stack(
              children: [
                if (_guide) const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _BodyGuidePainter()))),
                if (garment != null) garment,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _controls() {
    final g = _garment;
    final p = g?.product;
    final skin = context.watch<StyleProvider>().profile?.skinColor;
    Harmony? skinHarmony;
    if (skin != null && g?.color != null) skinHarmony = colorHarmony(skin, g!.color!);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      g?.label ?? 'Belum ada pakaian dipilih',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_loadingGarment)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  TextButton.icon(
                    onPressed: _chooseGarment,
                    icon: const Icon(Icons.checkroom, size: 18),
                    label: const Text('Pilih'),
                  ),
                ],
              ),
              if (_garmentError != null)
                Text(_garmentError!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
              if (p != null && p.availableColors.length > 1)
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: p.availableColors.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final selected = g?.colorIndex == i;
                      return GestureDetector(
                        onTap: () => _useProduct(p, i),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: p.availableColors[i],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? AppColors.red : Colors.black26,
                              width: selected ? 3 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              if (skinHarmony != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      ColorDot(skin!, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Dengan warna kulitmu: ${skinHarmony.kind.description}',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              _slider('Ukuran', _scale, 0.3, 3, (v) => setState(() => _scale = v)),
              _slider('Putar', _rotation, -0.8, 0.8, (v) => setState(() => _rotation = v)),
              _slider('Opasitas', _opacity, 0.4, 1, (v) => setState(() => _opacity = v)),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 4,
                children: [
                  if (_session.canSwitch && _still == null)
                    _tool(Icons.flip_camera_android, _session.currentLabel, _session.switchCamera),
                  if (_still == null)
                    _tool(Icons.flip, _session.mirrored ? 'Cermin: on' : 'Cermin: off', _session.toggleMirror),
                  _tool(Icons.accessibility_new, _guide ? 'Garis bantu' : 'Tanpa garis', () => setState(() => _guide = !_guide)),
                  _tool(Icons.restart_alt, 'Reset', () => setState(() {
                        _place(g?.slot ?? ClothingSlot.top);
                        _opacity = 0.95;
                      })),
                  if (_still == null)
                    _tool(Icons.photo_library_outlined, 'Foto galeri', _pickStill)
                  else
                    _tool(Icons.videocam_outlined, 'Kamera', _useCameraAgain),
                ],
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: _capturing ? null : _capture,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(_capturing ? 'Memproses...' : 'AMBIL GAMBAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            activeColor: AppColors.red,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('COBA VIRTUAL'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 820;
          if (wide) {
            return Row(
              children: [
                Expanded(child: _stage()),
                SizedBox(width: 360, child: _controls()),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: _stage()),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: box.maxHeight * 0.52),
                child: _controls(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Garis bantu siluet tubuh untuk menyelaraskan pakaian.
class _BodyGuidePainter extends CustomPainter {
  const _BodyGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.white.withValues(alpha: 0.55);
    final w = size.width;
    final h = size.height;
    canvas.drawCircle(Offset(w * 0.5, h * 0.13), w * 0.075, paint);
    final shoulder = Path()
      ..moveTo(w * 0.24, h * 0.27)
      ..quadraticBezierTo(w * 0.5, h * 0.21, w * 0.76, h * 0.27)
      ..lineTo(w * 0.70, h * 0.58)
      ..lineTo(w * 0.30, h * 0.58)
      ..close();
    canvas.drawPath(shoulder, paint);
    canvas.drawLine(Offset(w * 0.34, h * 0.58), Offset(w * 0.32, h * 0.93), paint);
    canvas.drawLine(Offset(w * 0.66, h * 0.58), Offset(w * 0.68, h * 0.93), paint);
    final hint = TextPainter(
      text: TextSpan(
        text: 'Sejajarkan bahu dengan garis',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    hint.paint(canvas, Offset((w - hint.width) / 2, h * 0.02));
  }

  @override
  bool shouldRepaint(covariant _BodyGuidePainter oldDelegate) => false;
}
