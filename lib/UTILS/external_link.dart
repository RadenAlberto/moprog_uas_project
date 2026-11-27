import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'toast.dart';

/// Membuka tautan di aplikasi luar (YouTube, peta, browser). Bila gagal,
/// tautan disalin ke clipboard agar pengguna tetap bisa membukanya.
Future<void> openExternalUrl(BuildContext context, String url) async {
  try {
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (opened) return;
  } catch (_) {
    // Jatuh ke penyalinan tautan di bawah.
  }

  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  showAppToast(
    context,
    'Tidak bisa membuka tautan. Alamatnya disalin ke clipboard.',
    icon: Icons.link,
  );
}
