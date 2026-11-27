import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../SERVICES/color_utils.dart';
import '../SERVICES/photo_store.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';
import '../SCREENS/detailproduk_uniqlo.dart';
import 'app_network_image.dart';

/// Foto dari [PhotoStore] (lemari digital, OOTD).
class StoredImage extends StatefulWidget {
  const StoredImage(
    this.name, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  });

  final String name;
  final BoxFit fit;
  final double? width;
  final double? height;

  static final Map<String, Uint8List> _cache = {};

  /// Membuang cache untuk satu berkas (setelah dihapus/diubah).
  static void evict(String name) => _cache.remove(name);

  @override
  State<StoredImage> createState() => _StoredImageState();
}

class _StoredImageState extends State<StoredImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StoredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final name = widget.name;
    final cached = StoredImage._cache[name];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    final store = context.read<PhotoStore>();
    final bytes = await store.read(name);
    if (!mounted || name != widget.name) return;
    setState(() {
      if (bytes == null) {
        _failed = true;
      } else {
        StoredImage._cache[name] = bytes;
        _bytes = bytes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _placeholder(Icons.broken_image_outlined),
      );
    }
    if (_failed) return _placeholder(Icons.image_not_supported_outlined);
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _placeholder(IconData icon) => Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.grey.shade400),
      );
}

/// Lingkaran warna kecil.
class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 14});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }
}

/// Kartu produk kecil: foto sesuai warna, nama, harga. Ketuk membuka detail.
class MiniProductTile extends StatelessWidget {
  const MiniProductTile({
    super.key,
    required this.product,
    this.color,
    this.caption,
    this.width = 140,
    this.onTap,
  });

  final Product product;

  /// Warna yang ditampilkan (foto dan titik warna). `null` = foto utama.
  final Color? color;
  final String? caption;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = color;
    final colorName = c == null ? null : (product.colorNameOf(c) ?? colorNameId(c));
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ?? () => pushPage(context, ProductDetailPage(product: product)),
        child: Container(
          decoration: cardDecoration(radius: 12, border: true, shadow: false),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 3 / 4,
                child: AppNetworkImage(
                  product.imageFor(c),
                  fit: BoxFit.cover,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.formattedPrice,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: product.isOnSale ? AppColors.red : AppColors.ink,
                      ),
                    ),
                    if (colorName != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          ColorDot(c!, size: 10),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              colorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (caption != null && caption!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        caption!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.muted,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Judul bagian dalam halaman Studio.
class StudioSectionTitle extends StatelessWidget {
  const StudioSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Garis perkembangan harga sederhana.
class PriceSparkline extends StatelessWidget {
  const PriceSparkline({super.key, required this.values, this.height = 36});

  final List<double> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _SparklinePainter(values)),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      final y = size.height / 2;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = AppColors.line
          ..strokeWidth = 2,
      );
      return;
    }
    var lo = values.first;
    var hi = values.first;
    for (final v in values) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = (hi - lo) == 0 ? 1.0 : (hi - lo);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - lo) / range) * (size.height - 6) - 3;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final falling = values.last < values.first;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = falling ? AppColors.success : AppColors.red,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values.length != values.length ||
      (values.isNotEmpty && old.values.isNotEmpty && old.values.last != values.last);
}

/// Dialog pencarian produk katalog; mengembalikan produk yang dipilih.
Future<Product?> pickCatalogProduct(
  BuildContext context,
  List<Product> catalog, {
  String title = 'Pilih produk',
  bool Function(Product)? filter,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _ProductPickerSheet(
      title: title,
      catalog: filter == null ? catalog : catalog.where(filter).toList(),
    ),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.title, required this.catalog});

  final String title;
  final List<Product> catalog;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? widget.catalog.take(40).toList()
        : widget.catalog
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                p.category.toLowerCase().contains(q))
            .take(60)
            .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Cari nama produk atau kategori',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('Produk tidak ditemukan'))
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = results[i];
                        return ListTile(
                          leading: SizedBox(
                            width: 44,
                            height: 56,
                            child: AppNetworkImage(
                              p.image,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          title: Text(
                            p.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text('${p.category} • ${p.formattedPrice}'),
                          onTap: () => Navigator.of(context).pop(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
