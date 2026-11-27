import 'package:flutter/material.dart';

/// Warna dan gaya bersama agar tampilan konsisten di seluruh aplikasi.
class AppColors {
  AppColors._();

  static const Color red = Color(0xFFEC1C24);
  static const Color redDark = Color(0xFFB71C1C);
  static const Color redSoft = Color(0xFFFFF1F1);
  static const Color ink = Color(0xFF111111);
  static const Color bg = Color(0xFFF5F5F6);
  static const Color surface = Colors.white;
  static const Color muted = Color(0xFF6B6B70);
  static const Color line = Color(0xFFE8E8EB);
  static const Color success = Color(0xFF2E7D32);
  static const Color star = Color(0xFFF9A825);
}

class AppShadows {
  AppShadows._();

  static const List<BoxShadow> soft = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> lift = [
    BoxShadow(
      color: Color(0x22000000),
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];
}

/// Dekorasi kartu putih berbayang lembut.
BoxDecoration cardDecoration({
  double radius = 16,
  Color color = AppColors.surface,
  bool shadow = true,
  bool border = false,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: shadow ? AppShadows.soft : null,
    border: border ? Border.all(color: AppColors.line) : null,
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.red,
    primary: AppColors.red,
    surface: AppColors.surface,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        if (states.contains(WidgetState.selected)) return AppColors.red;
        return null;
      }),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
