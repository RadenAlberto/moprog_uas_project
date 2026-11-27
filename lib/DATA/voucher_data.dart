import '../MODELS/member_model.dart';
import '../MODELS/voucher_model.dart';

/// Daftar voucher contoh. Kode voucher tidak peka huruf besar/kecil.
final List<Voucher> kVouchers = [
  Voucher(
    code: 'LIFEWEAR10',
    title: 'Diskon 10% Semua Produk',
    description: 'Berlaku untuk semua pengguna, tanpa harus menjadi member.',
    type: VoucherType.percent,
    value: 10,
    maxDiscount: 100000,
    minSpend: 300000,
    expiresAt: DateTime(2027, 12, 31, 23, 59),
  ),
  Voucher(
    code: 'ONGKIRFREE',
    title: 'Gratis Ongkir',
    description: 'Bebas ongkos kirim untuk pesanan ke seluruh Indonesia.',
    type: VoucherType.freeShipping,
    minSpend: 150000,
    expiresAt: DateTime(2027, 12, 31, 23, 59),
  ),
  Voucher(
    code: 'HEMAT50',
    title: 'Potongan Rp50.000 Khusus Member',
    description: 'Hanya untuk member yang sudah masuk (login).',
    type: VoucherType.fixed,
    value: 50000,
    minSpend: 500000,
    memberOnly: true,
    expiresAt: DateTime(2027, 12, 31, 23, 59),
  ),
  Voucher(
    code: 'GOLDSPECIAL',
    title: 'Diskon 15% Member Gold & Platinum',
    description: 'Voucher eksklusif untuk member level Gold ke atas.',
    type: VoucherType.percent,
    value: 15,
    maxDiscount: 250000,
    minSpend: 800000,
    memberOnly: true,
    minTier: MemberTier.gold,
    expiresAt: DateTime(2027, 12, 31, 23, 59),
  ),
];
