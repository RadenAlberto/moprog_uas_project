import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'product_model.dart';

/// Status pesanan.
///
/// Status dihitung dari waktu sejak pesanan dibuat supaya alur pelacakan
/// bisa dilihat langsung saat demo. Ubah [OrderTiming] menjadi jam/hari
/// jika ingin simulasi yang lebih realistis.
/// Cara penerimaan pesanan.
const String kFulfillPickup = 'pickup';
const String kFulfillDelivery = 'delivery';

enum OrderStatus { diproses, dikemas, dikirim, selesai, dibatalkan }

class OrderTiming {
  OrderTiming._();

  static const Duration processing = Duration(minutes: 2);
  static const Duration packing = Duration(minutes: 3);
  static const Duration shipping = Duration(minutes: 4);
}

extension OrderStatusInfo on OrderStatus {
  String get label {
    switch (this) {
      case OrderStatus.diproses:
        return 'Diproses';
      case OrderStatus.dikemas:
        return 'Dikemas';
      case OrderStatus.dikirim:
        return 'Dikirim';
      case OrderStatus.selesai:
        return 'Selesai';
      case OrderStatus.dibatalkan:
        return 'Dibatalkan';
    }
  }

  String get description {
    switch (this) {
      case OrderStatus.diproses:
        return 'Pembayaran diterima, pesanan sedang diproses.';
      case OrderStatus.dikemas:
        return 'Pesanan sedang dikemas di gudang.';
      case OrderStatus.dikirim:
        return 'Pesanan dalam perjalanan ke alamat Anda.';
      case OrderStatus.selesai:
        return 'Pesanan telah diterima. Terima kasih sudah berbelanja!';
      case OrderStatus.dibatalkan:
        return 'Pesanan dibatalkan. Poin dan saldo dikembalikan.';
    }
  }

  Color get color {
    switch (this) {
      case OrderStatus.diproses:
        return const Color(0xFFEF6C00);
      case OrderStatus.dikemas:
        return const Color(0xFF1565C0);
      case OrderStatus.dikirim:
        return const Color(0xFF6A4FA3);
      case OrderStatus.selesai:
        return const Color(0xFF2E7D32);
      case OrderStatus.dibatalkan:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData get icon {
    switch (this) {
      case OrderStatus.diproses:
        return Icons.receipt_long;
      case OrderStatus.dikemas:
        return Icons.inventory_2_outlined;
      case OrderStatus.dikirim:
        return Icons.local_shipping_outlined;
      case OrderStatus.selesai:
        return Icons.check_circle_outline;
      case OrderStatus.dibatalkan:
        return Icons.cancel_outlined;
    }
  }
}

/// Salinan data produk saat pembelian (harga tidak berubah walau katalog
/// berubah).
class OrderItem {
  final String productId;
  final String name;
  final String image;
  final double price;
  final String size;
  final int colorValue;
  final int quantity;

  const OrderItem({
    required this.productId,
    required this.name,
    required this.image,
    required this.price,
    required this.size,
    required this.colorValue,
    required this.quantity,
  });

  factory OrderItem.fromCartItem(CartItem item) {
    return OrderItem(
      productId: item.product.id,
      name: item.product.name,
      image: item.product.imageFor(item.selectedColor),
      price: item.product.price,
      size: item.selectedSize,
      colorValue: item.selectedColor.toARGB32(),
      quantity: item.quantity,
    );
  }

  Color get color => Color(colorValue);

  double get lineTotal => price * quantity;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'image': image,
        'price': price,
        'size': size,
        'colorValue': colorValue,
        'quantity': quantity,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['productId'] as String,
      name: json['name'] as String,
      image: (json['image'] as String?) ?? '',
      price: (json['price'] as num).toDouble(),
      size: json['size'] as String,
      colorValue: (json['colorValue'] as num).toInt(),
      quantity: (json['quantity'] as num).toInt(),
    );
  }
}

class Order {
  final String id;
  final String memberId;
  final DateTime createdAt;
  final List<OrderItem> items;
  final String paymentMethod;
  final String paymentStatus;
  final String recipient;
  final String phone;
  final String address;
  final int? addressId;

  final double subtotal;
  final double memberDiscount;
  final String? voucherCode;
  final double voucherDiscount;
  final int pointsUsed;
  final double pointsDiscount;
  final double shippingFee;
  final double shippingDiscount;
  final int pointsEarned;

  /// Terisi bila pesanan dibatalkan.
  final DateTime? cancelledAt;

  /// Status resmi dari backend; null berarti memakai simulasi lokal lama.
  final OrderStatus? serverStatus;

  /// Cara penerimaan: `null` = belum dipilih, [kFulfillPickup] atau
  /// [kFulfillDelivery].
  final String? fulfillmentType;
  final String? storeId;
  final String? storeName;
  final String? storeAddress;

  /// Kode yang ditunjukkan ke kasir saat mengambil pesanan di toko.
  final String? pickupCode;

  /// Layanan kurir untuk pengiriman ke alamat.
  final String? deliveryService;

  /// Waktu pilihan penerimaan disimpan.
  final DateTime? fulfillmentAt;

