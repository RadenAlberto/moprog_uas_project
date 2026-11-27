import 'dart:math' as math;

import 'member_model.dart';
import 'voucher_model.dart';

/// Aturan harga, ongkir, dan poin. Semua aturan ada di satu tempat supaya
/// mudah diubah dan diuji.
class PricingRules {
  PricingRules._();

  /// Ongkos kirim dasar.
  static const double baseShipping = 15000;

  /// Nilai 1 poin saat ditukar (Rupiah).
  static const double pointValue = 100;

  /// Setiap kelipatan belanja ini mendapat 1 poin (sebelum pengali level).
  static const double spendPerPoint = 10000;

  /// Maksimum porsi belanja yang boleh dibayar dengan poin.
  static const double maxPointsShare = 0.5;

  /// Bonus poin saat mendaftar.
  static const int welcomeBonusPoints = 200;
}

class PriceBreakdown {
  final double subtotal;
  final double memberDiscount;
  final double voucherDiscount;
  final int pointsUsed;
  final double pointsDiscount;
  final double shippingFee;
  final double shippingDiscount;
  final int pointsEarned;

  const PriceBreakdown({
    required this.subtotal,
    required this.memberDiscount,
    required this.voucherDiscount,
    required this.pointsUsed,
    required this.pointsDiscount,
    required this.shippingFee,
    required this.shippingDiscount,
    required this.pointsEarned,
  });

  /// Nilai produk yang benar-benar dibayar (setelah semua diskon & poin,
  /// tanpa ongkir). Menjadi dasar perhitungan poin dan level.
  double get merchandisePaid => math.max(
      0.0, subtotal - memberDiscount - voucherDiscount - pointsDiscount);

  double get total => math.max(0.0, merchandisePaid + shippingFee - shippingDiscount);

  double get totalSavings =>
      memberDiscount + voucherDiscount + pointsDiscount + shippingDiscount;
}

/// Menghitung rincian pembayaran.
///
/// - Diskon level hanya berlaku untuk member yang login.
/// - [voucher] hanya diterapkan bila lolos validasi.
/// - Poin dibatasi saldo [pointsAvailable] dan maksimum 50% dari belanja.
/// - Gratis ongkir bila memenuhi minimal belanja level, atau voucher ongkir.
PriceBreakdown calculatePrice({
  required double subtotal,
  required bool isMember,
  MemberTier tier = MemberTier.regular,
  Voucher? voucher,
  int pointsToUse = 0,
  int pointsAvailable = 0,
}) {
  final effectiveTier = isMember ? tier : MemberTier.regular;

  final memberDiscount =
      isMember ? (subtotal * effectiveTier.discountRate).roundToDouble() : 0.0;
  final afterMember = subtotal - memberDiscount;

  var voucherDiscount = 0.0;
  var freeShippingByVoucher = false;
  if (voucher != null &&
      voucher.validate(
            subtotal: subtotal,
            isMember: isMember,
            tier: effectiveTier,
          ) ==
          null) {
    if (voucher.type == VoucherType.freeShipping) {
      freeShippingByVoucher = true;
    } else {
      voucherDiscount = voucher.discountOn(afterMember);
    }
  }
  final afterVoucher = afterMember - voucherDiscount;

  var pointsUsed = 0;
  if (isMember && pointsToUse > 0 && pointsAvailable > 0) {
    final maxByShare =
        (afterVoucher * PricingRules.maxPointsShare / PricingRules.pointValue)
            .floor();
    final cap = math.min(pointsAvailable, maxByShare);
    pointsUsed = math.max(0, math.min(pointsToUse, cap));
  }
  final pointsDiscount = pointsUsed * PricingRules.pointValue;

  final shippingFee = subtotal > 0 ? PricingRules.baseShipping : 0.0;
  final qualifiesFreeShipping =
      subtotal > 0 && subtotal >= effectiveTier.freeShippingMinSpend;
  final shippingDiscount =
      (freeShippingByVoucher || qualifiesFreeShipping) ? shippingFee : 0.0;

  final merchandisePaid = math.max(0.0, afterVoucher - pointsDiscount);
  final pointsEarned = isMember
      ? (merchandisePaid /
              PricingRules.spendPerPoint *
              effectiveTier.pointMultiplier)
          .floor()
      : 0;

  return PriceBreakdown(
    subtotal: subtotal,
    memberDiscount: memberDiscount,
    voucherDiscount: voucherDiscount,
    pointsUsed: pointsUsed,
    pointsDiscount: pointsDiscount,
    shippingFee: shippingFee,
    shippingDiscount: shippingDiscount,
    pointsEarned: pointsEarned,
  );
}
