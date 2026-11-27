import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../DATA/voucher_data.dart';
import '../MODELS/voucher_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../SERVICES/api_service.dart';
import '../UTILS/formatters.dart';
import '../UTILS/toast.dart';
import 'login_page.dart';

/// Daftar voucher beserta status kelayakan untuk pengguna saat ini.
class VouchersPage extends StatelessWidget {
  const VouchersPage({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<ApiService>(); // daftar voucher berasal dari database server
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'VOUCHER',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 16,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!auth.isLoggedIn)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFCDD2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              color: Color(0xFFEC1C24)),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Masuk sebagai member untuk memakai voucher khusus member.',
                              style: TextStyle(fontSize: 12.5, height: 1.35),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            ),
                            child: const Text(
                              'MASUK',
                              style: TextStyle(
                                color: Color(0xFFEC1C24),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Salin kode lalu masukkan di halaman checkout.',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  for (final voucher in kVouchers)
                    _VoucherCard(
                      voucher: voucher,
                      problem: voucher.validate(
                        subtotal: double.maxFinite,
                        isMember: auth.isLoggedIn,
                        tier: auth.tier,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoucherCard extends StatelessWidget {
  const _VoucherCard({required this.voucher, required this.problem});

  final Voucher voucher;

  /// Alasan voucher belum bisa dipakai (`null` = bisa dipakai).
  final String? problem;

  IconData get _icon {
    switch (voucher.type) {
      case VoucherType.percent:
        return Icons.percent;
      case VoucherType.fixed:
        return Icons.payments_outlined;
      case VoucherType.freeShipping:
        return Icons.local_shipping_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usable = problem == null;
    final accent = usable ? const Color(0xFFEC1C24) : Colors.grey;

    return Opacity(
      opacity: usable ? 1 : 0.7,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 70,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(11),
                  ),
                ),
                child: Icon(_icon, color: Colors.white, size: 30),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voucher.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        voucher.benefitLabel,
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        voucher.description,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Min. belanja ${formatRupiah(voucher.minSpend)}  |  '
                        'Berlaku s/d ${formatDate(voucher.expiresAt)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                      if (!usable) ...[
                        const SizedBox(height: 6),
                        Text(
                          problem!,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              voucher.code,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: voucher.code),
                              );
                              if (!context.mounted) return;
                              showAppToast(
                                context,
                                'Kode ${voucher.code} disalin',
                                icon: Icons.copy,
                              );
                            },
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text(
                              'Salin',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
