import 'package:flutter/material.dart';

/// Video produk/kampanye. Tombol tonton membuka YouTube.
///
/// Jika [youtubeId] diisi, kartu menampilkan thumbnail asli YouTube dan
/// membuka `watch?v=ID`. Jika kosong, kartu membuka hasil pencarian YouTube
/// untuk [searchQuery] (selalu valid).
class VideoItem {
  final String id;
  final String title;
  final String subtitle;
  final String topic;
  final String searchQuery;
  final String youtubeId;
  final List<Color> gradient;
  final IconData icon;

  const VideoItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.topic,
    required this.searchQuery,
    this.youtubeId = '',
    required this.gradient,
    required this.icon,
  });

  bool get hasThumbnail => youtubeId.isNotEmpty;

  String get thumbnailUrl => 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';

  String get url => hasThumbnail
      ? 'https://www.youtube.com/watch?v=$youtubeId'
      : 'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(searchQuery)}';
}
