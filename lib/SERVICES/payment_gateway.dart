import 'dart:async';
import 'dart:math' as math;

/// Kanal pembayaran yang dilayani gateway.
enum GatewayChannel { virtualAccount, qris, card }

/// Menentukan kanal gateway dari nama metode di checkout.
/// `null` = tidak lewat gateway (COD).
GatewayChannel? gatewayChannelFor(String method) {
  final m = method.toLowerCase();
  if (m.startsWith('cod')) return null;
  if (m.contains('virtual account')) return GatewayChannel.virtualAccount;
  if (m.contains('qris') || m.contains('wallet')) return GatewayChannel.qris;
  if (m.contains('kartu')) return GatewayChannel.card;
  return null;
}

/// Tagihan yang dibuat gateway.
class GatewayCharge {
  const GatewayCharge({
    required this.reference,
    required this.channel,
    required this.amount,
    required this.expiresAt,
    this.bank,
    this.vaNumber,
    this.qrData,
  });

  final String reference;
  final GatewayChannel channel;
  final double amount;
  final DateTime expiresAt;
  final String? bank;
  final String? vaNumber;
  final String? qrData;
}

/// Hasil akhir pembayaran.
class GatewayResult {
  const GatewayResult.success(this.reference, this.info)
      : ok = true,
        error = null;
  const GatewayResult.failure(this.error)
      : ok = false,
        reference = null,
        info = null;

  final bool ok;
  final String? reference;

  /// Ringkasan kanal untuk struk, mis. "VA BCA 39358…" atau "Visa •••• 1114".
  final String? info;
  final String? error;
}

/// Tantangan 3-D Secure (OTP) setelah kartu diterima.
class CardChallenge {
  const CardChallenge(this.reference, this.last4, this.brand);
  final String reference;
  final String last4;
  final String brand;
}

class GatewayException implements Exception {
  GatewayException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Antarmuka payment gateway. Ganti implementasinya (mis. Midtrans/Xendit
/// lewat server Anda) tanpa mengubah halaman pembayaran.
abstract class PaymentGateway {
  Future<GatewayCharge> createCharge({
    required String orderRef,
    required double amount,
    required GatewayChannel channel,
    String? bank,
  });

  /// Memeriksa apakah tagihan VA/QRIS sudah dibayar pelanggan.
  Future<GatewayResult> checkStatus(GatewayCharge charge);

  Future<CardChallenge> startCard({
    required String orderRef,
    required double amount,
    required String number,
    required String expiry,
    required String cvv,
  });

  Future<GatewayResult> verifyOtp(CardChallenge challenge, String otp);
}

/// Algoritma Luhn untuk nomor kartu.
bool luhnValid(String number) {
  final digits = number.replaceAll(RegExp(r'\s|-'), '');
  if (!RegExp(r'^\d{12,19}$').hasMatch(digits)) return false;
  var sum = 0;
  var alt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = int.parse(digits[i]);
    if (alt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alt = !alt;
  }
  return sum % 10 == 0;
}

/// Format "MM/YY"; valid bila bulan 1-12 dan belum lewat dari [now].
bool cardExpiryValid(String text, DateTime now) {
  final m = RegExp(r'^(\d{2})\s*/\s*(\d{2})$').firstMatch(text.trim());
  if (m == null) return false;
  final month = int.parse(m.group(1)!);
  final year = 2000 + int.parse(m.group(2)!);
  if (month < 1 || month > 12) return false;
  return DateTime(year, month + 1).isAfter(now);
}

String cardBrand(String number) {
  final d = number.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('4')) return 'Visa';
  if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(d)) return 'Mastercard';
  if (RegExp(r'^3[47]').hasMatch(d)) return 'Amex';
  return 'Kartu';
}

/// Gateway sandbox: berperilaku seperti gateway sungguhan (tagihan, VA,
/// QRIS, 3-D Secure) tetapi tanpa memindahkan uang. Dipakai untuk demo
/// dan tes. Aturan uji:
/// - Kartu valid Luhn diterima; yang berakhiran 0002 ditolak, berakhiran
///   0003 saldo tidak cukup (mis. 4811 1111 0003 0002).
/// - OTP benar: 112233.
class SandboxPaymentGateway implements PaymentGateway {
  SandboxPaymentGateway({
    this.latency = const Duration(milliseconds: 700),
    DateTime Function()? clock,
    math.Random? random,
  })  : _clock = clock ?? DateTime.now,
        _random = random ?? math.Random();

