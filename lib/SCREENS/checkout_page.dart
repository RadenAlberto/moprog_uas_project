import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../DATA/voucher_data.dart';
import '../MODELS/member_model.dart';
import '../MODELS/pricing.dart';
import '../MODELS/voucher_model.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../SERVICES/payment_gateway.dart';
import '../SERVICES/api_service.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../UTILS/toast.dart';
import '../UTILS/validators.dart';
import '../WIDGETS/product_image.dart';
import '../WIDGETS/ui_kit.dart';
import 'fulfillment_page.dart';
import 'payment_gateway_page.dart';

class _PaymentMethod {
  const _PaymentMethod(this.id, this.name, this.icon, this.group);

  /// Disimpan pada pesanan. Metode COD harus diawali "COD" (lihat
  /// `isCashOnDelivery`).
  final String id;
  final String name;
  final IconData icon;
  final String group;
}

const List<_PaymentMethod> _paymentMethods = [
  _PaymentMethod(
    'Virtual Account BCA',
    'Virtual Account BCA',
    Icons.account_balance,
    'Transfer Bank',
  ),
  _PaymentMethod(
    'Mandiri Virtual Account',
    'Virtual Account Mandiri',
    Icons.account_balance,
    'Transfer Bank',
  ),
  _PaymentMethod(
    'QRIS / GoPay / OVO',
    'QRIS / E-Wallet (GoPay, OVO, ShopeePay)',
    Icons.qr_code_scanner,
    'E-Wallet & QRIS',
  ),
  _PaymentMethod(
    'Kartu Kredit / Debit',
    'Kartu Kredit / Debit (Visa/Mastercard)',
    Icons.credit_card,
    'Kartu',
  ),
  _PaymentMethod(
    'COD (Bayar di Tempat)',
    'COD (Bayar di Tempat)',
    Icons.payments_outlined,
    'Tunai',
  ),
];

