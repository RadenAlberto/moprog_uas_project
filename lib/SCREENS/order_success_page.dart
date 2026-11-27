import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../MODELS/order_model.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../UTILS/order_actions.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/ui_kit.dart';
import 'order_detail_page.dart';

/// Layar akhir setelah bayar dan memilih cara penerimaan.
/// Tetap tampil sampai pembeli memilih langkah berikutnya.
class OrderSuccessPage extends StatelessWidget {
  const OrderSuccessPage({super.key, required this.orderId});

  final String orderId;

  void _home(BuildContext context) {
    final appState = context.read<AppState>();
    Navigator.of(context).popUntil((r) => r.isFirst);
    appState.setTab(0);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    Order? order;
    for (final o in auth.myOrders) {
      if (o.id == orderId) order = o;
    }
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pesanan')),
        body: const Center(child: Text('Pesanan tidak ditemukan')),
      );
    }
    final o = order;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _home(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(o.paymentStatus.toLowerCase() == 'pending'
              ? 'Pesanan Dibuat' : 'Pesanan Berhasil'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8F5E9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle,
                          color: AppColors.success, size: 56),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Terima kasih!',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCashOnDeliveryLabel(o)
                          ? 'Pesanan dibuat. Siapkan pembayaran tunai saat pesanan diterima.'
                          : o.paymentStatus.toLowerCase() == 'pending'
                              ? 'Pesanan berhasil dibuat, tetapi pembayaran masih Pending. Buka detail pesanan untuk menyelesaikan pembayaran simulasi.'
                              : o.paymentStatus.toLowerCase() == 'refunded'
                                  ? 'Pesanan dibatalkan dan dana ditandai telah direfund (simulasi).'
                                  : 'Pembayaran diterima dan pesanan sedang diproses.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (o.isPickup) _pickupCard(context, o),
                if (o.isDelivery) _deliveryCard(o),
                if (o.needsFulfillment)
                  SurfaceCard(
                    child: Text(
                      'Cara penerimaan belum dipilih. Buka Detail Pesanan '
                      'untuk memilih ambil di toko atau diantar.',
                      style: TextStyle(color: Colors.orange.shade800),
                    ),
                  ),
                const SizedBox(height: 12),
                SurfaceCard(
                  child: Column(
                    children: [
                      KeyValueRow(label: 'No. Pesanan', value: o.id),
                      KeyValueRow(label: 'Metode bayar', value: o.paymentMethod),
                      KeyValueRow(label: 'Status pembayaran', value: o.paymentStatus),
                      if (o.paymentInfo != null)
                        KeyValueRow(label: 'Kanal', value: o.paymentInfo!),
                      if (o.gatewayRef != null)
                        KeyValueRow(label: 'Ref. gateway', value: o.gatewayRef!),
                      KeyValueRow(
                        label: o.isPickup && o.shippingRefund > 0
                            ? 'Total (ongkir dikembalikan)'
                            : 'Total',
                        value: formatRupiah(o.total),
                        bold: true,
                      ),
                      KeyValueRow(
                        label: 'Poin didapat',
                        value: '+${o.pointsEarned} poin',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.replay),
                    label: const Text('BELI LAGI'),
                    onPressed: () => reorderItems(context, o),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderDetailPage(orderId: o.id),
                      ),
                    ),
                    child: const Text('LIHAT PESANAN'),
                  ),
                ),
                TextButton(
                  onPressed: () => _home(context),
                  child: const Text('Lanjut belanja'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool isCashOnDeliveryLabel(Order o) => o.paymentMethod.startsWith('COD');

  Widget _pickupCard(BuildContext context, Order o) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storefront_outlined, color: AppColors.red),
              SizedBox(width: 8),
              Text('Ambil di toko',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text(o.storeName ?? '-',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(o.storeAddress ?? '',
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.redSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                const Text('Kode ambil',
                    style: TextStyle(color: AppColors.muted, fontSize: 12)),
                SelectableText(
                  o.pickupCode ?? '-',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: o.pickupCode ?? ''));
                    if (context.mounted) {
                      showAppToast(context, 'Kode ambil disalin');
                    }
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Salin'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kami beri tahu di Notifikasi saat pesanan siap diambil. '
            'Tunjukkan kode dan identitas ke kasir.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _deliveryCard(Order o) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_shipping_outlined, color: AppColors.red),
              SizedBox(width: 8),
              Text('Diantar ke alamat',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Text('${o.recipient} · ${o.phone}',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(o.address,
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          const SizedBox(height: 6),
          Text(o.deliveryService ?? 'Reguler',
              style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}
