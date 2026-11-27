import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:project_uts/DATA/product_data.dart';
import 'package:project_uts/MODELS/order_model.dart';
import 'package:project_uts/MODELS/pricing.dart';
import 'package:project_uts/MODELS/product_model.dart';
import 'package:project_uts/PROVIDERS/auth_provider.dart';
import 'package:project_uts/SCREENS/fulfillment_page.dart';
import 'package:project_uts/DATA/store_data.dart';
import 'package:project_uts/MODELS/store_model.dart';
import 'package:project_uts/SERVICES/payment_gateway.dart';
import 'package:project_uts/UTILS/key_value_store.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadProductCatalog();
  });


  test('Pickup tetap menampilkan toko server saat metadata services kosong', () {
    final original = List<StoreLocation>.of(kStores);
    addTearDown(() {
      kStores
        ..clear()
        ..addAll(original);
    });

    kStores
      ..clear()
      ..addAll([
        const StoreLocation(
          id: 'DB001',
          name: 'UNIQLO Toko Database 1',
          mall: 'Mall Satu',
          city: 'Jakarta',
          address: 'Jl. Satu',
          services: [],
        ),
        const StoreLocation(
          id: 'DB002',
          name: 'UNIQLO Toko Database 2',
          mall: 'Mall Dua',
          city: 'Jakarta',
          address: 'Jl. Dua',
          services: [],
        ),
      ]);

    expect(pickupStores().map((s) => s.id), ['DB001', 'DB002']);
  });

  test('metadata layanan Pickup tetap difilter bila sudah tersedia', () {
    final original = List<StoreLocation>.of(kStores);
    addTearDown(() {
      kStores
        ..clear()
        ..addAll(original);
    });

    kStores
      ..clear()
      ..addAll([
        const StoreLocation(
          id: 'DB001',
          name: 'UNIQLO Pickup',
          mall: 'Mall Satu',
          city: 'Jakarta',
          address: 'Jl. Satu',
          services: ['Pickup pesanan'],
        ),
        const StoreLocation(
          id: 'DB002',
          name: 'UNIQLO Non Pickup',
          mall: 'Mall Dua',
          city: 'Jakarta',
          address: 'Jl. Dua',
          services: ['Alterasi'],
        ),
      ]);

    expect(pickupStores().map((s) => s.id), ['DB001']);
  });

  test('pesanan belum selesai dapat dibatalkan, selesai dan batal tidak', () {
    Order makeOrder(String status) => Order.fromJson({
      'id': 'TEST-$status',
      'memberId': 'm1',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'items': <dynamic>[],
      'paymentMethod': 'Virtual Account BCA',
      'paymentStatus': 'Paid',
      'recipient': 'Tester',
      'phone': '0812',
      'address': 'Jakarta',
      'subtotal': 100000,
      'memberDiscount': 0,
      'voucherDiscount': 0,
      'pointsUsed': 0,
      'pointsDiscount': 0,
      'shippingFee': 0,
      'shippingDiscount': 0,
      'pointsEarned': 0,
      'serverStatus': status,
    });

    expect(makeOrder('diproses').canCancel, isTrue);
    expect(makeOrder('dikemas').canCancel, isTrue);
    expect(makeOrder('dikirim').canCancel, isTrue);
    expect(makeOrder('selesai').canCancel, isFalse);
    expect(makeOrder('dibatalkan').canCancel, isFalse);
  });

  test('Luhn dan masa berlaku kartu', () {
    expect(luhnValid('4811 1111 1111 1114'), isTrue);
    expect(luhnValid('4811 1111 1111 1115'), isFalse);
    expect(luhnValid('abc'), isFalse);
    final now = DateTime(2026, 11, 13);
    expect(cardExpiryValid('12/26', now), isTrue);
    expect(cardExpiryValid('10/26', now), isFalse);
    expect(cardExpiryValid('13/30', now), isFalse);
    expect(cardExpiryValid('1230', now), isFalse);
  });

  test('Kanal gateway menurut metode; COD tidak lewat gateway', () {
    expect(gatewayChannelFor('Virtual Account BCA'),
        GatewayChannel.virtualAccount);
    expect(gatewayChannelFor('QRIS / GoPay / OVO'), GatewayChannel.qris);
    expect(gatewayChannelFor('Kartu Kredit / Debit'), GatewayChannel.card);
    expect(gatewayChannelFor('COD (Bayar di Tempat)'), isNull);
  });

  test('Sandbox VA: belum bayar -> gagal, setelah simulasi -> sukses', () async {
    final gw = SandboxPaymentGateway(latency: Duration.zero);
    final charge = await gw.createCharge(
      orderRef: 'X',
      amount: 100000,
      channel: GatewayChannel.virtualAccount,
      bank: 'Mandiri Virtual Account',
    );
    expect(charge.vaNumber, startsWith('88608'));
    expect((await gw.checkStatus(charge)).ok, isFalse);
    gw.simulateCustomerPaid(charge);
    final paid = await gw.checkStatus(charge);
    expect(paid.ok, isTrue);
    expect(paid.info, contains('Mandiri'));
  });

  test('Sandbox kartu: valid + OTP benar, OTP salah, kartu ditolak', () async {
    final gw = SandboxPaymentGateway(latency: Duration.zero);
    final ch = await gw.startCard(
      orderRef: 'X',
      amount: 1,
      number: '4811 1111 1111 1114',
      expiry: '12/40',
      cvv: '123',
    );
    expect((await gw.verifyOtp(ch, '000000')).ok, isFalse);
    final ok = await gw.verifyOtp(ch, SandboxPaymentGateway.otpCode);
    expect(ok.ok, isTrue);
    expect(ok.info, 'Visa •••• 1114');

    expect(
      () => gw.startCard(
        orderRef: 'X',
        amount: 1,
        number: '4811 1111 0003 0002',
        expiry: '12/40',
        cvv: '123',
      ),
      throwsA(isA<GatewayException>()),
    );
  });

  test('Perkiraan siap diambil berada dalam jam buka toko', () {
    final store = pickupStores().first;
    final morning = pickupReadyEstimate(store, DateTime(2026, 11, 13, 6));
    expect(morning.hour, greaterThanOrEqualTo(store.openHour));
    final night = pickupReadyEstimate(store, DateTime(2026, 11, 13, 21));
    expect(night.day, 14);
    final day = pickupReadyEstimate(store, DateTime(2026, 11, 13, 12));
    expect(day, DateTime(2026, 11, 13, 14));
  });

  test('Pesanan: ambil di toko mengembalikan ongkir; hanya sekali pilih',
      () async {
    final auth = AuthProvider(store: MemoryStore());
    final err = await auth.register(
      name: 'Tester',
      email: 'tes@contoh.com',
      phone: '081234567890',
      password: 'rahasia123',
    );
    expect(err, isNull);

    final product = kProducts.first;
    final item = CartItem(
      product: product,
      selectedSize: product.availableSizes.first,
      selectedColor: product.availableColors.first,
    );
    final price = calculatePrice(
      subtotal: item.lineTotal,
      isMember: true,
      tier: auth.tier,
    );
    final order = await auth.placeOrder(
      items: [item],
      pricing: price,
      paymentMethod: 'Virtual Account BCA',
      recipient: 'Tester',
      phone: '081234567890',
      address: 'Jl. Contoh No. 1, Jakarta',
      gatewayRef: 'TRX-1',
      paymentInfo: 'VA BCA 1',
    );
    expect(order, isNotNull);
    expect(order!.needsFulfillment, isTrue);

    final before = order.total;
    final shippingPaid = order.shippingFee - order.shippingDiscount;
    final picked = await auth.setFulfillment(
      order.id,
      type: kFulfillPickup,
      storeId: 's1',
      storeName: 'UNIQLO Grand Indonesia',
      storeAddress: 'Jl. M.H. Thamrin No. 1',
    );
    expect(picked, isNotNull);
    expect(picked!.isPickup, isTrue);
    expect(picked.pickupCode, startsWith('PU-'));
    expect(picked.shippingRefund, shippingPaid);
    expect(picked.total, before - shippingPaid);
    expect(picked.statusLabel(OrderStatus.dikirim), 'Siap diambil');

    // Pilihan tidak bisa diubah lagi (ongkir tidak dikembalikan dua kali).
    final again = await auth.setFulfillment(order.id, type: kFulfillDelivery);
    expect(again, isNull);

    // JSON bolak-balik tetap utuh.
    final back = Order.fromJson(picked.toJson());
    expect(back.pickupCode, picked.pickupCode);
    expect(back.gatewayRef, 'TRX-1');
    expect(back.shippingRefund, picked.shippingRefund);
  });

  test('Pesanan lama tanpa data fulfillment dianggap diantar', () {
    final json = <String, dynamic>{
      'id': 'UNQ-20260101-1111',
      'memberId': 'm1',
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'items': <dynamic>[],
      'paymentMethod': 'COD (Bayar di Tempat)',
      'subtotal': 1.0,
      'memberDiscount': 0.0,
      'voucherDiscount': 0.0,
      'pointsUsed': 0,
      'pointsDiscount': 0.0,
      'shippingFee': 15000.0,
      'shippingDiscount': 0.0,
      'pointsEarned': 0,
    };
    final order = Order.fromJson(json);
    expect(order.isDelivery, isTrue);
    expect(order.needsFulfillment, isFalse);
  });
}
