import 'package:flutter/material.dart';

/// Membuka halaman baru di atas halaman saat ini.
Future<T?> pushPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(builder: (_) => page),
  );
}
