import 'package:flutter/material.dart';

import 'order_model.dart';

/// Status pembayaran sebuah pesanan.
enum PaymentStatus { lunas, menunggu, dikembalikan, dibatalkan }

extension PaymentStatusInfo on PaymentStatus {
  String get label {
    switch (this) {
      case PaymentStatus.lunas:
        return 'Lunas';
      case PaymentStatus.menunggu:
        return 'Menunggu pembayaran';
      case PaymentStatus.dikembalikan:
        return 'Dikembalikan';
      case PaymentStatus.dibatalkan:
        return 'Dibatalkan';
    }
  }

  Color get color {
    switch (this) {
      case PaymentStatus.lunas:
        return const Color(0xFF2E7D32);
      case PaymentStatus.menunggu:
        return const Color(0xFFEF6C00);
      case PaymentStatus.dikembalikan:
      case PaymentStatus.dibatalkan:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentStatus.lunas:
        return Icons.check_circle_outline;
      case PaymentStatus.menunggu:
        return Icons.hourglass_bottom;
      case PaymentStatus.dikembalikan:
        return Icons.undo;
      case PaymentStatus.dibatalkan:
        return Icons.cancel_outlined;
    }
  }
}

/// Catatan pembayaran yang diturunkan dari sebuah pesanan.
class PaymentRecord {
  final String reference;
  final Order order;
  final PaymentStatus status;

  const PaymentRecord({
    required this.reference,
    required this.order,
    required this.status,
  });

  String get method => order.paymentMethod;
  double get amount => order.total;
  DateTime get paidAt => order.createdAt;
  bool get isCod => isCashOnDelivery(order.paymentMethod);
}

bool isCashOnDelivery(String method) => method.toUpperCase().startsWith('COD');

/// Nomor referensi pembayaran, contoh: PAY-20261015-4821.
String paymentReference(Order order) =>
    'PAY-${order.id.replaceFirst('UNQ-', '')}';

PaymentStatus paymentStatusFor(Order order, {DateTime? now}) {
  // Ikuti status pembayaran yang disimpan server, bukan menebak lunas dari
  // status pengiriman. COD tetap belum lunas sampai admin/backend menerima
  // konfirmasi pembayaran yang sebenarnya.
  if (order.paymentStatus.toLowerCase() == 'refunded') {
    return PaymentStatus.dikembalikan;
  }
  if (order.isCancelled) return PaymentStatus.dibatalkan;
  if (order.isPaid) return PaymentStatus.lunas;
  return PaymentStatus.menunggu;
}

/// Membuat daftar pembayaran (terbaru dulu) dari daftar pesanan.
List<PaymentRecord> buildPaymentRecords(List<Order> orders, {DateTime? now}) {
  final list = [
    for (final order in orders)
      PaymentRecord(
        reference: paymentReference(order),
        order: order,
        status: paymentStatusFor(order, now: now),
      ),
  ];
  list.sort((a, b) => b.paidAt.compareTo(a.paidAt));
  return list;
}
