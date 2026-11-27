import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/style_provider.dart';
import '../SCREENS/style_advisor_page.dart';
import '../SCREENS/style_result_page.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';

/// Membuka UNIQLO PLUS Stylist: hasil terakhir bila profil sudah ada,
/// bila belum maka memulai analisis baru.
void openStylist(BuildContext context) {
  final hasProfile = context.read<StyleProvider>().hasProfile;
  pushPage<void>(
    context,
    hasProfile ? const StyleResultPage() : const StyleAdvisorPage(),
  );
}

/// Banner di beranda yang mengajak pengguna mencari pakaian yang cocok.
class StyleBanner extends StatelessWidget {
  const StyleBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final hasProfile = context.select<StyleProvider, bool>((s) => s.hasProfile);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openStylist(context),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF111111), Color(0xFF3A0A0C)],
              ),
              boxShadow: AppShadows.lift,
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'BARU - UNIQLO PLUS STYLIST',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hasProfile
                            ? 'Lihat pakaian yang cocok untukmu'
                            : 'Tidak paham fashion? Foto selfie, kami pilihkan.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        hasProfile
                            ? 'Rekomendasi dari bentuk wajah, warna kulit, tinggi, dan berat badanmu.'
                            : 'Bentuk wajah, warna kulit, tinggi, dan berat badan dibaca untuk menemukan model, warna, dan ukuran yang pas.',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasProfile
                                  ? Icons.auto_awesome
                                  : Icons.photo_camera_outlined,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasProfile ? 'Lihat rekomendasi' : 'Coba sekarang',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.face_retouching_natural, color: Colors.white24, size: 74),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