  /// Ongkir yang dikembalikan karena pesanan diambil di toko.
  final double shippingRefund;

  /// Referensi transaksi dari payment gateway dan ringkasan kanalnya
  /// (mis. nomor VA atau 4 digit kartu).
  final String? gatewayRef;
  final String? paymentInfo;

  const Order({
    required this.id,
    required this.memberId,
    required this.createdAt,
    required this.items,
    required this.paymentMethod,
    this.paymentStatus = 'Pending',
    required this.recipient,
    required this.phone,
    required this.address,
    this.addressId,
    required this.subtotal,
    required this.memberDiscount,
    this.voucherCode,
    required this.voucherDiscount,
    required this.pointsUsed,
    required this.pointsDiscount,
    required this.shippingFee,
    required this.shippingDiscount,
    required this.pointsEarned,
    this.cancelledAt,
    this.serverStatus,
    this.fulfillmentType,
    this.storeId,
    this.storeName,
    this.storeAddress,
    this.pickupCode,
    this.deliveryService,
    this.fulfillmentAt,
    this.shippingRefund = 0,
    this.gatewayRef,
    this.paymentInfo,
  });

  bool get isPickup => fulfillmentType == kFulfillPickup;
  bool get isDelivery => fulfillmentType == kFulfillDelivery;
  bool get needsFulfillment => fulfillmentType == null && !isCancelled;

  /// Label status yang menyesuaikan cara penerimaan.
  String statusLabel(OrderStatus s) {
    if (isPickup) {
      switch (s) {
        case OrderStatus.dikemas:
          return 'Disiapkan';
        case OrderStatus.dikirim:
          return 'Siap diambil';
        default:
          break;
      }
    }
    return s.label;
  }

  String statusDescription(OrderStatus s) {
    if (isPickup) {
      switch (s) {
        case OrderStatus.diproses:
          return 'Pembayaran diterima, pesanan diteruskan ke toko.';
        case OrderStatus.dikemas:
          return 'Tim toko sedang menyiapkan pesanan Anda.';
        case OrderStatus.dikirim:
          return 'Pesanan siap diambil di ${storeName ?? 'toko'}. '
              'Tunjukkan kode ambil ke kasir.';
        case OrderStatus.selesai:
          return 'Pesanan sudah diambil. Terima kasih sudah berbelanja!';
        case OrderStatus.dibatalkan:
          break;
      }
    }
    if (needsFulfillment && s == OrderStatus.diproses) {
      return 'Pembayaran diterima. Pilih ambil di toko atau diantar.';
    }
    return s.description;
  }

  bool get isCancelled => cancelledAt != null;

  bool get isPaid => paymentStatus.toLowerCase() == 'paid';

  bool get isCod => paymentMethod.toUpperCase().startsWith('COD') ||
      paymentMethod.toLowerCase().contains('bayar di tempat');

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Nilai produk yang dibayar (setelah diskon & poin, tanpa ongkir).
  double get merchandisePaid => math.max(
      0.0, subtotal - memberDiscount - voucherDiscount - pointsDiscount);

  double get total =>
      math.max(0.0, merchandisePaid + shippingFee - shippingDiscount);

  double get totalSavings =>
      memberDiscount + voucherDiscount + pointsDiscount + shippingDiscount;

  OrderStatus statusAt(DateTime now) {
    if (serverStatus != null) return serverStatus!;
    if (isCancelled) return OrderStatus.dibatalkan;
    final elapsed = now.difference(createdAt);
    if (elapsed < OrderTiming.processing) return OrderStatus.diproses;
    if (elapsed < OrderTiming.processing + OrderTiming.packing) {
      return OrderStatus.dikemas;
    }
    if (elapsed <
        OrderTiming.processing + OrderTiming.packing + OrderTiming.shipping) {
      return OrderStatus.dikirim;
    }
    return OrderStatus.selesai;
  }

  OrderStatus get status => statusAt(DateTime.now());

  /// Member dapat membatalkan pesanan selama belum selesai/dibatalkan.
  /// Aturan yang sama diterapkan oleh endpoint pembatalan backend.
  bool get canCancel =>
      status != OrderStatus.selesai && status != OrderStatus.dibatalkan;

  /// Waktu sebuah tahap dimulai (untuk linimasa pelacakan).
  DateTime stageStart(OrderStatus stage) {
    switch (stage) {
      case OrderStatus.diproses:
        return createdAt;
      case OrderStatus.dikemas:
        return createdAt.add(OrderTiming.processing);
      case OrderStatus.dikirim:
        return createdAt.add(OrderTiming.processing + OrderTiming.packing);
      case OrderStatus.selesai:
        return createdAt.add(OrderTiming.processing +
            OrderTiming.packing +
            OrderTiming.shipping);
      case OrderStatus.dibatalkan:
        return cancelledAt ?? createdAt;
    }
  }

  /// Nomor resi contoh, muncul setelah pesanan dikirim.
  String get trackingNumber {
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    return 'LWX$digits';
  }

