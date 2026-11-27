/// Sisa waktu hingga tengah malam (promo kilat berakhir tiap hari pukul 00.00).
Duration timeUntilMidnight(DateTime now) {
  final midnight = DateTime(now.year, now.month, now.day + 1);
  return midnight.difference(now);
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

/// Sapaan sesuai jam, contoh: "Selamat pagi".
String greetingFor(DateTime now) {
  final h = now.hour;
  if (h < 11) return 'Selamat pagi';
  if (h < 15) return 'Selamat siang';
  if (h < 18) return 'Selamat sore';
  return 'Selamat malam';
}
