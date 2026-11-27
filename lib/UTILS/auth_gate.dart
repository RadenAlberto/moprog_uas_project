import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/auth_provider.dart';
import '../SCREENS/login_page.dart';
import '../SCREENS/register_page.dart';

/// Pesan standar saat tamu mencoba checkout.
const String kCheckoutMemberMessage =
    'Checkout khusus member UNIQLO. Masuk atau gabung member untuk melanjutkan. '
    'Isi keranjang dan wishlist Anda tetap tersimpan.';

enum _GateChoice { login, register }

/// Memastikan pengguna sudah menjadi member yang login.
///
/// - Jika sudah login, langsung mengembalikan `true`.
/// - Jika belum, menampilkan pilihan MASUK / DAFTAR MEMBER. Setelah pengguna
///   berhasil masuk atau mendaftar, mengembalikan `true`; jika dibatalkan,
///   mengembalikan `false`.
///
/// Keranjang dan wishlist tamu digabung ke data akun saat login
/// (lihat `AppState.setActiveMember`), jadi isinya tidak hilang.
Future<bool> requireMember(
  BuildContext context, {
  String message = kCheckoutMemberMessage,
}) async {
  final auth = context.read<AuthProvider>();
  if (auth.isLoggedIn) return true;

  final navigator = Navigator.of(context);

  final choice = await showModalBottomSheet<_GateChoice>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => _MemberGateSheet(message: message),
  );

  if (choice == null) return false;

  final Widget page = choice == _GateChoice.login
      ? LoginPage(message: message)
      : const RegisterPage();

  await navigator.push<bool>(MaterialPageRoute(builder: (_) => page));

  // Sumber kebenaran: status login, bukan nilai yang dikembalikan halaman.
  return auth.isLoggedIn;
}

class _MemberGateSheet extends StatelessWidget {
  const _MemberGateSheet({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFF5F5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_outline,
                    color: Color(0xFFEC1C24),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Masuk untuk Checkout',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEC1C24),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(_GateChoice.login),
                child: const Text(
                  'MASUK SEBAGAI MEMBER',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () =>
                    Navigator.of(context).pop(_GateChoice.register),
                child: const Text(
                  'GABUNG MEMBER UNIQLO',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Nanti saja, lanjut lihat-lihat'),
            ),
          ],
        ),
      ),
    );
  }
}
