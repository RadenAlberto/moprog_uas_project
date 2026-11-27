import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/news_model.dart';
import '../PROVIDERS/app_state.dart';
import '../SCREENS/news_detail_page.dart';
import '../UTILS/formatters.dart';
import 'app_network_image.dart';

void openNews(BuildContext context, NewsItem item) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => NewsDetailPage(newsId: item.id)),
  );
}

/// Label kategori berwarna.
class NewsCategoryChip extends StatelessWidget {
  const NewsCategoryChip({super.key, required this.category});

  final NewsCategory category;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 12, color: category.color),
          const SizedBox(width: 4),
          Text(
            category.label.toUpperCase(),
            style: TextStyle(
              color: category.color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu berita ringkas untuk daftar horizontal di Home.
class NewsCompactCard extends StatelessWidget {
  const NewsCompactCard({super.key, required this.item, this.width = 250});

  final NewsItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isRead =
        context.select<AppState, bool>((state) => state.isNewsRead(item.id));

    return GestureDetector(
      onTap: () => openNews(context, item),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 120,
                  width: double.infinity,
                  child: AppNetworkImage(
                    item.image,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(10)),
                  ),
                ),
                if (!isRead)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC1C24),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NewsCategoryChip(category: item.category),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatDate(item.date),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Daftar horizontal berita untuk Home.
class NewsCarousel extends StatelessWidget {
  const NewsCarousel({super.key, required this.items});

  final List<NewsItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 245,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => NewsCompactCard(item: items[index]),
      ),
    );
  }
}

/// Kartu berita lebar untuk halaman daftar berita.
class NewsListCard extends StatelessWidget {
  const NewsListCard({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context) {
    final isRead =
        context.select<AppState, bool>((state) => state.isNewsRead(item.id));

    return GestureDetector(
      onTap: () => openNews(context, item),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(
                    item.image,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  if (item.isPinned)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.push_pin, size: 11, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'UTAMA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      NewsCategoryChip(category: item.category),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          formatDate(item.date),
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEC1C24),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'BARU',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
