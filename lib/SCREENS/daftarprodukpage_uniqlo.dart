import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../PROVIDERS/app_state.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';
import '../WIDGETS/product_card.dart';
import '../WIDGETS/ui_kit.dart';
import 'search_page.dart';

const List<String> _filters = [
  'Semua',
  'Men',
  'Women',
  'Kids',
  'Baby',
  'Unisex',
  'AIRism',
  'HEATTECH',
  'T-Shirts',
  'Shirts',
  'Outerwear',
  'Pants',
  'Jeans',
  'Shorts',
  'Skirts',
  'Dresses',
  'Sweatshirts',
  'Knitwear',
  'Innerwear',
  'Loungewear',
  'Accessories',
];

enum _Sort { recommended, cheapest, priciest, biggestDiscount }

extension on _Sort {
  String get label {
    switch (this) {
      case _Sort.recommended:
        return 'Rekomendasi';
      case _Sort.cheapest:
        return 'Harga terendah';
      case _Sort.priciest:
        return 'Harga tertinggi';
      case _Sort.biggestDiscount:
        return 'Diskon terbesar';
    }
  }
}

/// Katalog produk dengan filter kategori dan pengurutan.
class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  _Sort _sort = _Sort.recommended;
  final GlobalKey _selectedChipKey = GlobalKey();
  String? _lastCategory;

  List<Product> _sorted(List<Product> source) {
    final list = List<Product>.of(source);
    switch (_sort) {
      case _Sort.recommended:
        break;
      case _Sort.cheapest:
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case _Sort.priciest:
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case _Sort.biggestDiscount:
        list.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
        break;
    }
    return list;
  }

  /// Menggulirkan chip kategori aktif ke area terlihat (mis. saat dibuka dari
  /// kategori di Beranda).
  void _revealSelectedChip(String category) {
    if (_lastCategory == category) return;
    _lastCategory = category;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _selectedChipKey.currentContext;
      if (!mounted || chipContext == null) return;
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.3,
        duration: const Duration(milliseconds: 250),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final category = appState.catalogCategory;
    final products = _sorted(appState.catalogProducts(category));
    _revealSelectedChip(category);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(category.toUpperCase()),
        actions: [
          IconButton(
            tooltip: 'Cari produk',
            icon: const Icon(Icons.search),
            onPressed: () => pushPage(context, const SearchPage()),
          ),
          PopupMenuButton<_Sort>(
            tooltip: 'Urutkan',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              for (final sort in _Sort.values)
                PopupMenuItem<_Sort>(value: sort, child: Text(sort.label)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              height: 52,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    for (final filter in _filters)
                      Padding(
                        key: filter == category ? _selectedChipKey : null,
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: filter == category,
                          selectedColor: AppColors.red,
                          backgroundColor: const Color(0xFFF2F2F2),
                          labelStyle: TextStyle(
                            color: filter == category
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: filter == category
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          side: BorderSide.none,
                          showCheckmark: false,
                          onSelected: (_) =>
                              appState.setCatalogCategory(filter),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${products.length} produk  |  ${_sort.label}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: 'Belum ada produk',
                      message: 'Tidak ada produk pada kategori ini.',
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const ProductGridDelegate(),
                          itemCount: products.length,
                          itemBuilder: (context, index) =>
                              ProductCard(product: products[index]),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
