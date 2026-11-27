import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../DATA/store_data.dart';
import '../MODELS/store_model.dart';
import '../SERVICES/api_service.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/external_link.dart';
import '../WIDGETS/ui_kit.dart';

/// Pencari toko (data contoh). Tombol "Buka peta" membuka Google Maps.
class StoreLocatorPage extends StatefulWidget {
  const StoreLocatorPage({super.key});

  @override
  State<StoreLocatorPage> createState() => _StoreLocatorPageState();
}

class _StoreLocatorPageState extends State<StoreLocatorPage> {
  String _query = '';
  bool _openOnly = false;

  @override
  Widget build(BuildContext context) {
    context.watch<ApiService>(); // perbarui daftar toko dari database
    final now = DateTime.now();
    final query = _query.trim().toLowerCase();

    final stores = kStores.where((store) {
      if (_openOnly && !store.isOpenAt(now)) return false;
      if (query.isEmpty) return true;
      return store.name.toLowerCase().contains(query) ||
          store.city.toLowerCase().contains(query) ||
          store.mall.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('TEMUKAN TOKO')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Cari nama mal atau kota',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${stores.length} toko',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      const Text('Buka sekarang',
                          style: TextStyle(fontSize: 12.5)),
                      Switch(
                        value: _openOnly,
                        onChanged: (value) => setState(() => _openOnly = value),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Daftar toko disinkronkan dari database server saat koneksi tersedia.',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ),
                ),
                Expanded(
                  child: stores.isEmpty
                      ? const EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'Toko tidak ditemukan',
                          message: 'Coba kata kunci lain.',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          itemCount: stores.length,
                          itemBuilder: (context, index) =>
                              _StoreTile(store: stores[index], now: now),
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

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.store, required this.now});

  final StoreLocation store;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final open = store.isOpenAt(now);

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.storefront_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      store.city,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              PillTag(
                label: open ? 'BUKA' : 'TUTUP',
                color: (open ? AppColors.success : AppColors.muted)
                    .withValues(alpha: 0.12),
                textColor: open ? AppColors.success : AppColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            store.address,
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 4),
          Text(
            'Jam buka ${store.hoursLabel}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (store.services.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final service in store.services)
                  PillTag(
                    label: service,
                    color: AppColors.bg,
                    textColor: AppColors.ink,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => openExternalUrl(
                context,
                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeQueryComponent(store.mapsQuery)}',
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('Buka peta'),
            ),
          ),
        ],
      ),
    );
  }
}
