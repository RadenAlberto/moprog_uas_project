import 'package:flutter/material.dart';

import '../DATA/product_data.dart';
import '../MODELS/order_model.dart';
import '../MODELS/product_model.dart';
import 'app_network_image.dart';
import 'garment_illustration.dart';

/// Gambar produk: foto dari internet bila ada, selain itu ilustrasi pakaian.
class ProductImage extends StatelessWidget {
  const ProductImage(
    this.product, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.color,
  });

  final Product product;

  /// Warna terpilih: foto yang tampil adalah foto produk dalam warna ini.
  final Color? color;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final illustration = GarmentIllustration(product: product);

    final url = product.imageFor(color);
    Widget child = url.isEmpty
        ? illustration
        : AppNetworkImage(url, fit: fit, fallback: illustration);

    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return SizedBox(width: width, height: height, child: child);
  }
}

/// Gambar item pesanan: mencari produk aslinya agar ilustrasi tetap muncul.
class OrderItemImage extends StatelessWidget {
  const OrderItemImage(
    this.item, {
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  final OrderItem item;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final product = findProduct(item.productId);
    if (product != null) {
      return ProductImage(
        product,
        color: item.color,
        width: width,
        height: height,
        borderRadius: borderRadius,
      );
    }
    return AppNetworkImage(
      item.image,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}
