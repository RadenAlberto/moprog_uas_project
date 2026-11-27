import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'APP/app_providers.dart';
import 'DATA/product_data.dart';
import 'SCREENS/main_navigation.dart';
import 'SCREENS/splash_page.dart';
import 'SERVICES/learned_model.dart';
import 'UTILS/app_theme.dart';
import 'UTILS/key_value_store.dart';
import 'UTILS/prefs_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Penyimpanan permanen (akun, pesanan, keranjang). Bila gagal dibuka,
  // aplikasi tetap jalan memakai penyimpanan sementara di memori.
  KeyValueStore store;
  try {
    store = PrefsStore(await SharedPreferences.getInstance());
  } catch (_) {
    store = MemoryStore();
  }

  // Katalog produk Uniqlo dimuat dari aset sebelum aplikasi tampil. Bila gagal,
  // katalog kosong dan aplikasi mengambilnya dari server saat online.
  try {
    await loadProductCatalog();
  } catch (_) {}

  // Model ML hasil pelatihan (bukti data ada di ml/artifacts/REPORT.md).
  await loadLearnedModel();

  runApp(AppProviders(store: store, child: const UniqloPlusApp()));
}

class UniqloPlusApp extends StatelessWidget {
  const UniqloPlusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNIQLO PLUS',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Animasi logo dulu, lalu masuk ke aplikasi.
      home: const IntroGate(child: MainNavigation()),
    );
  }
}
