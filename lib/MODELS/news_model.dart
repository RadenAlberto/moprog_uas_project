import 'dart:math' as math;

import 'package:flutter/material.dart';

enum NewsCategory { promo, info, koleksi, event, member }

extension NewsCategoryInfo on NewsCategory {
  String get label {
    switch (this) {
      case NewsCategory.promo:
        return 'Promo';
      case NewsCategory.info:
        return 'Info';
      case NewsCategory.koleksi:
        return 'Koleksi';
      case NewsCategory.event:
        return 'Event';
      case NewsCategory.member:
        return 'Member';
    }
  }

  Color get color {
    switch (this) {
      case NewsCategory.promo:
        return const Color(0xFFEC1C24);
      case NewsCategory.info:
        return const Color(0xFF1565C0);
      case NewsCategory.koleksi:
        return const Color(0xFF2E7D32);
      case NewsCategory.event:
        return const Color(0xFFEF6C00);
      case NewsCategory.member:
        return const Color(0xFF6A4FA3);
    }
  }

  IconData get icon {
    switch (this) {
      case NewsCategory.promo:
        return Icons.local_offer_outlined;
      case NewsCategory.info:
        return Icons.info_outline;
      case NewsCategory.koleksi:
        return Icons.checkroom_outlined;
      case NewsCategory.event:
        return Icons.event_outlined;
      case NewsCategory.member:
        return Icons.card_membership_outlined;
    }
  }
}

/// Tujuan tombol aksi (CTA) pada detail berita.
enum NewsAction { none, catalog, membership, vouchers }

class NewsItem {
  final String id;
  final String title;
  final String summary;

  /// Isi artikel. Pisahkan paragraf dengan baris kosong.
  final String content;
  final String image;
  final NewsCategory category;
  final DateTime date;
  final bool isPinned;
  final NewsAction action;
  final String? actionLabel;

  NewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.image,
    required this.category,
    required this.date,
    this.isPinned = false,
    this.action = NewsAction.none,
    this.actionLabel,
  });

  List<String> get paragraphs => content
      .split('\n\n')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// Perkiraan waktu baca dalam menit.
  int get readMinutes {
    final words = content.split(RegExp(r'\s+')).length;
    return math.max(1, (words / 180).ceil());
  }
}
