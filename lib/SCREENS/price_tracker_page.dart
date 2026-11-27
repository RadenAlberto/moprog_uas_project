import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/tracker_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../UTILS/nav.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/app_network_image.dart';
import '../WIDGETS/studio_widgets.dart';
import '../WIDGETS/ui_kit.dart';
import 'detailproduk_uniqlo.dart';

/// Sheet untuk mulai melacak [product] pada ukuran [size].
Future<void> showTrackSheet(
  BuildContext context,
  Product product, {
  required String size,
  Color? color,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _TrackSheet(product: product, size: size, color: color),
  );
}

class _TrackSheet extends StatefulWidget {
  const _TrackSheet({required this.product, required this.size, this.color});

  final Product product;
  final String size;
  final Color? color;

  @override
  State<_TrackSheet> createState() => _TrackSheetState();
}

class _TrackSheetState extends State<_TrackSheet> {
  late String _size = widget.size;
  final TextEditingController _target = TextEditingController();

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  void _save() {
    final digits = _target.text.replaceAll(RegExp(r'[^0-9]'), '');
    final target = digits.isEmpty ? null : double.tryParse(digits);
    context.read<TrackerProvider>().track(
          widget.product,
          _size,
          color: widget.color,
          targetPrice: target,
        );
    Navigator.of(context).pop();
    showAppToast(
      context,
      'Dilacak. Kamu akan dikabari saat harga turun atau stok kembali.',
      icon: Icons.notifications_active_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final tracked = context.watch<TrackerProvider>().isTracked(p.id, _size);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Lacak harga & stok',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${p.name} • harga sekarang ${p.formattedPrice}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            const Text('Ukuran', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final s in p.availableSizes)
                  ChoiceChip(
                    label: Text(s),
                    selected: _size == s,
                    onSelected: (_) => setState(() => _size = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Harga target (opsional)',
                helperText: 'Kosongkan untuk dikabari setiap harga turun.',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (tracked)
              OutlinedButton(
                onPressed: () {
                  context.read<TrackerProvider>().untrack(p.id, _size);
                  Navigator.of(context).pop();
                },
                child: const Text('Berhenti melacak ukuran ini'),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _save,
              child: Text(tracked ? 'PERBARUI PELACAKAN' : 'MULAI LACAK'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Daftar produk yang dilacak dan notifikasinya.
class PriceTrackerPage extends StatelessWidget {
  const PriceTrackerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final unread = context.select<TrackerProvider, int>((t) => t.unreadCount);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PELACAK HARGA'),
          bottom: TabBar(
            labelColor: AppColors.red,
            indicatorColor: AppColors.red,
            tabs: [
              const Tab(text: 'Dilacak'),
              Tab(text: unread > 0 ? 'Notifikasi ($unread)' : 'Notifikasi'),
            ],
          ),
        ),
        body: const TabBarView(children: [_TrackedTab(), _AlertsTab()]),
      ),
    );
  }
}

class _TrackedTab extends StatelessWidget {
  const _TrackedTab();

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TrackerProvider>();
    final app = context.read<AppState>();
    final items = tracker.items;

    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_active_outlined,
        title: 'Belum ada produk dilacak',
        message: 'Buka detail produk lalu ketuk "Lacak harga" untuk dikabari '
            'saat harganya turun atau ukuranmu tersedia lagi.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tracker.lastChecked == null
                    ? 'Dicek otomatis saat aplikasi terbuka.'
                    : 'Terakhir dicek ${formatTimeShort(tracker.lastChecked!)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
              ),
            ),
            OutlinedButton.icon(
              onPressed: tracker.checking ? null : tracker.refreshAndCheck,
              icon: tracker.checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('Cek sekarang'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final item in items)
          _TrackedCard(item: item, product: app.productById(item.productId)),
        const SizedBox(height: 8),
        if (items.isNotEmpty) _DemoPanel(item: items.first),
      ],
    );
  }
}

