import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // SliverConstraints, SliverGridLayout
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../PROVIDERS/app_state.dart';
import '../SCREENS/detailproduk_uniqlo.dart';
import '../UTILS/app_theme.dart';
import 'product_image.dart';
import 'ui_kit.dart';

/// Foto produk Uniqlo berukuran 3:4 (lebar:tinggi). Semua bingkai foto produk
/// memakai rasio ini supaya foto tampil utuh, tidak terpotong, dan seragam.
const double kProductPhotoAspect = 3 / 4;

/// Tinggi area teks kartu (nama, rating, harga, titik warna).
const double kProductInfoExtent = 132;

/// Tinggi kartu produk untuk lebar [width]: foto 3:4 + area teks.
double productCardHeight(double width, {double info = kProductInfoExtent}) =>
    width / kProductPhotoAspect + info;

/// Grid yang tinggi barisnya mengikuti lebar kartu, jadi foto 3:4 selalu muat
/// utuh di semua ukuran layar. Pengganti `SliverGridDelegateWithMaxCrossAxisExtent`
/// + `childAspectRatio` tetap.
class ProductGridDelegate extends SliverGridDelegate {
  const ProductGridDelegate({
    this.maxCrossAxisExtent = 210,
    this.crossAxisSpacing = 12,
    this.mainAxisSpacing = 14,
    this.infoExtent = kProductInfoExtent,
  });

  final double maxCrossAxisExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double infoExtent;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final count = math.max(
      1,
      (constraints.crossAxisExtent / (maxCrossAxisExtent + crossAxisSpacing))
          .ceil(),
    );
    final usable = math.max(
      0.0,
      constraints.crossAxisExtent - crossAxisSpacing * (count - 1),
    );
    final cardWidth = usable / count;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: count,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      mainAxisExtent: productCardHeight(cardWidth, info: infoExtent),
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(covariant ProductGridDelegate oldDelegate) =>
      oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing ||
      oldDelegate.infoExtent != infoExtent;
}

/// Kartu produk yang dipakai di Beranda, Katalog, Wishlist, dan daftar horizontal.
///
/// Foto selalu berbingkai 3:4 (utuh, tanpa terpotong); sisa tinggi kartu
/// dipakai area teks. Pemanggil harus memberi tinggi kartu sekitar
/// [productCardHeight] (lihat [ProductGridDelegate]).
class ProductCard extends StatelessWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.footer,
    this.rank,
  });

  final Product product;

  /// Widget tambahan di bawah harga (mis. tombol "+ Keranjang").
  final Widget? footer;

  /// Nomor peringkat (untuk daftar "Terlaris").
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final isLiked =
        context.select<AppState, bool>((state) => state.isWishlisted(product));
    final rating = context.select<AppState, (double, int)>(
      (state) => state.ratingOf(product).record,
    );

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProductDetailPage(product: product),
          ),
        );
      },
      child: Container(
        decoration: cardDecoration(radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: kProductPhotoAspect,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImage(
                    product,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (product.isOnSale)
                          PillTag(label: '-${product.discountPercent}%'),
                        if (product.isNew)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: PillTag(
                              label: 'BARU',
                              color: AppColors.ink,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => context
                          .read<AppState>()
                          .toggleWishlist(product, context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.soft,
                        ),
                        child: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? AppColors.red : Colors.black87,
                          size: 17,
                        ),
                      ),
                    ),
                  ),
                  if (rank != null)
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: const BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(10),
                          ),
                        ),
                        child: Text(
                          '#$rank',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
              padding: EdgeInsets.fromLTRB(10, 10, 10, footer == null ? 10 : 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 13, color: AppColors.star),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          '${rating.$1.toStringAsFixed(1)} (${rating.$2})',
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
                  const SizedBox(height: 4),
                  // Selalu menyisakan satu baris agar tinggi kartu seragam.
                  SizedBox(
                    height: 13,
                    child: product.isOnSale
                        ? Text(
                            product.formattedOriginalPrice,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: AppColors.muted,
                              decoration: TextDecoration.lineThrough,
                            ),
                          )
                        : null,
                  ),
                  Text(
                    product.formattedPrice,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.red,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _ColorDots(colors: product.availableColors),
                ],
              ),
                ),
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorDots extends StatelessWidget {
  const _ColorDots({required this.colors});

  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    final shown = colors.take(4).toList();
    final extra = colors.length - shown.length;
    return SizedBox(
      height: 12,
      child: Row(
        children: [
          for (final color in shown)
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26, width: 0.6),
              ),
            ),
          if (extra > 0)
            Text(
              '+$extra',
              style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
            ),
        ],
      ),
    );
  }
}

/// Daftar produk horizontal (Flash Sale, Terakhir Dilihat, Produk Serupa).
class HorizontalProductList extends StatelessWidget {
  const HorizontalProductList({
    super.key,
    required this.products,
    this.itemWidth = 160,
    this.height,
    this.showRank = false,
  });

  final List<Product> products;
  final double itemWidth;

  /// Tinggi daftar; bila kosong dihitung dari lebar kartu (foto 3:4 + teks).
  final double? height;
  final bool showRank;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height ?? productCardHeight(itemWidth) + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: products.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: itemWidth,
            child: ProductCard(
              product: products[index],
              rank: showRank ? index + 1 : null,
            ),
          );
        },
      ),
    );
  }
}
