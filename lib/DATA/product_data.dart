import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../MODELS/product_model.dart';
import '../SERVICES/product_json.dart';

/// Lokasi katalog produk bawaan (data resmi Uniqlo Indonesia).
///
/// Berkas ini dibuat oleh `backend/import_uniqlo.py` dari `raw_products.json`
/// dan dipakai juga sebagai seed database server (`backend/products_seed.json`),
/// jadi aplikasi dan server selalu memuat katalog yang sama.
const String kProductAsset = 'assets/data/products.json';

/// Katalog aktif. Kosong sampai [loadProductCatalog] selesai (dipanggil di
/// `main()` sebelum `runApp`). Objek list yang sama dipakai selamanya supaya
/// `AppState` bisa membedakan katalog bawaan dari katalog server.
final List<Product> kProducts = <Product>[];

final Map<String, Product> _kIndex = <String, Product>{};

/// Memuat katalog dari aset. Aman dipanggil berulang (tidak memuat ulang).
/// Produk yang datanya rusak dilewati, bukan menggagalkan seluruh katalog.
Future<void> loadProductCatalog({AssetBundle? bundle}) async {
  if (kProducts.isNotEmpty) return;
  final text = await (bundle ?? rootBundle).loadString(kProductAsset);
  final decoded = jsonDecode(text);
  if (decoded is! List) return;
  for (final raw in decoded) {
    final product = productFromJson(raw);
    if (product != null) {
      kProducts.add(product);
      _kIndex[product.id] = product;
    }
  }
}

/// Mencari produk bawaan berdasarkan id.
Product? findProduct(String id) => _kIndex[id];

/// Nama warna untuk item pesanan/keranjang: nama dari data produk bila ada,
/// selain itu nama umum dari [fallback].
String colorNameFor(String productId, Color color, String Function(Color) fallback) {
  return findProduct(productId)?.colorNameOf(color) ?? fallback(color);
}
