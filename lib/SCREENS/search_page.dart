import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../PROVIDERS/app_state.dart';
import '../UTILS/app_theme.dart';
import '../WIDGETS/product_card.dart';
import '../WIDGETS/ui_kit.dart';

const List<String> _trending = [
  'AIRism',
  'HEATTECH',
  'Jeans',
  'Hoodie',
  'Dress',
  'Kids',
  'Jaket',
  'Kaos UT',
];

/// Pencarian produk: riwayat pencarian, kata kunci populer, dan hasil langsung.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _query = widget.initialQuery;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value, {bool remember = false}) {
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() => _query = value);
    if (remember) context.read<AppState>().addRecentSearch(value);
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final results = appState.searchProducts(_query);
    final hasQuery = _query.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        centerTitle: false,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (value) => setState(() => _query = value),
          onSubmitted: (value) => appState.addRecentSearch(value),
          decoration: InputDecoration(
            hintText: 'Cari AIRism, HEATTECH, kemeja...',
            hintStyle: const TextStyle(fontSize: 14, color: Colors.grey),
            border: InputBorder.none,
            suffixIcon: hasQuery
                ? IconButton(
                    tooltip: 'Hapus',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _setQuery(''),
                  )
                : null,
          ),
        ),
      ),
      body: SafeArea(
        child: hasQuery
            ? _buildResults(results)
            : _buildSuggestions(appState),
      ),
    );
  }

  Widget _buildResults(List<Product> results) {
    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Produk tidak ditemukan',
        message: 'Coba kata kunci lain, misalnya nama produk atau kategori.',
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                '${results.length} produk ditemukan',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const ProductGridDelegate(),
                itemCount: results.length,
                itemBuilder: (context, index) => Listener(
                  onPointerUp: (_) =>
                      context.read<AppState>().addRecentSearch(_query),
                  child: ProductCard(product: results[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestions(AppState appState) {
    final recent = appState.recentSearches;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pencarian Terakhir',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: appState.clearRecentSearches,
                child: const Text(
                  'Hapus semua',
                  style: TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final text in recent)
                InputChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: Text(text),
                  backgroundColor: Colors.white,
                  onPressed: () => _setQuery(text, remember: true),
                  onDeleted: () => appState.removeRecentSearch(text),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        const Text(
          'Sedang Tren',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final text in _trending)
              ActionChip(
                avatar: const Icon(
                  Icons.trending_up,
                  size: 16,
                  color: AppColors.red,
                ),
                label: Text(text),
                backgroundColor: Colors.white,
                onPressed: () => _setQuery(text, remember: true),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          'Jelajahi Kategori',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in const [
              'Men',
              'Women',
              'Kids',
              'Baby',
              'Outerwear',
              'Innerwear',
              'Accessories',
            ])
              ActionChip(
                label: Text(category),
                backgroundColor: AppColors.redSoft,
                side: BorderSide.none,
                onPressed: () {
                  appState.showCategory(category);
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
          ],
        ),
      ],
    );
  }
}
