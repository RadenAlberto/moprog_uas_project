import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/order_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/formatters.dart';
import '../UTILS/order_actions.dart';
import '../WIDGETS/order_widgets.dart';
import '../WIDGETS/product_image.dart';
import 'login_page.dart';
import 'order_detail_page.dart';

/// Riwayat pembelian member: ringkasan, pencarian, filter status, dan daftar
/// pesanan.
class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  OrderStatus? _filter;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AuthProvider>().refreshServerData();
    });
    // Status pesanan lokal/layar tetap diperbarui berkala.
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      title: const Text(
        'RIWAYAT PEMBELIAN',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          fontSize: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: _appBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text(
                  'Masuk untuk melihat riwayat pembelian',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEC1C24),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                  child: const Text('MASUK'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final now = DateTime.now();
    final all = auth.myOrders;

    final counts = <OrderStatus, int>{};
    for (final order in all) {
      final status = order.statusAt(now);
      counts[status] = (counts[status] ?? 0) + 1;
    }

    final query = _query.trim().toLowerCase();
    final orders = all.where((order) {
      if (_filter != null && order.statusAt(now) != _filter) return false;
      if (query.isEmpty) return true;
      return order.id.toLowerCase().contains(query) ||
          order.items.any((i) => i.name.toLowerCase().contains(query));
    }).toList();


    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: _appBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        _SummaryItem(
                          label: 'Pesanan',
                          value: '${all.length}',
                        ),
                        _divider(),
                        _SummaryItem(
                          label: 'Total belanja',
                          value: formatRupiahCompact(auth.totalTransactionSpend),
                        ),
                        _divider(),
                        _SummaryItem(
                          label: 'Total hemat',
                          value: formatRupiahCompact(auth.totalTransactionSavings),
                          valueColor: const Color(0xFF2E7D32),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Cari no. pesanan atau nama produk',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: Colors.grey),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.black54),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF2F2F2),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _FilterChip(
                        label: 'Semua (${all.length})',
                        selected: _filter == null,
                        onTap: () => setState(() => _filter = null),
                      ),
                      for (final status in OrderStatus.values)
                        _FilterChip(
                          label: '${status.label} (${counts[status] ?? 0})',
                          selected: _filter == status,
                          onTap: () => setState(() => _filter = status),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: all.isEmpty
                      ? const _EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Belum ada pesanan',
                          subtitle:
                              'Pesanan yang Anda buat saat login sebagai member akan muncul di sini.',
                        )
                      : orders.isEmpty
                          ? const _EmptyState(
                              icon: Icons.search_off,
                              title: 'Pesanan tidak ditemukan',
                              subtitle:
                                  'Coba ubah kata kunci atau filter status.',
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: orders.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                return _OrderCard(
                                  order: orders[index],
                                  now: now,
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 30, color: Colors.grey.shade200);
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: const Color(0xFFEC1C24),
        backgroundColor: const Color(0xFFF2F2F2),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide.none,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.now});

  final Order order;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final status = order.statusAt(now);
    final shown = order.items.take(3).toList();
    final extra = order.items.length - shown.length;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailPage(orderId: order.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
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
                Expanded(
                  child: Text(
                    order.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OrderStatusChip(status: status, label: order.statusLabel(status)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              formatDateTime(order.createdAt),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
            ),
            if (order.paymentStatus.toLowerCase() == 'pending') ...[
              const SizedBox(height: 6),
              const Row(children: [
                Icon(Icons.schedule, size: 14, color: Colors.orange),
                SizedBox(width: 5),
                Text('Menunggu pembayaran', style: TextStyle(
                  color: Colors.orange, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ] else if (order.paymentStatus.toLowerCase() == 'refunded') ...[
              const SizedBox(height: 6),
              const Row(children: [
                Icon(Icons.currency_exchange, size: 14, color: Colors.blueGrey),
                SizedBox(width: 5),
                Text('Dana direfund (simulasi)', style: TextStyle(
                  color: Colors.blueGrey, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ]),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                for (final item in shown)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OrderItemImage(
                      item,
                      width: 48,
                      height: 64,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                if (extra > 0)
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '+$extra',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${order.itemCount} item',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatRupiah(order.total),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: order.isCancelled
                            ? Colors.grey
                            : const Color(0xFFEC1C24),
                        decoration: order.isCancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey.shade400),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrderDetailPage(orderId: order.id),
                      ),
                    ),
                    child: const Text('Lihat Detail', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEC1C24),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => reorderItems(context, order),
                    child: const Text(
                      'Beli Lagi',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
