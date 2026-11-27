import 'dart:math' as math;

import '../UTILS/formatters.dart';
import 'member_model.dart';

enum VoucherType { percent, fixed, freeShipping }

class Voucher {
  final String code;
  final String title;
  final String description;
  final VoucherType type;

  /// Persen (untuk `percent`) atau nominal Rupiah (untuk `fixed`).
  final double value;

  /// Batas maksimum potongan untuk voucher persen.
  final double? maxDiscount;

  final double minSpend;
  final bool memberOnly;
  final MemberTier? minTier;
  final DateTime expiresAt;

  Voucher({
    required this.code,
    required this.title,
    required this.description,
    required this.type,
    this.value = 0,
    this.maxDiscount,
    this.minSpend = 0,
    this.memberOnly = false,
    this.minTier,
    required this.expiresAt,
  });

  /// Mengembalikan pesan error jika voucher tidak bisa dipakai, atau `null`
  /// jika valid.
  String? validate({
    required double subtotal,
    required bool isMember,
    required MemberTier tier,
    DateTime? now,
  }) {
    if ((now ?? DateTime.now()).isAfter(expiresAt)) {
      return 'Voucher sudah kedaluwarsa';
    }
    if ((memberOnly || minTier != null) && !isMember) {
      return 'Voucher ini khusus member. Silakan masuk terlebih dahulu';
    }
    if (minTier != null && tier.index < minTier!.index) {
      return 'Voucher ini khusus member ${minTier!.label} ke atas';
    }
    if (subtotal < minSpend) {
      return 'Minimal belanja ${formatRupiah(minSpend)}';
    }
    return null;
  }

  /// Besar potongan untuk nilai dasar [base]. Voucher gratis ongkir
  /// tidak memotong harga produk.
  double discountOn(double base) {
    switch (type) {
      case VoucherType.percent:
        var discount = base * value / 100;
        if (maxDiscount != null) {
          discount = math.min(discount, maxDiscount!);
        }
        return discount.roundToDouble();
      case VoucherType.fixed:
        return math.min(value, base);
      case VoucherType.freeShipping:
        return 0;
    }
  }

  String get benefitLabel {
    switch (type) {
      case VoucherType.percent:
        final cap = maxDiscount == null
            ? ''
            : ' (maks. ${formatRupiah(maxDiscount!)})';
        return 'Diskon ${value.toStringAsFixed(0)}%$cap';
      case VoucherType.fixed:
        return 'Potongan ${formatRupiah(value)}';
      case VoucherType.freeShipping:
        return 'Gratis ongkir';
    }
  }
}