/// Checkout: alamat, metode bayar, voucher, poin, lalu simpan pesanan.
/// Halaman ini dibuka setelah pengguna login (lihat `requireMember`).
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  final TextEditingController _voucherController = TextEditingController();

  String _paymentMethod = _paymentMethods.first.id;
  Voucher? _voucher;
  String? _voucherError;
  bool _usePoints = false;
  bool _submitting = false;
  List<Map<String, dynamic>> _savedAddresses = [];
  int? _selectedAddressId;

  @override
  void initState() {
    super.initState();
    final member = context.read<AuthProvider>().currentMember;
    _nameController = TextEditingController(text: member?.name ?? '');
    _phoneController = TextEditingController(text: member?.phone ?? '');
    _addressController = TextEditingController(text: member?.address ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _loadSavedAddresses(); });
  }

  Future<void> _loadSavedAddresses() async {
    if (!mounted) return;
    final rows = await context.read<ApiService>().fetchAddresses();
    if (!mounted || rows == null) return;
    setState(() => _savedAddresses = rows);
    final selectedStillExists = _selectedAddressId != null &&
        rows.any((x) => (x['id'] as num?)?.toInt() == _selectedAddressId);
    if (!selectedStillExists) {
      _selectedAddressId = null;
      if (rows.isNotEmpty) {
        final selected = rows.firstWhere(
          (x) => x['is_default'] == true || x['is_default'] == 1,
          orElse: () => rows.first,
        );
        _applySavedAddress(selected);
      }
    }
  }

  void _applySavedAddress(Map<String, dynamic> item) {
    setState(() {
      _selectedAddressId = (item['id'] as num?)?.toInt();
      _nameController.text = (item['recipient_name'] ?? '').toString();
      _phoneController.text = (item['phone'] ?? '').toString();
      final parts = [item['address'], item['city'], item['postal_code']]
          .where((x) => x != null && x.toString().trim().isNotEmpty)
          .map((x) => x.toString().trim()).toList();
      _addressController.text = parts.join(', ');
    });
  }

  Future<void> _editSavedAddress([Map<String, dynamic>? current]) async {
    final api = context.read<ApiService>();
    final name = TextEditingController(text: (current?['recipient_name'] ?? _nameController.text).toString());
    final phone = TextEditingController(text: (current?['phone'] ?? _phoneController.text).toString());
    final address = TextEditingController(text: (current?['address'] ?? _addressController.text).toString());
    final city = TextEditingController(text: (current?['city'] ?? '').toString());
    final postal = TextEditingController(text: (current?['postal_code'] ?? '').toString());
    final label = TextEditingController(text: (current?['label'] ?? 'Rumah').toString());
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(current == null ? 'Tambah alamat' : 'Edit alamat'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: label, decoration: const InputDecoration(labelText: 'Label alamat')),
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Nama penerima')),
        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nomor HP')),
        TextField(controller: address, maxLines: 2, decoration: const InputDecoration(labelText: 'Alamat lengkap')),
        TextField(controller: city, decoration: const InputDecoration(labelText: 'Kota')),
        TextField(controller: postal, decoration: const InputDecoration(labelText: 'Kode pos')),
      ])),
      actions: [TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Batal')),
        FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Simpan'))],
    ));
    if (result == true) {
      final saved = await api.saveAddress(id: (current?['id'] as num?)?.toInt(),
        recipientName: name.text.trim(), phone: phone.text.trim(), address: address.text.trim(),
        city: city.text.trim(), postalCode: postal.text.trim(), label: label.text.trim(),
        isDefault: current?['is_default'] == true || current?['is_default'] == 1 || _savedAddresses.isEmpty);
      if (saved != null) {
        await _loadSavedAddresses();
        final savedId = (saved['id'] as num?)?.toInt();
        if (savedId != null) {
          final matches = _savedAddresses.where((x) => (x['id'] as num?)?.toInt() == savedId).toList();
          if (matches.isNotEmpty) _applySavedAddress(matches.first);
        }
      }
    }
    name.dispose(); phone.dispose(); address.dispose(); city.dispose(); postal.dispose(); label.dispose();
  }

  Future<void> _openAddressBook() async {
    await _loadSavedAddresses();
    if (!mounted) return;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16), child: SizedBox(height: 420, child: Column(children: [
          Row(children: [const Expanded(child: Text('Alamat tersimpan',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
            IconButton(onPressed:()=>Navigator.pop(sheetContext),icon:const Icon(Icons.close))]),
          Expanded(child: _savedAddresses.isEmpty ? const Center(child:Text('Belum ada alamat tersimpan.')) : ListView.builder(
            itemCount:_savedAddresses.length,itemBuilder:(context,index){final a=_savedAddresses[index];
              final isDefault=a['is_default']==true||a['is_default']==1;
              return ListTile(title:Text('${a['label']??'Alamat'}${isDefault?' • Utama':''}'),
                subtitle:Text('${a['recipient_name']} • ${a['phone']}\n${a['address']}, ${a['city']??''} ${a['postal_code']??''}'),
                isThreeLine:true, onTap:(){_applySavedAddress(a);Navigator.pop(sheetContext);},
                trailing:PopupMenuButton<String>(onSelected:(v)async{
                  final api=context.read<ApiService>(); final id=(a['id'] as num).toInt();
                  if(v=='default'){await api.setDefaultAddress(id);await _loadSavedAddresses();}
                  if(v=='edit'){Navigator.pop(sheetContext);await _editSavedAddress(a);}
                  if(v=='delete'){await api.deleteAddress(id);await _loadSavedAddresses();}
                },itemBuilder:(_)=>[const PopupMenuItem(value:'default',child:Text('Jadikan utama')),
                  const PopupMenuItem(value:'edit',child:Text('Edit')),
                  const PopupMenuItem(value:'delete',child:Text('Hapus'))]),
              );}),),
          SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:(){Navigator.pop(sheetContext);_editSavedAddress();},icon:const Icon(Icons.add),label:const Text('Tambah alamat baru'))),
        ])))));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _voucherController.dispose();
    super.dispose();
  }

  void _applyVoucher(String rawCode, double subtotal) {
    final auth = context.read<AuthProvider>();
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _voucherError = 'Masukkan kode voucher');
      return;
    }

    Voucher? found;
    for (final candidate in kVouchers) {
      if (candidate.code.toUpperCase() == code) {
        found = candidate;
        break;
      }
    }
    final voucher = found;
    if (voucher == null) {
      setState(() => _voucherError = 'Kode voucher tidak ditemukan');
      return;
    }

    final error = voucher.validate(
      subtotal: subtotal,
      isMember: auth.isLoggedIn,
      tier: auth.tier,
    );
    setState(() {
      if (error != null) {
        _voucherError = error;
      } else {
        _voucher = voucher;
        _voucherError = null;
        _voucherController.clear();
      }
    });
  }

  Future<void> _pay(PriceBreakdown price) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    // Checkout harus memakai alamat yang sudah tersimpan dan dipilih.
    // Jangan membuat alamat baru otomatis karena dapat menggandakan baris.
    final api = context.read<ApiService>();
    if (api.hasSession && _selectedAddressId == null) {
      showAppToast(context,
        'Pilih alamat tersimpan atau tambahkan alamat melalui Buku Alamat sebelum membayar.',
        color: Colors.red.shade700, icon: Icons.location_on_outlined);
      await _openAddressBook();
      return;
    }

    // 1. Bayar lewat payment gateway (COD tidak lewat gateway).
    String? gatewayRef;
    String? paymentInfo;
    if (gatewayChannelFor(_paymentMethod) != null) {
      final result = await navigator.push<GatewayResult>(
        MaterialPageRoute<GatewayResult>(
          builder: (_) => PaymentGatewayPage(
            method: _paymentMethod,
            amount: price.total,
            orderRef: auth.newOrderId(),
          ),
        ),
      );
      if (!mounted) return;
      if (result == null || !result.ok) {
        showAppToast(
          context,
          'Pembayaran dibatalkan. Keranjang Anda tetap tersimpan.',
          color: Colors.orange.shade800,
          icon: Icons.info_outline,
        );
        return;
      }
      gatewayRef = result.reference;
      paymentInfo = result.info;
    }

    // 2. Pembayaran berhasil: simpan pesanan.
    setState(() => _submitting = true);
    final order = await auth.placeOrder(
      items: appState.checkedCartItems,
      pricing: price,
      paymentMethod: _paymentMethod,
      recipient: _nameController.text,
      phone: _phoneController.text,
      address: _addressController.text,
      addressId: _selectedAddressId,
      voucher: _voucher,
      gatewayRef: gatewayRef,
      paymentInfo: paymentInfo,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (order == null) {
      showAppToast(
        context,
        gatewayRef == null
            ? 'Pesanan gagal dibuat. Pastikan Anda sudah masuk sebagai member.'
            : 'Pembayaran diterima (ref $gatewayRef) tetapi pesanan gagal '
                'disimpan. Hubungi layanan pelanggan.',
        color: Colors.red.shade700,
        icon: Icons.error_outline,
      );
      return;
    }

    appState.clearCheckedCart();

    // 3. Pilih ambil di toko / diantar, lalu layar sukses. Tidak ada
    // popUntil ke beranda: pembeli yang memutuskan langkah berikutnya.
    await navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => FulfillmentPage(orderId: order.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ApiService>(); // refresh daftar voucher dari server
    final appState = context.watch<AppState>();
    final auth = context.watch<AuthProvider>();
    final items = appState.checkedCartItems;
    final subtotal = appState.selectedCartTotal;

    final price = calculatePrice(
      subtotal: subtotal,
      isMember: auth.isLoggedIn,
      tier: auth.tier,
      voucher: _voucher,
      pointsToUse: _usePoints ? auth.points : 0,
      pointsAvailable: auth.points,
    );

    // Voucher yang sudah dipasang bisa tidak berlaku lagi bila isi keranjang berubah.
    final voucherWarning = _voucher?.validate(
      subtotal: subtotal,
      isMember: auth.isLoggedIn,
      tier: auth.tier,
    );

    final eligibleVouchers = kVouchers
        .where((v) =>
            v.validate(
              subtotal: subtotal,
              isMember: auth.isLoggedIn,
              tier: auth.tier,
            ) ==
            null)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('CHECKOUT & PEMBAYARAN')),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.shopping_cart_outlined,
              title: 'Tidak ada produk yang dipilih',
              message: 'Pilih produk di keranjang terlebih dahulu.',
              actionLabel: 'Kembali ke Keranjang',
              onAction: () => Navigator.of(context).pop(),
            )
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _Section(
                          title: 'Alamat Pengiriman',
                          icon: Icons.location_on_outlined,
                          child: Column(
                            children: [
                              Row(children: [
                                Expanded(child: TextButton.icon(
                                  onPressed: _openAddressBook,
                                  icon: const Icon(Icons.bookmark_outline),
                                  label: const Text('Pilih alamat tersimpan'),
                                )),
                                TextButton.icon(onPressed: _editSavedAddress,
                                  icon: const Icon(Icons.add), label: const Text('Tambah')),
                              ]),
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Nama penerima',
                                ),
                                validator: (v) =>
                                    Validators.notEmpty(v, 'Nama penerima'),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Nomor HP',
                                ),
                                validator: Validators.phone,
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _addressController,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: 'Alamat lengkap',
                                ),
                                validator: (v) {
                                  final empty =
                                      Validators.notEmpty(v, 'Alamat');
                                  if (empty != null) return empty;
                                  if (v!.trim().length < 10) {
                                    return 'Alamat terlalu singkat';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Section(
                          title: 'Ringkasan Pesanan (${items.length} item)',
                          icon: Icons.shopping_bag_outlined,
                          child: Column(
                            children: [
                              for (final item in items)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      ProductImage(
                                        item.product,
                                        color: item.selectedColor,
                                        width: 48,
                                        height: 64,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.product.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                            Text(
                                              'Ukuran ${item.selectedSize}  |  Qty ${item.quantity}',
                                              style: const TextStyle(
                                                color: AppColors.muted,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        formatRupiah(item.lineTotal),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Section(
                          title: 'Metode Pembayaran',
                          icon: Icons.payment,
                          child: Column(
                            children: [
                              for (final method in _paymentMethods)
                                _MethodTile(
                                  method: method,
                                  selected: _paymentMethod == method.id,
                                  onTap: () =>
                                      setState(() => _paymentMethod = method.id),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Section(
                          title: 'Voucher & Poin',
                          icon: Icons.local_offer_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_voucher != null)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.check_circle,
                                      color: AppColors.success),
                                  title: Text(
                                    _voucher!.code,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    voucherWarning ?? _voucher!.benefitLabel,
                                    style: TextStyle(
                                      color: voucherWarning == null
                                          ? AppColors.muted
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                  trailing: TextButton(
                                    onPressed: () =>
                                        setState(() => _voucher = null),
                                    child: const Text('Hapus'),
                                  ),
                                )
                              else ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _voucherController,
                                        textCapitalization:
                                            TextCapitalization.characters,
                                        decoration: InputDecoration(
                                          labelText: 'Kode voucher',
                                          errorText: _voucherError,
                                        ),
                                        onSubmitted: (value) =>
                                            _applyVoucher(value, subtotal),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.ink,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => _applyVoucher(
                                          _voucherController.text,
                                          subtotal,
                                        ),
                                        child: const Text('PAKAI'),
                                      ),
                                    ),
                                  ],
                                ),
                                if (eligibleVouchers.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      for (final voucher in eligibleVouchers)
                                        ActionChip(
                                          avatar: const Icon(
                                            Icons.local_offer,
                                            size: 14,
                                            color: AppColors.red,
                                          ),
                                          label: Text(voucher.code),
                                          backgroundColor: AppColors.redSoft,
                                          side: BorderSide.none,
                                          onPressed: () => _applyVoucher(
                                            voucher.code,
                                            subtotal,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                              const Divider(height: 24),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _usePoints,
                                onChanged: auth.points <= 0
                                    ? null
                                    : (value) =>
                                        setState(() => _usePoints = value),
                                title: Text(
                                  'Pakai poin (saldo ${auth.points} poin)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                subtitle: Text(
                                  '1 poin = ${formatRupiah(PricingRules.pointValue)}, '
                                  'maksimal ${(PricingRules.maxPointsShare * 100).round()}% dari belanja',
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _Section(
                          title: 'Rincian Pembayaran',
                          icon: Icons.receipt_long_outlined,
                          child: Column(
                            children: [
                              _CostRow('Subtotal produk',
                                  formatRupiah(price.subtotal)),
                              if (price.memberDiscount > 0)
                                _CostRow(
                                  'Diskon member (${auth.tier.label})',
                                  '-${formatRupiah(price.memberDiscount)}',
                                  positive: true,
                                ),
                              if (price.voucherDiscount > 0)
                                _CostRow(
                                  'Voucher ${_voucher?.code ?? ''}',
                                  '-${formatRupiah(price.voucherDiscount)}',
                                  positive: true,
                                ),
                              if (price.pointsDiscount > 0)
                                _CostRow(
                                  'Poin (${price.pointsUsed} poin)',
                                  '-${formatRupiah(price.pointsDiscount)}',
                                  positive: true,
                                ),
                              _CostRow('Ongkos kirim',
                                  formatRupiah(price.shippingFee)),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Setelah bayar, pilih ambil di toko '
                                    '(ongkir dikembalikan) atau diantar.',
                                    style: TextStyle(
                                      color: AppColors.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              if (price.shippingDiscount > 0)
                                _CostRow(
                                  'Gratis ongkir',
                                  '-${formatRupiah(price.shippingDiscount)}',
                                  positive: true,
                                ),
                              const Divider(height: 20),
                              _CostRow(
                                'Total pembayaran',
                                formatRupiah(price.total),
                                bold: true,
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Anda akan mendapat ${price.pointsEarned} poin dari pesanan ini.',
                                  style: const TextStyle(
                                    color: AppColors.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _submitting
                                ? null
                                : () => _pay(price),
                            child: _submitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'BAYAR ${formatRupiah(price.total)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
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
      decoration: cardDecoration(radius: 12, border: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
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

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final _PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: selected ? AppColors.redSoft : Colors.white,
            border: Border.all(
              color: selected ? AppColors.red : AppColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                method.icon,
                color: selected ? AppColors.red : Colors.black87,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                    Text(
                      method.group,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppColors.red : Colors.black38,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow(
    this.label,
    this.value, {
    this.bold = false,
    this.positive = false,
  });

  final String label;
  final String value;
  final bool bold;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 14 : 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
                color: bold ? Colors.black : Colors.grey.shade700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 12.5,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              color: bold
                  ? AppColors.red
                  : (positive ? AppColors.success : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