  Order copyWith({
    DateTime? cancelledAt,
    String? fulfillmentType,
    String? storeId,
    String? storeName,
    String? storeAddress,
    String? pickupCode,
    String? deliveryService,
    DateTime? fulfillmentAt,
    String? address,
    int? addressId,
    bool clearAddressId = false,
    String? recipient,
    String? phone,
    double? shippingFee,
    double? shippingDiscount,
    double? shippingRefund,
    OrderStatus? serverStatus,
    String? paymentStatus,
  }) {
    return Order(
      id: id,
      memberId: memberId,
      createdAt: createdAt,
      items: items,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      recipient: recipient ?? this.recipient,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      addressId: clearAddressId ? null : (addressId ?? this.addressId),
      subtotal: subtotal,
      memberDiscount: memberDiscount,
      voucherCode: voucherCode,
      voucherDiscount: voucherDiscount,
      pointsUsed: pointsUsed,
      pointsDiscount: pointsDiscount,
      shippingFee: shippingFee ?? this.shippingFee,
      shippingDiscount: shippingDiscount ?? this.shippingDiscount,
      pointsEarned: pointsEarned,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      serverStatus: serverStatus ?? this.serverStatus,
      fulfillmentType: fulfillmentType ?? this.fulfillmentType,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      pickupCode: pickupCode ?? this.pickupCode,
      deliveryService: deliveryService ?? this.deliveryService,
      fulfillmentAt: fulfillmentAt ?? this.fulfillmentAt,
      shippingRefund: shippingRefund ?? this.shippingRefund,
      gatewayRef: gatewayRef,
      paymentInfo: paymentInfo,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'serverStatus': serverStatus?.name,
        'items': items.map((i) => i.toJson()).toList(),
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'recipient': recipient,
        'phone': phone,
        'address': address,
        'addressId': addressId,
        'subtotal': subtotal,
        'memberDiscount': memberDiscount,
        'voucherCode': voucherCode,
        'voucherDiscount': voucherDiscount,
        'pointsUsed': pointsUsed,
        'pointsDiscount': pointsDiscount,
        'shippingFee': shippingFee,
        'shippingDiscount': shippingDiscount,
        'pointsEarned': pointsEarned,
        'cancelledAt': cancelledAt?.toIso8601String(),
        'fulfillmentType': fulfillmentType,
        'storeId': storeId,
        'storeName': storeName,
        'storeAddress': storeAddress,
        'pickupCode': pickupCode,
        'deliveryService': deliveryService,
        'fulfillmentAt': fulfillmentAt?.toIso8601String(),
        'shippingRefund': shippingRefund,
        'gatewayRef': gatewayRef,
        'paymentInfo': paymentInfo,
      };

  factory Order.fromJson(Map<String, dynamic> json) {
    final cancelled = json['cancelledAt'] as String?;
    final rawStatus = json['serverStatus'] as String?;
    final serverStatus = rawStatus == null ? null : (OrderStatus.values.any((x) => x.name == rawStatus) ? OrderStatus.values.firstWhere((x) => x.name == rawStatus) : null);
    return Order(
      id: json['id'] as String,
      memberId: json['memberId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      items: (json['items'] as List)
          .map((e) => OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      paymentMethod: json['paymentMethod'] as String,
      paymentStatus: (json['paymentStatus'] ?? 'Pending').toString(),
      recipient: (json['recipient'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      addressId: (json['addressId'] as num?)?.toInt(),
      subtotal: (json['subtotal'] as num).toDouble(),
      memberDiscount: (json['memberDiscount'] as num).toDouble(),
      voucherCode: json['voucherCode'] as String?,
      voucherDiscount: (json['voucherDiscount'] as num).toDouble(),
      pointsUsed: (json['pointsUsed'] as num).toInt(),
      pointsDiscount: (json['pointsDiscount'] as num).toDouble(),
      shippingFee: (json['shippingFee'] as num).toDouble(),
      shippingDiscount: (json['shippingDiscount'] as num).toDouble(),
      pointsEarned: (json['pointsEarned'] as num).toInt(),
      cancelledAt: cancelled == null ? null : DateTime.parse(cancelled),
      serverStatus: serverStatus,
      // Pesanan lama (sebelum fitur ini) dianggap sudah dikirim ke alamat.
      // Key null berarti pesanan baru belum memilih penerimaan.
      // Key tidak ada berarti snapshot lama sebelum field ini diperkenalkan.
      fulfillmentType: json.containsKey('fulfillmentType')
          ? json['fulfillmentType'] as String?
          : kFulfillDelivery,
      storeId: json['storeId'] as String?,
      storeName: json['storeName'] as String?,
      storeAddress: json['storeAddress'] as String?,
      pickupCode: json['pickupCode'] as String?,
      deliveryService: json['deliveryService'] as String?,
      fulfillmentAt: json['fulfillmentAt'] == null
          ? null
          : DateTime.parse(json['fulfillmentAt'] as String),
      shippingRefund: (json['shippingRefund'] as num?)?.toDouble() ?? 0,
      gatewayRef: json['gatewayRef'] as String?,
      paymentInfo: json['paymentInfo'] as String?,
    );
  }
}
