import 'package:flutter/material.dart';

import '../SERVICES/manual_book_service.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';
import '../UTILS/toast.dart';

/// Menu "Informasi": bisa dibuka semua pengguna (tamu maupun member).
/// Berisi INSTRUCTION BOOK (PDF) dalam Bahasa Indonesia dan English yang
/// bisa dibuka langsung maupun diunduh.
class InformationPage extends StatefulWidget {
  const InformationPage({super.key});

  @override
  State<InformationPage> createState() => _InformationPageState();
}

class _InformationPageState extends State<InformationPage> {
  late ManualLanguage _lang = ManualBookService.deviceLanguage();
  bool _busy = false;

  bool get _id => _lang == ManualLanguage.id;

  String _t(String id, String en) => _id ? id : en;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ManualBookException catch (e) {
      if (mounted) {
        showAppToast(
          context,
          e.message,
          color: Colors.red.shade700,
          icon: Icons.error_outline,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() => _run(() => ManualBookService.open(_lang));

  Future<void> _download() => _run(() async {
        final path = await ManualBookService.download(_lang);
        if (path != null && mounted) {
          showAppToast(
            context,
            _t('Tersimpan di: $path', 'Saved to: $path'),
            icon: Icons.download_done,
          );
        }
      });

  List<(String, String)> get _chapters => const [
        ('Kenali Aplikasi', 'Meet the App'),
        ('Daftar & Masuk', 'Sign Up & Log In'),
        ('Beranda & Pencarian', 'Home & Search'),
        ('Produk & Keranjang', 'Products & Cart'),
        ('Checkout', 'Checkout'),
        ('Pembayaran & Penerimaan', 'Payment & Receiving'),
        ('Pesanan Saya', 'My Orders'),
        ('Poin, Level & Voucher', 'Points, Levels & Vouchers'),
        ('Studio & Stylist', 'Studio & Stylist'),
        ('Toko, Ukuran & Info', 'Stores, Sizes & Info'),
        ('Tips & Bantuan', 'Tips & Help'),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('INFORMASI')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HeroCard(
                  lang: _lang,
                  busy: _busy,
                  onLanguage: (l) => setState(() => _lang = l),
                  onOpen: _open,
                  onDownload: _download,
                ),
                const SizedBox(height: 22),
                Text(
                  _t('Isi buku', 'Inside the book'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration:
                      cardDecoration(radius: 14, border: true, shadow: false),
                  child: Column(
                    children: [
                      for (var i = 0; i < _chapters.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 1, color: AppColors.line),
                        ListTile(
                          dense: true,
                          leading: Text(
                            (i + 1).toString().padLeft(2, '0'),
                            style: const TextStyle(
                              color: AppColors.red,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          title: Text(
                            _id ? _chapters[i].$1 : _chapters[i].$2,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.redSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: AppColors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _t(
                            'Buku ini tersedia untuk semua pengguna, termasuk '
                                'yang belum mendaftar, dan tersimpan di aplikasi '
                                'sehingga bisa dibuka tanpa internet.',
                            'This book is available to everyone, including '
                                'people who have not signed up yet, and is '
                                'stored in the app so it opens without internet.',
                          ),
                          style: const TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'UNIQLO PLUS  v1.0.0',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.lang,
    required this.busy,
    required this.onLanguage,
    required this.onOpen,
    required this.onDownload,
  });

  final ManualLanguage lang;
  final bool busy;
  final ValueChanged<ManualLanguage> onLanguage;
  final VoidCallback onOpen;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final id = lang == ManualLanguage.id;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.lift,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.red, AppColors.redDark],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sampul buku mini.
              Container(
                width: 74,
                height: 104,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 10,
                      offset: Offset(3, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 26,
                        height: 26,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      'INSTRUC-\nTION\nBOOK',
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        color: AppColors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lang.code,
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INSTRUCTION BOOK',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      id
                          ? 'Panduan memakai UNIQLO PLUS dari daftar, belanja, '
                              'sampai Studio gaya. 16 halaman, PDF.'
                          : 'A guide to UNIQLO PLUS from sign-up and '
                              'shopping to the style Studio. 16 pages, PDF.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ManualLanguage>(
              showSelectedIcon: false,
              segments: [
                for (final l in ManualLanguage.values)
                  ButtonSegment<ManualLanguage>(
                    value: l,
                    label: Text(l.label),
                  ),
              ],
              selected: {lang},
              onSelectionChanged: (s) => onLanguage(s.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                foregroundColor: Colors.white,
                selectedBackgroundColor: Colors.white,
                selectedForegroundColor: AppColors.red,
                side: const BorderSide(color: Colors.white54),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.red,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: busy ? null : onOpen,
                  icon: const Icon(Icons.menu_book_outlined, size: 20),
                  label: Text(
                    id ? 'BUKA' : 'OPEN',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    side: const BorderSide(color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: busy ? null : onDownload,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_outlined, size: 20),
                  label: Text(
                    id ? 'UNDUH' : 'DOWNLOAD',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tautan kecil "Baru? Baca INSTRUCTION BOOK" untuk halaman masuk / daftar
/// supaya pengguna baru tahu panduan ini ada.
class InstructionBookLink extends StatelessWidget {
  const InstructionBookLink({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => pushPage(context, const InformationPage()),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.redSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.menu_book_outlined, color: AppColors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Baru di UNIQLO PLUS? Baca INSTRUCTION BOOK '
                '(Indonesia / English).',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
