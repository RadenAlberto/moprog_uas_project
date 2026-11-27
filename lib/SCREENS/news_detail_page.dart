import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/news_model.dart';
import '../PROVIDERS/app_state.dart';
import '../UTILS/formatters.dart';
import '../WIDGETS/app_network_image.dart';
import '../WIDGETS/news_widgets.dart';
import '../WIDGETS/section_header.dart';
import 'vouchers_page.dart';

/// Detail berita. Membuka halaman ini menandai berita sebagai sudah dibaca.
class NewsDetailPage extends StatefulWidget {
  const NewsDetailPage({super.key, required this.newsId});

  final String newsId;

  @override
  State<NewsDetailPage> createState() => _NewsDetailPageState();
}

class _NewsDetailPageState extends State<NewsDetailPage> {
  @override
  void initState() {
    super.initState();
    // notifyListeners tidak boleh dipanggil saat build, jadi tunggu frame pertama.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().markNewsRead(widget.newsId);
    });
  }

  void _runAction(NewsItem item) {
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);

    switch (item.action) {
      case NewsAction.catalog:
        navigator.popUntil((route) => route.isFirst);
        appState.setTab(1);
        break;
      case NewsAction.membership:
        navigator.popUntil((route) => route.isFirst);
        appState.setTab(4);
        break;
      case NewsAction.vouchers:
        navigator.push(
          MaterialPageRoute(builder: (_) => const VouchersPage()),
        );
        break;
      case NewsAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final item = appState.newsById(widget.newsId);

    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Berita tidak ditemukan.')),
      );
    }

    final related = appState.news
        .where((n) => n.id != item.id && n.category == item.category)
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: AppNetworkImage(item.image),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            NewsCategoryChip(category: item.category),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${formatDateLong(item.date)}  |  ${item.readMinutes} menit baca',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.summary,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                            height: 1.4,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const Divider(height: 28),
                        for (final paragraph in item.paragraphs)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(
                              paragraph,
                              style: const TextStyle(fontSize: 14.5, height: 1.6),
                            ),
                          ),
                        if (item.action != NewsAction.none) ...[
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEC1C24),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => _runAction(item),
                              child: Text(
                                (item.actionLabel ?? 'Lihat').toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const SectionHeader(title: 'Berita Terkait'),
                    const SizedBox(height: 8),
                    NewsCarousel(items: related),
                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
