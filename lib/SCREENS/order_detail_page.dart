import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../DATA/product_data.dart';
import '../MODELS/order_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../UTILS/order_actions.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/order_widgets.dart';
import '../WIDGETS/product_image.dart';
import 'fulfillment_page.dart';

/// Detail pesanan: status, linimasa pelacakan, produk, alamat, dan rincian
/// pembayaran. Pesanan yang belum selesai masih dapat dibatalkan oleh member.
class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
    // Muat ulang snapshot dari backend saat detail dibuka agar data yang
    // ditampilkan sama dengan pesanan di control panel, bukan cache lama.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<AuthProvider>().refreshServerData());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _cancel(Order order) async {
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan pesanan?'),
        content: Text(
          order.paymentStatus.toLowerCase() == 'paid'
              ? 'Pesanan ${order.id} akan dibatalkan. Poin yang dipakai dikembalikan, poin dari pesanan dibatalkan, dan dana akan ditandai sudah direfund (simulasi).'
              : 'Pesanan ${order.id} akan dibatalkan. Poin yang dipakai dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Tidak'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Ya, batalkan',
              style: TextStyle(color: Color(0xFFEC1C24)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final cancelled = await auth.cancelOrder(order.id);
    if (!mounted) return;
    if (cancelled) {
      showAppToast(
        context,
        order.paymentStatus.toLowerCase() == 'paid'
            ? 'Pesanan dibatalkan. Dana telah direfund (simulasi).'
            : 'Pesanan dibatalkan.',
        color: Colors.grey.shade900,
        icon: Icons.cancel_outlined,
      );
    } else {
      showAppToast(
        context,
        'Pesanan sudah tidak bisa dibatalkan',
        color: Colors.red.shade700,
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _simulatePayment(Order order) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.simulatePayment(order.id);
    if (!mounted) return;
    if (ok) {
      showAppToast(context, 'Pembayaran simulasi berhasil. Status menjadi Paid.',
          color: AppColors.success, icon: Icons.check_circle_outline);
    } else {
      showAppToast(context, 'Pembayaran simulasi gagal. Silakan coba lagi.',
          color: Colors.red.shade700, icon: Icons.error_outline);
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppToast(context, '$label disalin', icon: Icons.copy);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final order = auth.orderById(widget.orderId);

    final appBar = AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: const Text(
        'DETAIL PESANAN',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          fontSize: 16,
        ),
      ),
    );

    if (order == null) {
      return Scaffold(
        appBar: appBar,
        body: const Center(child: Text('Pesanan tidak ditemukan.')),
      );
    }

    final status = order.status;
    final showTracking = order.isDelivery &&
        (status == OrderStatus.dikirim || status == OrderStatus.selesai);

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: appBar,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusBanner(order: order, status: status),
                  const SizedBox(height: 14),
                  _Section(
                    title: 'Informasi Pesanan',
                    icon: Icons.receipt_long_outlined,
                    child: Column(
                      children: [
                        _PriceRow('Nomor pesanan', order.id, plain: true),
                        _PriceRow('Tanggal pesanan',
                            formatDateTime(order.createdAt), plain: true),
                        _PriceRow('Status pesanan',
                            order.statusLabel(status), plain: true),
                        _PriceRow('Status pembayaran',
                            order.paymentStatus, plain: true),
                        _PriceRow('Metode pembayaran',
                            order.paymentMethod, plain: true),
                        if ((order.paymentInfo ?? '').trim().isNotEmpty)
                          _PriceRow('Info pembayaran',
                              order.paymentInfo!.trim(), plain: true),
                        if ((order.gatewayRef ?? '').trim().isNotEmpty)
                          _PriceRow('Referensi transaksi',
                              order.gatewayRef!.trim(), plain: true),
                        _PriceRow(
                          'Cara penerimaan',
                          order.isPickup
                              ? 'Ambil di toko'
                              : order.isDelivery
                                  ? 'Diantar ke alamat'
                                  : 'Belum dipilih',
                          plain: true,
                        ),
                        if (order.isPickup) ...[
                          const Divider(height: 16),
                          _PriceRow('Toko pengambilan',
                              order.storeName ?? '-', plain: true),
                          _PriceRow('Alamat toko',
                              order.storeAddress ?? '-', plain: true),
                          _PriceRow('Kode pengambilan',
                              order.pickupCode ?? '-', plain: true),
                        ] else if (order.isDelivery) ...[
                          const Divider(height: 16),
                          _PriceRow('Nama penerima',
                              order.recipient.isEmpty ? '-' : order.recipient,
                              plain: true),
                          _PriceRow('Nomor telepon',
                              order.phone.isEmpty ? '-' : order.phone,
                              plain: true),
                          _PriceRow('Alamat pengiriman',
                              order.address.isEmpty ? '-' : order.address,
                              plain: true),
                          _PriceRow('Layanan pengiriman',
                              order.deliveryService ?? '-', plain: true),
                        ] else if (order.needsFulfillment) ...[
                          const Divider(height: 16),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Pilih toko pengambilan atau alamat pengiriman untuk melengkapi pesanan.',
                              style: TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Section(
                    title: 'Status Pembayaran',
                    icon: Icons.payment_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            order.paymentStatus.toLowerCase() == 'paid'
                                ? Icons.check_circle
                                : order.paymentStatus.toLowerCase() == 'refunded'
                                    ? Icons.currency_exchange
                                    : Icons.schedule,
                            color: order.paymentStatus.toLowerCase() == 'paid'
                                ? AppColors.success
                                : order.paymentStatus.toLowerCase() == 'refunded'
                                    ? Colors.blueGrey
                                    : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            order.paymentStatus == 'Paid' ? 'Sudah dibayar'
                                : order.paymentStatus == 'Refunded' ? 'Direfund (simulasi)'
                                : order.paymentStatus.toLowerCase() == 'unpaid' ? 'Belum dibayar (COD)'
                                : order.paymentStatus,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ]),
                        if (order.paymentStatus.toLowerCase() == 'unpaid' &&
                            order.isCod && !order.isCancelled) ...[
                          const SizedBox(height: 8),
                          const Text('Pembayaran COD dilakukan saat pesanan diterima atau diambil. Pesanan ini belum ditandai lunas.'),
                        ],
                        if (order.paymentStatus.toLowerCase() == 'pending' &&
                            !order.isCancelled) ...[
                          const SizedBox(height: 8),
                          const Text('Pesanan menunggu pembayaran. Selesaikan pembayaran agar pesanan dapat diproses.'),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _simulatePayment(order),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('SIMULASIKAN PEMBAYARAN BERHASIL'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const Text('Ini hanya simulasi untuk keperluan pengujian; tidak ada uang sungguhan yang dipindahkan.',
                            style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        ],
                        if (order.paymentStatus.toLowerCase() == 'refunded')
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('Dana ditandai telah direfund. Ini merupakan simulasi dan tidak ada transfer uang sungguhan.'),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (order.needsFulfillment) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pilih cara penerimaan',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ambil di toko UNIQLO terdekat atau diantar ke alamat.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    FulfillmentPage(orderId: order.id),
                              ),
                            ),
                            child: const Text('PILIH SEKARANG'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  _Section(
                    title: 'Status Pesanan',
                    icon: Icons.timeline,
                    child: _Timeline(order: order, status: status),
                  ),
                  const SizedBox(height: 14),
                  if (order.isPickup)
                    _Section(
                      title: 'Ambil di Toko',
                      icon: Icons.storefront_outlined,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.storeName ?? '-',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.storeAddress ?? '',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Kode ambil: ${order.pickupCode ?? '-'}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _copy(
                                    order.pickupCode ?? '', 'Kode ambil'),
                                icon: const Icon(Icons.copy, size: 14),
                                label: const Text(
                                  'Salin',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          if (order.shippingRefund > 0)
                            Text(
                              'Ongkir ${formatRupiah(order.shippingRefund)} dikembalikan.',
                              style: const TextStyle(
                                color: AppColors.success,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    )
                  else if (!order.needsFulfillment)
                    _Section(
                    title: 'Info Pengiriman',
                    icon: Icons.local_shipping_outlined,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.recipient} | ${order.phone}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          order.address,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                        if (showTracking) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'No. resi: ${order.trackingNumber}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    _copy(order.trackingNumber, 'No. resi'),
                                icon: const Icon(Icons.copy, size: 14),
                                label: const Text(
                                  'Salin',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Section(
                    title: 'Produk (${order.itemCount} item)',
                    icon: Icons.shopping_bag_outlined,
                    child: Column(
                      children: [
                        for (var i = 0; i < order.items.length; i++) ...[
                          if (i > 0) const Divider(height: 18),
                          _ItemRow(item: order.items[i]),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Section(
                    title: 'Rincian Pembayaran',
                    icon: Icons.receipt_long_outlined,
                    child: Column(
                      children: [
                        _PriceRow('Metode pembayaran', order.paymentMethod,
                            plain: true),
                        const Divider(height: 18),
                        _PriceRow('Subtotal produk', formatRupiah(order.subtotal)),
                        if (order.memberDiscount > 0)
                          _PriceRow(
                            'Diskon member',
                            '-${formatRupiah(order.memberDiscount)}',
                            color: const Color(0xFF2E7D32),
                          ),
                        if (order.voucherDiscount > 0)
                          _PriceRow(
                            'Voucher${order.voucherCode == null ? '' : ' (${order.voucherCode})'}',
                            '-${formatRupiah(order.voucherDiscount)}',
                            color: const Color(0xFF2E7D32),
                          ),
                        if (order.pointsUsed > 0)
                          _PriceRow(
                            'Tukar poin (${order.pointsUsed} poin)',
                            '-${formatRupiah(order.pointsDiscount)}',
                            color: const Color(0xFF2E7D32),
                          ),
                        _PriceRow(
                            'Ongkos kirim', formatRupiah(order.shippingFee)),
                        if (order.shippingDiscount > 0)
                          _PriceRow(
                            order.voucherCode != null &&
                                    order.voucherDiscount == 0
                                ? 'Gratis ongkir (${order.voucherCode})'
                                : 'Gratis ongkir',
                            '-${formatRupiah(order.shippingDiscount)}',
                            color: const Color(0xFF2E7D32),
                          ),
                        const Divider(height: 18),
                        _PriceRow(
                          'Total pembayaran',
                          formatRupiah(order.total),
                          bold: true,
                          color: const Color(0xFFEC1C24),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: order.isCancelled
                          ? Colors.grey.shade100
                          : const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.stars,
                              size: 18,
                              color: order.isCancelled
                                  ? Colors.grey
                                  : const Color(0xFF2E7D32),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                order.isCancelled
                                    ? 'Poin dari pesanan ini dibatalkan'
                                    : 'Poin didapat: +${order.pointsEarned} poin',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!order.isCancelled && order.totalSavings > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Total hemat pada pesanan ini: ${formatRupiah(order.totalSavings)}',
                            style: TextStyle(
                              color: Colors.grey.shade800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'No. pesanan: ${order.id}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Salin no. pesanan',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.copy, size: 16),
                        onPressed: () => _copy(order.id, 'No. pesanan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 70),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE0E0E0))),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(
                children: [
                  if (order.canCancel) ...[
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFEC1C24),
                          side: const BorderSide(color: Color(0xFFEC1C24)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => _cancel(order),
                        child: const Text(
                          'BATALKAN',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEC1C24),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => reorderItems(context, order),
                      child: const Text(
                        'BELI LAGI',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
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

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.order, required this.status});

  final Order order;
  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: status.color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: status.color,
              shape: BoxShape.circle,
            ),
            child: Icon(status.icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      order.statusLabel(status),
                      style: TextStyle(
                        color: status.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OrderStatusChip(
                      status: status,
                      label: order.statusLabel(status),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  order.statusDescription(status),
                  style: const TextStyle(fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 4),
                Text(
                  'Dipesan ${formatDateTime(order.createdAt)}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFEC1C24)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          child,
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order, required this.status});

  final Order order;
  final OrderStatus status;

  String _label(OrderStatus step) {
    if (order.isPickup) {
      if (step == OrderStatus.dikemas) return 'Pesanan disiapkan di toko';
      if (step == OrderStatus.dikirim) return 'Siap diambil';
    }
    switch (step) {
      case OrderStatus.diproses:
        return 'Pesanan dibuat & dibayar';
      case OrderStatus.dikemas:
        return 'Pesanan dikemas';
      case OrderStatus.dikirim:
        return 'Pesanan dikirim';
      case OrderStatus.selesai:
        return 'Pesanan selesai';
      case OrderStatus.dibatalkan:
        return 'Pesanan dibatalkan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = order.isCancelled
        ? const [OrderStatus.diproses, OrderStatus.dibatalkan]
        : const [
            OrderStatus.diproses,
            OrderStatus.dikemas,
            OrderStatus.dikirim,
            OrderStatus.selesai,
          ];
    final currentIndex = steps.indexOf(status);

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineStep(
            title: _label(steps[i]),
            subtitle: i <= currentIndex
                ? formatDateTime(order.stageStart(steps[i]))
                : 'Menunggu',
            note: i == currentIndex ? order.statusDescription(steps[i]) : null,
            color: steps[i].color,
            icon: steps[i].icon,
            reached: i <= currentIndex,
            isCurrent: i == currentIndex,
            isLast: i == steps.length - 1,
            lineReached: i < currentIndex,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.reached,
    required this.isCurrent,
    required this.isLast,
    required this.lineReached,
    this.note,
  });

  final String title;
  final String subtitle;
  final String? note;
  final Color color;
  final IconData icon;
  final bool reached;
  final bool isCurrent;
  final bool isLast;
  final bool lineReached;

  @override
  Widget build(BuildContext context) {
    final dotColor = reached ? color : Colors.grey.shade300;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.35),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: lineReached ? color : Colors.grey.shade300,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: reached ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13,
                        color: reached ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11.5,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      note!,
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OrderItemImage(
          item,
          width: 54,
          height: 72,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: item.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '${colorNameFor(item.productId, item.color, colorLabel)} | Ukuran ${item.size}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${formatRupiah(item.price)} x ${item.quantity}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          formatRupiah(item.lineTotal),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow(
    this.label,
    this.value, {
    this.bold = false,
    this.color,
    this.plain = false,
  });

  final String label;
  final String value;
  final bool bold;
  final Color? color;

  /// `true` untuk baris informasi (tanpa penekanan harga).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 13.5 : 12.5,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                color: bold ? Colors.black : Colors.grey.shade700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: bold ? 15 : 12.5,
                fontWeight:
                    bold || !plain ? FontWeight.w700 : FontWeight.w600,
                color: color ?? Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
