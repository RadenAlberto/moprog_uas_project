import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../DATA/store_data.dart';
import '../MODELS/order_model.dart';
import '../MODELS/store_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../SERVICES/api_service.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/ui_kit.dart';
import 'order_success_page.dart';

/// Toko yang dapat dipilih untuk pickup.
///
/// Sebagian data toko lama dari database belum mengisi kolom `services`
/// (nilainya `[]`). Jika seluruh metadata layanan kosong, jangan sampai
/// checkout menampilkan daftar kosong: semua toko yang tersimpan
/// di katalog server ditawarkan sebagai lokasi pickup simulasi. Jika metadata
/// layanan sudah diisi, tetap hormati pilihan layanan Pickup pesanan.
List<StoreLocation> pickupStores() {
  final hasServiceMetadata = kStores.any((s) => s.services.isNotEmpty);
  if (!hasServiceMetadata) return List<StoreLocation>.of(kStores);
  return kStores
      .where((s) => s.services.contains('Pickup pesanan'))
      .toList();
}

/// Perkiraan pesanan siap diambil: 2 jam setelah [now], dalam jam buka toko.
DateTime pickupReadyEstimate(StoreLocation store, DateTime now) {
  var t = now.add(const Duration(hours: 2));
  final open = DateTime(t.year, t.month, t.day, store.openHour);
  final close = DateTime(t.year, t.month, t.day, store.closeHour);
  if (t.isBefore(open)) return open.add(const Duration(hours: 1));
  if (!t.isBefore(close)) {
    final next = open.add(const Duration(days: 1, hours: 1));
    return next;
  }
  return t;
}

/// Setelah bayar: pilih ambil di toko atau diantar ke alamat.
class FulfillmentPage extends StatefulWidget {
  const FulfillmentPage({super.key, required this.orderId});

  final String orderId;

  @override
  State<FulfillmentPage> createState() => _FulfillmentPageState();
}

class _FulfillmentPageState extends State<FulfillmentPage> {
  static const String _deliveryService = 'Reguler (2-4 hari kerja)';

  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;

  String _type = kFulfillPickup;
  String? _storeId;
  String _city = 'Semua';
  List<Map<String, dynamic>> _savedAddresses = [];
  int? _selectedAddressId;
  bool _saving = false;
  bool _loadingAddresses = false;

