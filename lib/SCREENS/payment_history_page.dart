import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/payment_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../UTILS/nav.dart';
import '../WIDGETS/member_required_view.dart';
import '../WIDGETS/ui_kit.dart';
import 'order_detail_page.dart';

/// Riwayat pembayaran: semua transaksi member beserta status, metode, dan
/// nomor referensi. Ketuk satu baris untuk membuka rincian pesanan.
class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  PaymentStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('RIWAYAT PEMBAYARAN')),
      body: SafeArea(
        child: auth.isLoggedIn
            ? _buildBody(auth)
            : const MemberRequiredView(
                title: 'Riwayat pembayaran khusus member',
                message:
                    'Masuk atau gabung member untuk melihat semua transaksi '
                    'dan status pembayaran Anda.',
                icon: Icons.account_balance_wallet_outlined,
              ),
      ),
    );
  }

  Widget _buildBody(AuthProvider auth) {
    final all = auth.paymentRecords;
    final records =
        _filter == null ? all : all.where((r) => r.status == _filter).toList();

    var paid = 0.0;
    var pending = 0.0;
    var refunded = 0.0;
    for (final r in all) {
      switch (r.status) {
        case PaymentStatus.lunas:
          paid += r.amount;
        case PaymentStatus.menunggu:
          pending += r.amount;
        case PaymentStatus.dikembalikan:
          refunded += r.amount;
        case PaymentStatus.dibatalkan:
          break;
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _SummaryCard(paid: paid, pending: pending, refunded: refunded),
            const SizedBox(height: 16),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip('Semua (${all.length})', null),
                  for (final status in PaymentStatus.values)
                    _chip(
                      '${status.label} (${all.where((r) => r.status == status).length})',
                      status,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: all.isEmpty
                      ? 'Belum ada transaksi'
                      : 'Tidak ada transaksi pada filter ini',
                  message: all.isEmpty
                      ? 'Pembayaran Anda akan tercatat di sini setelah '
                          'checkout pertama.'
                      : null,
                ),
              )
            else
              for (final record in records) _PaymentTile(record: record),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, PaymentStatus? status) {
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.ink,
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        onSelected: (_) => setState(() => _filter = status),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.paid,
    required this.pending,
    required this.refunded,
  });

  final double paid;
  final double pending;
  final double refunded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B1B1F), Color(0xFF3A3A42)],
        ),
        boxShadow: AppShadows.lift,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOTAL TERBAYAR',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatRupiah(paid),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _mini('Menunggu pembayaran', formatRupiahCompact(pending)),
              ),
              Expanded(
                child: _mini('Dikembalikan', formatRupiahCompact(refunded)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.record});

  final PaymentRecord record;

  @override
  Widget build(BuildContext context) {
    final status = record.status;
    final strike = status == PaymentStatus.dikembalikan;

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: () => pushPage(context, OrderDetailPage(orderId: record.order.id)),
      child: Row(
        children: [
          IconBadge(icon: status.icon, color: status.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.reference,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.method} • ${record.order.itemCount} barang',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateTime(record.paidAt),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatRupiah(record.amount),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  decoration: strike ? TextDecoration.lineThrough : null,
                  color: strike ? AppColors.muted : AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              PillTag(
                label: (record.isCod && status == PaymentStatus.menunggu
                      ? 'BAYAR DI TEMPAT'
                      : status.label.toUpperCase()),
                color: status.color.withValues(alpha: 0.12),
                textColor: status.color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