String formatTimeShort(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class _TrackedCard extends StatelessWidget {
  const _TrackedCard({required this.item, required this.product});

  final TrackedItem item;
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final dropped = item.lastPrice < item.startPrice;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: cardDecoration(radius: 14, border: true, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: p == null ? null : () => pushPage(context, ProductDetailPage(product: p)),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 72,
                  child: AppNetworkImage(
                    p?.imageFor(item.colorArgb == null ? null : Color(item.colorArgb!)) ?? '',
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p?.name ?? item.productId,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            formatRupiah(item.lastPrice),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: dropped ? AppColors.success : AppColors.ink,
                            ),
                          ),
                          if (dropped) ...[
                            const SizedBox(width: 6),
                            Text(
                              formatRupiah(item.startPrice),
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          PillTag(label: 'Ukuran ${item.size}', color: Colors.black87),
                          PillTag(
                            label: item.sizeAvailable ? 'Stok ada' : 'Habis',
                            color: item.sizeAvailable ? AppColors.success : AppColors.muted,
                          ),
                          if (item.targetPrice != null)
                            PillTag(
                              label: 'Target ${formatRupiah(item.targetPrice!)}',
                              color: AppColors.red,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PriceSparkline(values: [for (final h in item.history) h.price]),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: p == null
                    ? null
                    : () => showTrackSheet(
                          context,
                          p,
                          size: item.size,
                          color: item.colorArgb == null ? null : Color(item.colorArgb!),
                        ),
                child: const Text('Ubah target'),
              ),
              TextButton(
                onPressed: () =>
                    context.read<TrackerProvider>().untrack(item.productId, item.size),
                child: const Text('Hapus', style: TextStyle(color: AppColors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Simulasi perubahan harga/stok agar notifikasi bisa didemokan.
class _DemoPanel extends StatelessWidget {
  const _DemoPanel({required this.item});

  final TrackedItem item;

  @override
  Widget build(BuildContext context) {
    final tracker = context.read<TrackerProvider>();
    return Container(
      decoration: cardDecoration(radius: 14, color: const Color(0xFFFFFBEA), shadow: false, border: true),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('Mode demo', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: const Text(
          'Simulasi perubahan pada produk pertama di daftar (data asli tidak berubah).',
          style: TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.trending_down, size: 16),
                label: const Text('Harga turun 20%'),
                onPressed: () => tracker.simulate(item, TrackerSimulation.priceDrop),
              ),
              ActionChip(
                avatar: const Icon(Icons.remove_shopping_cart_outlined, size: 16),
                label: const Text('Ukuran habis'),
                onPressed: () => tracker.simulate(item, TrackerSimulation.soldOut),
              ),
              ActionChip(
                avatar: const Icon(Icons.inventory_2_outlined, size: 16),
                label: const Text('Stok kembali'),
                onPressed: () => tracker.simulate(item, TrackerSimulation.restock),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertsTab extends StatelessWidget {
  const _AlertsTab();

  @override
  Widget build(BuildContext context) {
    final tracker = context.watch<TrackerProvider>();
    final alerts = tracker.alerts;
    if (alerts.isEmpty) {
      return const EmptyState(
        icon: Icons.notifications_none,
        title: 'Belum ada notifikasi',
        message: 'Kabar penurunan harga dan stok kembali muncul di sini.',
      );
    }
    final app = context.read<AppState>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              const Spacer(),
              TextButton(onPressed: tracker.markAllRead, child: const Text('Tandai dibaca')),
              TextButton(onPressed: tracker.clearAlerts, child: const Text('Hapus semua')),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: alerts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = alerts[i];
              final time = DateTime.fromMillisecondsSinceEpoch(a.at);
              return ListTile(
                tileColor: a.read ? null : AppColors.redSoft,
                leading: CircleAvatar(
                  backgroundColor: a.kind.color,
                  child: Icon(a.kind.icon, color: Colors.white, size: 20),
                ),
                title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${a.body}\n${formatTimeShort(time)}'),
                isThreeLine: true,
                onTap: () {
                  tracker.markRead(a.id);
                  final p = app.productById(a.productId);
                  if (p != null) pushPage(context, ProductDetailPage(product: p));
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
