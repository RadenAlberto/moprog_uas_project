import 'package:flutter/material.dart';

/// Lokasi berkas logo aplikasi (UNIQLO PLUS).
const String kLogoAsset = 'assets/images/logo.png';

/// Logo UNIQLO PLUS berbentuk persegi merah. Dipakai di header, kartu member,
/// halaman masuk, dan animasi pembuka.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40, this.radius = 6});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        kLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: 'Logo UNIQLO PLUS',
        // Bila berkas aset hilang, tampilkan kotak merah polos (bukan crash).
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: const Color(0xFFEC1C24),
          alignment: Alignment.center,
          child: Text(
            'UQ+',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: size * 0.3,
            ),
          ),
        ),
      ),
    );
  }
}