  static const String otpCode = '112233';

  final Duration latency;
  final DateTime Function() _clock;
  final math.Random _random;

  final Set<String> _paid = {};

  Future<void> _wait() => Future<void>.delayed(latency);

  String _digits(int n) =>
      List.generate(n, (_) => _random.nextInt(10)).join();

  @override
  Future<GatewayCharge> createCharge({
    required String orderRef,
    required double amount,
    required GatewayChannel channel,
    String? bank,
  }) async {
    await _wait();
    final ref = 'TRX-${_clock().millisecondsSinceEpoch}-${_digits(3)}';
    switch (channel) {
      case GatewayChannel.virtualAccount:
        final isMandiri = (bank ?? '').toLowerCase().contains('mandiri');
        final prefix = isMandiri ? '88608' : '39358';
        return GatewayCharge(
          reference: ref,
          channel: channel,
          amount: amount,
          bank: isMandiri ? 'Mandiri' : 'BCA',
          vaNumber: '$prefix${_digits(11)}',
          expiresAt: _clock().add(const Duration(hours: 24)),
        );
      case GatewayChannel.qris:
        return GatewayCharge(
          reference: ref,
          channel: channel,
          amount: amount,
          qrData: 'UNIQLOPLUS|$ref|${amount.round()}',
          expiresAt: _clock().add(const Duration(minutes: 15)),
        );
      case GatewayChannel.card:
        return GatewayCharge(
          reference: ref,
          channel: channel,
          amount: amount,
          expiresAt: _clock().add(const Duration(minutes: 15)),
        );
    }
  }

  /// Sandbox: dipanggil tombol "Simulasikan pembayaran" yang meniru
  /// notifikasi dari bank / e-wallet.
  void simulateCustomerPaid(GatewayCharge charge) => _paid.add(charge.reference);

  @override
  Future<GatewayResult> checkStatus(GatewayCharge charge) async {
    await _wait();
    if (!_clock().isBefore(charge.expiresAt)) {
      return const GatewayResult.failure('Tagihan sudah kedaluwarsa.');
    }
    if (!_paid.contains(charge.reference)) {
      return const GatewayResult.failure('Pembayaran belum diterima.');
    }
    final info = charge.channel == GatewayChannel.virtualAccount
        ? 'VA ${charge.bank} ${charge.vaNumber}'
        : 'QRIS';
    return GatewayResult.success(charge.reference, info);
  }

  @override
  Future<CardChallenge> startCard({
    required String orderRef,
    required double amount,
    required String number,
    required String expiry,
    required String cvv,
  }) async {
    await _wait();
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (!luhnValid(digits)) {
      throw GatewayException('Nomor kartu tidak valid.');
    }
    if (!cardExpiryValid(expiry, _clock())) {
      throw GatewayException('Masa berlaku kartu tidak valid.');
    }
    if (!RegExp(r'^\d{3,4}$').hasMatch(cvv)) {
      throw GatewayException('CVV harus 3 atau 4 digit.');
    }
    if (digits.endsWith('0002')) {
      throw GatewayException('Kartu ditolak oleh bank penerbit.');
    }
    if (digits.endsWith('0003')) {
      throw GatewayException('Saldo/limit kartu tidak cukup.');
    }
    return CardChallenge(
      'TRX-${_clock().millisecondsSinceEpoch}-${_digits(3)}',
      digits.substring(digits.length - 4),
      cardBrand(digits),
    );
  }

  @override
  Future<GatewayResult> verifyOtp(CardChallenge challenge, String otp) async {
    await _wait();
    if (otp.trim() != otpCode) {
      return const GatewayResult.failure('Kode OTP salah.');
    }
    return GatewayResult.success(
      challenge.reference,
      '${challenge.brand} •••• ${challenge.last4}',
    );
  }
}
