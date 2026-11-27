import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_uts/DATA/product_data.dart';

/// Memastikan katalog Uniqlo (assets/data/products.json) termuat utuh dan foto,
/// warna, ukuran, serta harga cocok dengan data aslinya.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadProductCatalog();
  });

  test('1.376 produk Uniqlo termuat, tiap produk punya foto per warna', () {
    expect(kProducts.length, 1376);
    for (final p in kProducts) {
      expect(p.availableSizes, isNotEmpty, reason: p.id);
      expect(p.colorImages.length, p.availableColors.length, reason: p.id);
      expect(p.colorNames.length, p.availableColors.length, reason: p.id);
      expect(p.colorImages.every((u) => u.startsWith('https://')), isTrue,
          reason: p.id);
      // Warna harus unik agar warna terpilih bisa dikenali lewat ARGB.
      final values = p.availableColors.map((c) => c.toARGB32()).toSet();
      expect(values.length, p.availableColors.length, reason: p.id);
    }
  });

  test('Celana Capri Denim Crop: warna, foto, ukuran, harga sesuai Uniqlo', () {
    final p = findProduct('E495975-000')!;
    expect(p.name, 'Celana Capri Denim Crop');
    expect(p.price, 599000);
    expect(p.isOnSale, isFalse);
    expect(p.colorNames, ['Biru Navy', 'Hitam']);
    expect(p.availableSizes.first, '23inch');
    expect(p.availableSizes.length, 8);

    final navy = p.availableColors[0];
    final black = p.availableColors[1];
    expect(p.imageFor(navy), contains('idgoods_69_495975'));
    expect(p.imageFor(black), contains('idgoods_09_495975'));
    expect(p.colorNameOf(black), 'Hitam');
    expect(p.imageFor(Colors.pink), p.image, reason: 'warna asing -> foto utama');
  });

  test('Produk promo: harga turun dari harga normal', () {
    final sale = kProducts.where((p) => p.isOnSale).toList();
    expect(sale, isNotEmpty);
    for (final p in sale) {
      expect(p.price, lessThan(p.originalPrice!), reason: p.id);
      expect(p.discountPercent, greaterThan(0), reason: p.id);
    }
  });
}
