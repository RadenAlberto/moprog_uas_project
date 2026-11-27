import 'package:flutter/material.dart';

import '../MODELS/product_model.dart';

/// Mengubah JSON dari server menjadi [Product]. Mengembalikan `null` bila
/// data tidak lengkap sehingga satu produk rusak tidak menjatuhkan katalog.
Product? productFromJson(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final name = raw['name'];
  final price = raw['price'];
  final category = raw['category'];
  final audience = raw['audience'];
  if (id is! String || id.isEmpty) return null;
  if (name is! String || name.isEmpty) return null;
  if (price is! num || price <= 0) return null;
  if (category is! String || category.isEmpty) return null;
  if (audience is! String || audience.isEmpty) return null;

  List<String> strings(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String && item.isNotEmpty) item,
    ];
  }

  final sizes = strings(raw['sizes']);
  final colors = <Color>[];
  final rawColors = raw['colors'];
  if (rawColors is List) {
    for (final item in rawColors) {
      if (item is num) colors.add(Color(item.toInt()));
    }
  }
  if (sizes.isEmpty || colors.isEmpty) return null;

  final gallery = <GalleryImage>[];
  final rawGallery = raw['gallery'];
  if (rawGallery is List) {
    for (final item in rawGallery) {
      if (item is Map && item['url'] is String && (item['url'] as String).isNotEmpty) {
        gallery.add(GalleryImage(
          item['url'] as String,
          item['color'] is String ? item['color'] as String : '',
        ));
      }
    }
  }

  // Daftar paralel (nama, kode, foto) hanya dipakai bila panjangnya sama
  // dengan daftar warna; bila tidak, diabaikan agar tidak salah pasang.
  List<String> parallel(String key) {
    final list = strings(raw[key]);
    return list.length == colors.length ? list : const [];
  }

  final ratingAverage = raw['rating_average'];
  final ratingCount = raw['rating_count'];

  final original = raw['original_price'];
  return Product(
    id: id,
    name: name,
    price: price.toDouble(),
    originalPrice: original is num ? original.toDouble() : null,
    image: raw['image'] is String ? raw['image'] as String : '',
    category: category,
    audience: audience,
    description: raw['description'] is String ? raw['description'] as String : '',
    features: strings(raw['features']),
    isNew: raw['is_new'] == true,
    availableSizes: sizes,
    availableColors: colors,
    colorCodes: parallel('color_codes'),
    colorNames: parallel('color_names'),
    colorImages: parallel('color_images'),
    gallery: gallery,
    ratingAverage: ratingAverage is num ? ratingAverage.toDouble() : 0,
    ratingCount: ratingCount is num ? ratingCount.toInt() : 0,
    url: raw['url'] is String ? raw['url'] as String : '',
  );
}

/// Popularitas 0..1 dari JSON produk server (0.0 bila tidak ada).
double? popularityFromJson(Object? raw) {
  if (raw is! Map) return null;
  final value = raw['popularity'];
  if (value is! num) return null;
  return value.toDouble().clamp(0.0, 1.0).toDouble();
}
