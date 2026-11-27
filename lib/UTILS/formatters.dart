import 'package:flutter/material.dart';

/// Format angka menjadi Rupiah, contoh: 1234567 -> "Rp 1.234.567".
String formatRupiah(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (Match m) => '${m[1]}.',
  );
  return '${negative ? '-' : ''}Rp $grouped';
}

const List<String> _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

const List<String> _monthLong = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Contoh: "15 Okt 2026".
String formatDate(DateTime d) => '${d.day} ${_monthShort[d.month - 1]} ${d.year}';

/// Contoh: "15 Oktober 2026".
String formatDateLong(DateTime d) =>
    '${d.day} ${_monthLong[d.month - 1]} ${d.year}';

/// Contoh: "09:05".
String formatTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// Contoh: "15 Okt 2026, 09:05".
String formatDateTime(DateTime d) => '${formatDate(d)}, ${formatTime(d)}';

/// Waktu relatif, contoh: "3 jam lalu".
String timeAgo(DateTime d, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(d);
  if (diff.inMinutes < 1) return 'Baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  return formatDate(d);
}

final Map<int, String> _colorNames = <int, String>{
  Colors.white.toARGB32(): 'Putih',
  Colors.black.toARGB32(): 'Hitam',
  Colors.grey.toARGB32(): 'Abu-abu',
  Colors.blueGrey.toARGB32(): 'Biru Keabuan',
  Colors.blue.toARGB32(): 'Biru',
  Colors.indigo.toARGB32(): 'Indigo',
  Colors.brown.toARGB32(): 'Cokelat',
  Colors.pink.toARGB32(): 'Merah Muda',
  Colors.red.toARGB32(): 'Merah',
  Colors.green.toARGB32(): 'Hijau',
  Colors.yellow.toARGB32(): 'Kuning',
  Colors.purple.toARGB32(): 'Ungu',
  Colors.teal.toARGB32(): 'Tosca',
  Colors.orange.toARGB32(): 'Oranye',
  Colors.lightBlue.toARGB32(): 'Biru Muda',
};

/// Nama warna dalam Bahasa Indonesia untuk warna produk.
String colorLabel(Color color) => _colorNames[color.toARGB32()] ?? 'Warna Lain';

/// Rupiah ringkas untuk kartu statistik, contoh: "Rp 2,66 jt", "Rp 450 rb".
String formatRupiahCompact(num value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    final text = millions.toStringAsFixed(millions >= 10 ? 0 : 2);
    return 'Rp ${text.replaceAll('.', ',')} jt';
  }
  if (value >= 1000) {
    return 'Rp ${(value / 1000).toStringAsFixed(0)} rb';
  }
  return formatRupiah(value);
}