  @override
  void initState() {
    super.initState();
    final order = context.read<AuthProvider>().myOrders.firstWhere(
          (o) => o.id == widget.orderId,
        );
    _name = TextEditingController(text: order.recipient);
    _phone = TextEditingController(text: order.phone);
    _address = TextEditingController(text: order.address);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _loadSavedAddresses(); });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Order? _order(AuthProvider auth) {
    for (final o in auth.myOrders) {
      if (o.id == widget.orderId) return o;
    }
    return null;
  }

  Future<void> _loadSavedAddresses() async {
    if (!mounted) return;
    setState(() => _loadingAddresses = true);
    final rows = await context.read<ApiService>().fetchAddresses();
    if (!mounted) return;
    setState(() {
      _savedAddresses = rows ?? [];
      _loadingAddresses = false;
      if (_selectedAddressId == null && _savedAddresses.isNotEmpty) {
        final selected = _savedAddresses.firstWhere(
          (a) => a['is_default'] == true || a['is_default'] == 1,
          orElse: () => _savedAddresses.first,
        );
        _selectedAddressId = (selected['id'] as num?)?.toInt();
        _applyAddress(selected);
      }
    });
  }

  void _applyAddress(Map<String, dynamic> item) {
    _selectedAddressId = (item['id'] as num?)?.toInt();
    _name.text = (item['recipient_name'] ?? '').toString();
    _phone.text = (item['phone'] ?? '').toString();
    _address.text = [
      item['address'], item['city'], item['postal_code']
    ].where((v) => v != null && v.toString().trim().isNotEmpty)
      .map((v) => v.toString().trim()).join(', ');
  }

  Future<void> _editAddress([Map<String, dynamic>? current]) async {
    final api = context.read<ApiService>();
    final label = TextEditingController(text: (current?['label'] ?? 'Rumah').toString());
    final name = TextEditingController(text: (current?['recipient_name'] ?? _name.text).toString());
    final phone = TextEditingController(text: (current?['phone'] ?? _phone.text).toString());
    final address = TextEditingController(text: (current?['address'] ?? _address.text).toString());
    final city = TextEditingController(text: (current?['city'] ?? '').toString());
    final postal = TextEditingController(text: (current?['postal_code'] ?? '').toString());
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(current == null ? 'Tambah alamat' : 'Edit alamat'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: label, decoration: const InputDecoration(labelText: 'Label')),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama penerima')),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nomor HP')),
        TextField(controller: address, minLines: 2, maxLines: 3, decoration: const InputDecoration(labelText: 'Alamat lengkap')),
        TextField(controller: city, decoration: const InputDecoration(labelText: 'Kota')),
        TextField(controller: postal, decoration: const InputDecoration(labelText: 'Kode pos')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
      ],
    ));
    if (ok == true) {
      final saved = await api.saveAddress(
        id: (current?['id'] as num?)?.toInt(),
        recipientName: name.text.trim(), phone: phone.text.trim(),
        address: address.text.trim(), city: city.text.trim(),
        postalCode: postal.text.trim(), label: label.text.trim(),
        isDefault: current?['is_default'] == true || current?['is_default'] == 1 || _savedAddresses.isEmpty,
      );
      if (saved != null) {
        await _loadSavedAddresses();
        final id = (current?['id'] as num?)?.toInt() ?? (saved['id'] as num?)?.toInt();
        if (id != null) {
          final found = _savedAddresses.where((a) => (a['id'] as num?)?.toInt() == id).toList();
          if (found.isNotEmpty) setState(() => _applyAddress(found.first));
        }
      } else if (mounted) {
        showAppToast(context, 'Alamat gagal disimpan. Periksa koneksi dan data.', color: Colors.red);
      }
    }
    label.dispose(); name.dispose(); phone.dispose(); address.dispose(); city.dispose(); postal.dispose();
  }

  Future<void> _confirm(Order order) async {
    final auth = context.read<AuthProvider>();
    final nav = Navigator.of(context);

    if (_type == kFulfillPickup) {
      if (_storeId == null) {
        showAppToast(
          context,
          'Pilih toko pengambilan dulu',
          color: Colors.red.shade700,
          icon: Icons.error_outline,
        );
        return;
      }
    } else {
      if (_selectedAddressId == null) {
        showAppToast(context, 'Pilih atau tambahkan alamat pengiriman terlebih dahulu.', color: Colors.red);
        return;
      }
    }

    setState(() => _saving = true);
    StoreLocation? store;
    for (final s in kStores) {
      if (s.id == _storeId) store = s;
    }
    final updated = await auth.setFulfillment(
      order.id,
      type: _type,
      storeId: store?.id,
      storeName: store?.name,
      storeAddress: store?.address,
      deliveryService: _deliveryService,
      addressId: _type == kFulfillDelivery ? _selectedAddressId : null,
      recipient: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
    );
    if (!mounted) return;
    if (updated == null) {
      setState(() => _saving = false);
      final reason = context.read<ApiService>().lastOperationError;
      showAppToast(
        context,
        reason ?? 'Pilihan penerimaan gagal disimpan. Periksa sesi dan koneksi server.',
        color: Colors.red.shade700,
        icon: Icons.error_outline,
      );
      return;
    }
    await nav.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => OrderSuccessPage(orderId: order.id),
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pilih nanti?'),
        content: const Text(
          'Pembayaran sudah diterima. Anda bisa memilih ambil di toko atau '
          'diantar kapan saja dari Detail Pesanan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Pilih sekarang'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Nanti saja'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ApiService>(); // pilihan pickup mengikuti toko di database
    final auth = context.watch<AuthProvider>();
    final order = _order(auth);
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Penerimaan Pesanan')),
        body: const Center(child: Text('Pesanan tidak ditemukan')),
      );
    }
    final refund = order.shippingFee - order.shippingDiscount;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.popUntil((r) => r.isFirst);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Penerimaan Pesanan')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SurfaceCard(
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pembayaran ${order.id} diterima. '
                          'Bagaimana Anda ingin menerima pesanan?',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _OptionCard(
                        icon: Icons.storefront_outlined,
                        title: 'Ambil di Toko',
                        subtitle: 'Gratis ongkir',
                        selected: _type == kFulfillPickup,
                        onTap: () => setState(() => _type = kFulfillPickup),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _OptionCard(
                        icon: Icons.local_shipping_outlined,
                        title: 'Diantar',
                        subtitle: 'Ke alamat Anda',
                        selected: _type == kFulfillDelivery,
                        onTap: () => setState(() => _type = kFulfillDelivery),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_type == kFulfillPickup)
                  _pickupSection(refund)
                else
                  _deliverySection(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _saving ? null : () => _confirm(order),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_type == kFulfillPickup
                            ? 'KONFIRMASI AMBIL DI TOKO'
                            : 'KONFIRMASI PENGIRIMAN'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickupSection(double refund) {
    final all = pickupStores();
    final cities = ['Semua', ...{for (final s in all) s.city}];
    final stores =
        all.where((s) => _city == 'Semua' || s.city == _city).toList();
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (refund > 0)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.undo, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ongkir ${formatRupiah(refund)} yang sudah dibayar '
                    'dikembalikan bila Anda ambil di toko.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in cities)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c),
                    selected: _city == c,
                    onSelected: (_) => setState(() => _city = c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final store in stores)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: cardDecoration(radius: 12).copyWith(
              border: Border.all(
                color: _storeId == store.id ? AppColors.red : AppColors.line,
                width: _storeId == store.id ? 1.6 : 1,
              ),
            ),
            child: ListTile(
              onTap: () => setState(() => _storeId = store.id),
              leading: Icon(
                _storeId == store.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: _storeId == store.id ? AppColors.red : AppColors.muted,
              ),
              title: Text(
                store.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${store.address}\n'
                '${store.isOpenAt(now) ? 'Buka' : 'Tutup'} · ${store.hoursLabel}'
                '  |  Siap diambil ± ${formatDateTime(pickupReadyEstimate(store, now))}',
                style: const TextStyle(fontSize: 12, height: 1.35),
              ),
              isThreeLine: true,
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Bawa kode ambil dan identitas. Pesanan disimpan 7 hari di toko.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _deliverySection() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pilih alamat pengiriman',
            style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (_loadingAddresses)
            const Center(child: Padding(
              padding: EdgeInsets.all(18), child: CircularProgressIndicator()))
          else if (_savedAddresses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Belum ada alamat tersimpan. Tambahkan alamat terlebih dahulu.'),
            )
          else
            for (final item in _savedAddresses)
              Card(
                elevation: 0,
                color: _selectedAddressId == (item['id'] as num?)?.toInt()
                    ? AppColors.redSoft : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: _selectedAddressId == (item['id'] as num?)?.toInt()
                        ? AppColors.red : AppColors.line,
                  ),
                ),
                child: ListTile(
                  onTap: () => setState(() => _applyAddress(item)),
                  leading: Radio<int>(
                    value: (item['id'] as num).toInt(),
                    groupValue: _selectedAddressId,
                    onChanged: (_) => setState(() => _applyAddress(item)),
                  ),
                  title: Text(
                    '${item['label'] ?? 'Alamat'}${item['is_default'] == true || item['is_default'] == 1 ? ' • Utama' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${item['recipient_name']} • ${item['phone']}\n${item['address']}, ${item['city'] ?? ''} ${item['postal_code'] ?? ''}',
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    tooltip: 'Edit alamat',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editAddress(item),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _editAddress(),
            icon: const Icon(Icons.add),
            label: const Text('Tambah alamat baru'),
          ),
          const SizedBox(height: 8),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.local_shipping_outlined),
            title: Text(_deliveryService),
            subtitle: Text('Ongkir sudah termasuk dalam pembayaran'),
          ),
        ],
      ),
    );
  }

}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.redSoft : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.red : AppColors.line,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: selected ? AppColors.red : AppColors.ink),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(
              subtitle,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
