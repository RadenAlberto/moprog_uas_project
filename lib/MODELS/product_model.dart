import 'package:flutter/material.dart';

import '../UTILS/formatters.dart';

/// Produk katalog.
///
/// [price] adalah harga yang dibayar saat ini. Bila [originalPrice] diisi dan
/// lebih besar dari [price], produk dianggap sedang diskon (tampil di
/// Flash Sale dan diberi label persen).
class Product {
  final String id;
  final String name;
  final double price;

  /// Harga sebelum diskon (opsional).
  final double? originalPrice;

  /// URL foto. Kosong = pakai ilustrasi pakaian yang digambar dengan kode.
  final String image;
  final String category;
  final String audience;
  final String description;

  /// Label teknologi/bahan, contoh: `AIRism`, `HEATTECH`.
  final List<String> features;
  final bool isNew;
  final List<String> availableSizes;
  final List<Color> availableColors;

  /// Kode warna Uniqlo (mis. `69`), sejajar dengan [availableColors].
  final List<String> colorCodes;

  /// Nama tiap warna (sejajar dengan [availableColors]), contoh `Biru Navy`.
  final List<String> colorNames;

  /// Foto produk untuk tiap warna (sejajar dengan [availableColors]).
  final List<String> colorImages;

  /// Foto tambahan (tampak belakang, detail, dll). `color` kosong = berlaku
  /// untuk semua warna.
  final List<GalleryImage> gallery;

  /// Rating resmi dari katalog Uniqlo (0 bila belum ada ulasan).
  final double ratingAverage;
  final int ratingCount;

  /// Alamat halaman produk di situs Uniqlo.
  final String url;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.originalPrice,
    required this.image,
    required this.category,
    required this.audience,
    required this.description,
    this.features = const [],
    this.isNew = false,
    required this.availableSizes,
    required this.availableColors,
    this.colorCodes = const [],
    this.colorNames = const [],
    this.colorImages = const [],
    this.gallery = const [],
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.url = '',
  });

  int _colorIndex(Color color) {
    final value = color.toARGB32();
    for (var i = 0; i < availableColors.length; i++) {
      if (availableColors[i].toARGB32() == value) return i;
    }
    return -1;
  }

  /// Foto produk untuk warna [color]; bila tidak ada, foto utama.
  String imageFor(Color? color) {
    if (color == null) return image;
    final i = _colorIndex(color);
    if (i >= 0 && i < colorImages.length && colorImages[i].isNotEmpty) {
      return colorImages[i];
    }
    return image;
  }

  /// Nama warna sesuai data produk (null bila tidak diketahui).
  String? colorNameOf(Color color) {
    final i = _colorIndex(color);
    if (i >= 0 && i < colorNames.length) return colorNames[i];
    return null;
  }

  /// Foto galeri untuk warna [color]: foto khusus warna itu + foto umum.
  List<String> galleryFor(Color color) {
    final i = _colorIndex(color);
    final code = i >= 0 && i < colorCodes.length ? colorCodes[i] : '';
    return [
      for (final g in gallery)
        if (g.color.isEmpty || g.color == code) g.url,
    ];
  }

  /// Salinan produk dengan harga/ukuran berbeda. Dipakai Price Tracker untuk
  /// mode demo (simulasi diskon dan stok) tanpa mengubah data asli.
  Product withOverrides({
    double? price,
    double? originalPrice,
    List<String>? availableSizes,
  }) {
    return Product(
      id: id,
      name: name,
      price: price ?? this.price,
      originalPrice: originalPrice ?? this.originalPrice,
      image: image,
      category: category,
      audience: audience,
      description: description,
      features: features,
      isNew: isNew,
      availableSizes: availableSizes ?? this.availableSizes,
      availableColors: availableColors,
      colorCodes: colorCodes,
      colorNames: colorNames,
      colorImages: colorImages,
      gallery: gallery,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      url: url,
    );
  }

  bool get isOnSale => originalPrice != null && originalPrice! > price;

  /// Persentase diskon dibulatkan (0 bila tidak diskon).
  int get discountPercent {
    if (!isOnSale) return 0;
    return ((1 - price / originalPrice!) * 100).round();
  }

  String get formattedPrice => formatRupiah(price);

  String get formattedOriginalPrice =>
      originalPrice == null ? '' : formatRupiah(originalPrice!);
}

/// Foto tambahan produk.
class GalleryImage {
  const GalleryImage(this.url, [this.color = '']);

  final String url;

  /// Kode warna Uniqlo; kosong bila berlaku untuk semua warna.
  final String color;
}

/// Satu baris di keranjang belanja.
class CartItem {
  final Product product;
  final String selectedSize;
  final Color selectedColor;

  int quantity;
  bool isChecked;

  CartItem({
    required this.product,
    required this.selectedSize,
    required this.selectedColor,
    this.quantity = 1,
    this.isChecked = true,
  });

  double get lineTotal => product.price * quantity;
}
