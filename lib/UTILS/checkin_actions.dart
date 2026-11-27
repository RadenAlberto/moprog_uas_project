import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/auth_provider.dart';
import 'auth_gate.dart';
import 'toast.dart';

/// Check-in harian. Tamu diarahkan masuk/daftar dulu; member mendapat poin
/// yang naik bila check-in berturut-turut.
Future<void> performCheckIn(BuildContext context) async {
  final auth = context.read<AuthProvider>();

  if (!auth.isLoggedIn) {
    final ok = await requireMember(
      context,
      message: 'Check-in harian khusus member UNIQLO. Masuk atau gabung member '
          'untuk mengumpulkan poin gratis setiap hari.',
    );
    if (!ok || !context.mounted) return;
  }

  if (!auth.canCheckInToday()) {
    showAppToast(
      context,
      'Anda sudah check-in hari ini. Kembali lagi besok!',
      color: Colors.grey.shade900,
      icon: Icons.event_available,
    );
    return;
  }

  final reward = await auth.checkIn();
  if (!context.mounted) return;

  if (reward == null) return;
  showAppToast(
    context,
    'Check-in berhasil: +$reward poin (hari ke-${auth.currentStreak()})',
    icon: Icons.stars_rounded,
  );
}
