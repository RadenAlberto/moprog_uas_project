import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/news_model.dart';
import '../PROVIDERS/app_state.dart';
import '../WIDGETS/news_widgets.dart';

/// Daftar berita & info dengan pencarian dan filter kategori.
class NewsListPage extends StatefulWidget {
  const NewsListPage({super.key});

  @override
  State<NewsListPage> createState() => _NewsListPageState();
}

class _NewsListPageState extends State<NewsListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  NewsCategory? _category;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final query = _query.trim().toLowerCase();

    final items = appState.news.where((item) {
      if (_category != null && item.category != _category) return false;
      if (query.isEmpty) return true;
      return item.title.toLowerCase().contains(query) ||
          item.summary.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'BERITA & INFO',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Tandai semua sudah dibaca',
            icon: const Icon(Icons.done_all),
            onPressed: appState.unreadNewsCount == 0
                ? null
                : appState.markAllNewsRead,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Cari berita, promo, atau info',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: Colors.grey),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.black54),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF2F2F2),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _CategoryChip(
                        label: 'Semua',
                        selected: _category == null,
                        onTap: () => setState(() => _category = null),
                      ),
                      for (final category in NewsCategory.values)
                        _CategoryChip(
                          label: category.label,
                          selected: _category == category,
                          onTap: () => setState(() => _category = category),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 56, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              const Text(
                                'Berita tidak ditemukan',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: items.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) =>
                              NewsListCard(item: items[index]),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: const Color(0xFFEC1C24),
        backgroundColor: const Color(0xFFF2F2F2),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide.none,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
