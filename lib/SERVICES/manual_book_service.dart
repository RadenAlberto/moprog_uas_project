import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bahasa INSTRUCTION BOOK yang tersedia.
enum ManualLanguage {
  id('ID', 'Bahasa Indonesia'),
  en('EN', 'English');

  const ManualLanguage(this.code, this.label);

  final String code;
  final String label;
}

/// Gagal membuka / menyimpan INSTRUCTION BOOK.
class ManualBookException implements Exception {
  ManualBookException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Membuka dan mengunduh INSTRUCTION BOOK (PDF) yang dibundel di aset aplikasi.
///
/// File ada di `assets/docs/` sehingga bisa dibuka oleh semua pengguna
/// (tamu maupun member), bahkan tanpa koneksi internet.
///
/// - Android / iOS: "Buka" memakai aplikasi PDF di perangkat, "Unduh" membuka
///   lembar bagikan sistem (Simpan ke File/Downloads, Drive, WhatsApp, dll).
/// - Windows / macOS / Linux: "Buka" memakai aplikasi PDF bawaan, "Unduh"
///   menyalin file ke folder Downloads.
/// - Web: membuka PDF di tab baru (browser menyediakan tombol unduh).
class ManualBookService {
  ManualBookService._();

  /// Nama dasar file yang dilihat pengguna.
  static const String baseName = 'INSTRUCTION BOOK';

  static String assetPath(ManualLanguage lang) =>
      'assets/docs/INSTRUCTION_BOOK_${lang.code}.pdf';

  /// Nama file saat disimpan / dibagikan, mis. `INSTRUCTION BOOK - ID.pdf`.
  static String fileName(ManualLanguage lang) =>
      '$baseName - ${lang.code}.pdf';

  /// Bahasa awal mengikuti bahasa perangkat (Indonesia -> ID, lainnya -> EN).
  static ManualLanguage deviceLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return code == 'id' ? ManualLanguage.id : ManualLanguage.en;
  }

  static bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Menyalin PDF dari aset ke folder sementara dengan nama file yang rapi.
  static Future<File> _extract(ManualLanguage lang) async {
    final data = await rootBundle.load(assetPath(lang));
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${fileName(lang)}');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file;
  }

  static Future<void> _openInBrowser(ManualLanguage lang) async {
    // Aset Flutter Web dilayani di <base>/assets/<kunci aset>.
    final uri = Uri.base.resolve('assets/${assetPath(lang)}');
    final ok = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!ok) {
      throw ManualBookException('Tidak dapat membuka PDF di browser.');
    }
  }

  /// Membuka PDF di aplikasi pembaca PDF.
  static Future<void> open(ManualLanguage lang) async {
    try {
      if (kIsWeb) {
        await _openInBrowser(lang);
        return;
      }
      final file = await _extract(lang);
      final result = await OpenFilex.open(file.path, type: 'application/pdf');
      if (result.type != ResultType.done) {
        throw ManualBookException(
          result.type == ResultType.noAppToOpen
              ? 'Tidak ada aplikasi PDF di perangkat ini. '
                  'Gunakan tombol Unduh lalu buka dari File.'
              : (result.message.isEmpty
                  ? 'PDF tidak dapat dibuka.'
                  : result.message),
        );
      }
    } on ManualBookException {
      rethrow;
    } catch (e) {
      throw ManualBookException('PDF tidak dapat dibuka: $e');
    }
  }

  /// Mengunduh / menyimpan PDF.
  ///
  /// Mengembalikan path file bila disimpan langsung (desktop), atau `null`
  /// bila pengguna memilih tujuan lewat lembar bagikan (mobile) / browser (web).
  static Future<String?> download(ManualLanguage lang) async {
    try {
      if (kIsWeb) {
        await _openInBrowser(lang);
        return null;
      }
      final file = await _extract(lang);
      final name = fileName(lang);

      if (_isMobile) {
        await SharePlus.instance.share(
          ShareParams(
            title: name,
            files: [
              XFile(file.path, mimeType: 'application/pdf', name: name),
            ],
            fileNameOverrides: [name],
          ),
        );
        return null;
      }

      final dir =
          await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final target = File('${dir.path}${Platform.pathSeparator}$name');
      await file.copy(target.path);
      return target.path;
    } on ManualBookException {
      rethrow;
    } catch (e) {
      throw ManualBookException('PDF tidak dapat disimpan: $e');
    }
  }
}
