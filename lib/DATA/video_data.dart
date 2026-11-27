import 'package:flutter/material.dart';

import '../MODELS/video_model.dart';

/// Daftar video. Untuk memakai video tertentu, isi `youtubeId`
/// (bagian setelah `v=` pada URL YouTube) agar thumbnail asli tampil.
const List<VideoItem> kVideos = [
  VideoItem(
    id: 'v1',
    title: 'LifeWear: pakaian sederhana untuk semua',
    subtitle: 'Filosofi UNIQLO tentang pakaian yang dibuat lebih baik setiap hari.',
    topic: 'Brand',
    searchQuery: 'UNIQLO LifeWear official',
    gradient: [Color(0xFFEC1C24), Color(0xFF8E0F14)],
    icon: Icons.favorite_outline,
  ),
  VideoItem(
    id: 'v2',
    title: 'HEATTECH: hangat tanpa tebal',
    subtitle: 'Cara kerja teknologi serat yang mengubah uap tubuh menjadi panas.',
    topic: 'Teknologi',
    searchQuery: 'UNIQLO HEATTECH how it works',
    gradient: [Color(0xFFEF6C00), Color(0xFFB23C00)],
    icon: Icons.whatshot_outlined,
  ),
  VideoItem(
    id: 'v3',
    title: 'AIRism: sejuk dan nyaman seharian',
    subtitle: 'Kain halus yang cepat kering dan menyerap keringat.',
    topic: 'Teknologi',
    searchQuery: 'UNIQLO AIRism official',
    gradient: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
    icon: Icons.air,
  ),
  VideoItem(
    id: 'v4',
    title: 'UT: kaos grafis dari seluruh dunia',
    subtitle: 'Koleksi UT hasil kolaborasi seniman, musik, dan budaya pop.',
    topic: 'Koleksi',
    searchQuery: 'UNIQLO UT collection',
    gradient: [Color(0xFF6A4FA3), Color(0xFF311B6B)],
    icon: Icons.palette_outlined,
  ),
  VideoItem(
    id: 'v5',
    title: 'Ultra Light Down: ringan dan hangat',
    subtitle: 'Jaket bulu angsa ringkas yang bisa dilipat ke dalam kantong.',
    topic: 'Produk',
    searchQuery: 'UNIQLO Ultra Light Down jacket',
    gradient: [Color(0xFF455A64), Color(0xFF1C2A30)],
    icon: Icons.ac_unit,
  ),
  VideoItem(
    id: 'v6',
    title: 'Cara memilih ukuran yang pas',
    subtitle: 'Tips mengukur badan dan membaca tabel ukuran UNIQLO.',
    topic: 'Panduan',
    searchQuery: 'UNIQLO size guide how to measure',
    gradient: [Color(0xFF00897B), Color(0xFF004D40)],
    icon: Icons.straighten,
  ),
  VideoItem(
    id: 'v7',
    title: 'Tren gaya dan koleksi terbaru',
    subtitle: 'Inspirasi padu padan LifeWear musim ini.',
    topic: 'Gaya',
    searchQuery: 'UNIQLO style collection new arrivals',
    gradient: [Color(0xFFC2185B), Color(0xFF7B0F3A)],
    icon: Icons.checkroom_outlined,
  ),
  VideoItem(
    id: 'v8',
    title: 'Kisah di balik kain: inovasi UNIQLO',
    subtitle: 'Riset bahan dan teknologi pembuatan pakaian harian.',
    topic: 'Brand',
    searchQuery: 'UNIQLO innovation fabric documentary',
    gradient: [Color(0xFF37474F), Color(0xFF111A1E)],
    icon: Icons.science_outlined,
  ),
];
