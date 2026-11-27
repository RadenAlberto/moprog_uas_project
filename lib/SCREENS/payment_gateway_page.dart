import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../SERVICES/payment_gateway.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/ui_kit.dart';

/// Halaman pembayaran lewat payment gateway.
///
/// Mengembalikan [GatewayResult] bila berhasil, atau `null` bila pembeli
/// keluar tanpa membayar (keranjang tetap utuh).
class PaymentGatewayPage extends StatefulWidget {
  const PaymentGatewayPage({
    super.key,
    required this.method,
    required this.amount,
    required this.orderRef,
    this.gateway,
  });

  final String method;
  final double amount;
  final String orderRef;
  final PaymentGateway? gateway;

  @override
  State<PaymentGatewayPage> createState() => _PaymentGatewayPageState();
}

class _PaymentGatewayPageState extends State<PaymentGatewayPage> {
  late final PaymentGateway _gateway;
  late final GatewayChannel _channel;

  GatewayCharge? _charge;
  String? _loadError;
  bool _busy = false;
  String? _message;
  Timer? _poller;
  Timer? _ticker;
  Duration _remaining = Duration.zero;
  String _wallet = 'QRIS';

  final _formKey = GlobalKey<FormState>();
  final _numberCtl = TextEditingController();
  final _expiryCtl = TextEditingController();
  final _cvvCtl = TextEditingController();
  final _nameCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? SandboxPaymentGateway();
    _channel = gatewayChannelFor(widget.method) ?? GatewayChannel.qris;
    _createCharge();
  }

  @override
  void dispose() {
    _poller?.cancel();
    _ticker?.cancel();
    _numberCtl.dispose();
    _expiryCtl.dispose();
    _cvvCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _createCharge() async {
    setState(() {
      _loadError = null;
      _charge = null;
    });
    try {
      final charge = await _gateway.createCharge(
        orderRef: widget.orderRef,
        amount: widget.amount,
        channel: _channel,
        bank: widget.method,
      );
      if (!mounted) return;
      setState(() => _charge = charge);
      _startTimers(charge);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = 'Gagal membuat tagihan. Coba lagi.');
    }
  }

  void _startTimers(GatewayCharge charge) {
    void tick() {
      final left = charge.expiresAt.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _remaining = left.isNegative ? Duration.zero : left);
    }

    tick();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());

    if (_channel != GatewayChannel.card) {
      _poller?.cancel();
      _poller = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _check(silent: true),
      );
    }
  }

  Future<void> _check({bool silent = false}) async {
    final charge = _charge;
    if (charge == null || (_busy && !silent) || !mounted) return;
    if (!silent) setState(() => _busy = true);
    final result = await _gateway.checkStatus(charge);
    if (!mounted) return;
    if (result.ok) {
      _finish(result);
      return;
    }
    if (!silent) {
      setState(() {
        _busy = false;
        _message = result.error;
      });
    }
  }

  void _simulatePaid() {
    final charge = _charge;
    final gw = _gateway;
    if (charge == null || gw is! SandboxPaymentGateway) return;
    gw.simulateCustomerPaid(charge);
    _check();
  }

  void _finish(GatewayResult result) {
    _poller?.cancel();
    _ticker?.cancel();
    final info = _channel == GatewayChannel.qris && result.info == 'QRIS'
        ? _wallet
        : result.info;
    Navigator.of(context).pop(GatewayResult.success(result.reference!, info));
  }

  Future<void> _payCard() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final challenge = await _gateway.startCard(
        orderRef: widget.orderRef,
        amount: widget.amount,
        number: _numberCtl.text,
        expiry: _expiryCtl.text,
        cvv: _cvvCtl.text,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      final otp = await _askOtp(challenge);
      if (otp == null || !mounted) return;
      setState(() => _busy = true);
      final result = await _gateway.verifyOtp(challenge, otp);
      if (!mounted) return;
      if (result.ok) {
        _finish(result);
      } else {
        setState(() {
          _busy = false;
          _message = result.error;
        });
      }
    } on GatewayException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Terjadi gangguan jaringan. Coba lagi.';
      });
    }
  }

  Future<String?> _askOtp(CardChallenge challenge) {
    final ctl = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verifikasi 3-D Secure',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Masukkan kode OTP yang dikirim bank ke ${challenge.brand} '
              '•••• ${challenge.last4}.',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              'Sandbox: kode OTP uji adalah ${SandboxPaymentGateway.otpCode}',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Kode OTP',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(ctx).pop(ctl.text),
                child: const Text('KONFIRMASI'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan pembayaran?'),
        content: const Text(
          'Pesanan belum dibuat dan keranjang Anda tetap tersimpan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Lanjut bayar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  String _clock(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours >= 1) {
      return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    }
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave()) nav.pop(null);
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Pembayaran')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _createCharge,
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    final charge = _charge;
    if (charge == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summary(charge),
        const SizedBox(height: 12),
        if (_channel == GatewayChannel.virtualAccount) _vaPanel(charge),
        if (_channel == GatewayChannel.qris) _qrisPanel(charge),
        if (_channel == GatewayChannel.card) _cardPanel(),
        if (_message != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.redSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_message!)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Mode sandbox: tidak ada uang yang dipindahkan. Pembayaran '
          'sungguhan memerlukan akun dan kunci payment gateway Anda.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _summary(GatewayCharge charge) {
    final expired = _remaining == Duration.zero;
    return SurfaceCard(
      child: Column(
        children: [
          KeyValueRow(label: 'Metode', value: widget.method),
          KeyValueRow(label: 'Referensi', value: charge.reference),
          KeyValueRow(
            label: 'Total bayar',
            value: formatRupiah(widget.amount),
            bold: true,
          ),
          if (_channel != GatewayChannel.card)
            KeyValueRow(
              label: 'Bayar sebelum',
              value: expired ? 'Kedaluwarsa' : _clock(_remaining),
              valueColor: expired ? AppColors.red : null,
            ),
        ],
      ),
    );
  }

  Widget _checkButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: _busy ? null : () => _check(),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('CEK STATUS PEMBAYARAN'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _simulatePaid,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: const Text('Sandbox: simulasikan pembayaran berhasil'),
          ),
        ),
      ],
    );
  }

  Widget _vaPanel(GatewayCharge charge) {
    final va = charge.vaNumber ?? '';
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Virtual Account ${charge.bank}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  va,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Salin',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: va));
                  if (mounted) showAppToast(context, 'Nomor VA disalin');
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Cara bayar: buka m-banking / ATM, pilih Transfer › Virtual '
            'Account, masukkan nomor di atas, lalu konfirmasi. Halaman ini '
            'otomatis terbarui setelah pembayaran diterima.',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          _checkButtons(),
        ],
      ),
    );
  }

  Widget _qrisPanel(GatewayCharge charge) {
    return SurfaceCard(
      child: Column(
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final w in const ['QRIS', 'GoPay', 'OVO', 'ShopeePay'])
                ChoiceChip(
                  label: Text(w),
                  selected: _wallet == w,
                  onSelected: (_) => setState(() => _wallet = w),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: 200,
            height: 200,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomPaint(painter: _QrPainter(charge.qrData ?? '')),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kode QR contoh (bukan QR yang dapat dipindai). Pada gateway '
            'sungguhan di sini tampil QRIS dari penyedia.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _checkButtons(),
        ],
      ),
    );
  }

  Widget _cardPanel() {
    return SurfaceCard(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _numberCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(19),
                _GroupFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Nomor kartu',
                hintText: '4811 1111 1111 1114',
                prefixIcon: Icon(Icons.credit_card),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  luhnValid(v ?? '') ? null : 'Nomor kartu tidak valid',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nama di kartu',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Isi nama di kartu' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _expiryCtl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                      _ExpiryFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'MM/YY',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => cardExpiryValid(v ?? '', DateTime.now())
                        ? null
                        : 'Tidak valid',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cvvCtl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'CVV',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        RegExp(r'^\d{3,4}$').hasMatch(v ?? '')
                            ? null
                            : 'Tidak valid',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Kartu uji: 4811 1111 1111 1114 (berhasil), 4811 1111 0003 0002 '
                '(ditolak), 4811 1111 0002 0003 (saldo kurang). Masa berlaku: '
                'tanggal yang akan datang, CVV bebas.',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _payCard,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('BAYAR ${formatRupiah(widget.amount)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(digits[i]);
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final d = newValue.text.replaceAll('/', '');
    final text = d.length > 2 ? '${d.substring(0, 2)}/${d.substring(2)}' : d;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Pola kotak mirip QR (hanya ilustrasi, dibuat dari data tagihan).
class _QrPainter extends CustomPainter {
  _QrPainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    const n = 25;
    final cell = size.width / n;
    final paint = Paint()..color = Colors.black;
    var seed = 17;
    for (final c in data.codeUnits) {
      seed = (seed * 31 + c) & 0x7fffffff;
    }
    bool finder(int x, int y) =>
        (x < 8 && y < 8) || (x >= n - 8 && y < 8) || (x < 8 && y >= n - 8);

    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (finder(x, y)) continue;
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        if ((seed >> 16) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            paint,
          );
        }
      }
    }
    void eye(int ox, int oy) {
      canvas.drawRect(
          Rect.fromLTWH(ox * cell, oy * cell, 7 * cell, 7 * cell), paint);
      canvas.drawRect(
        Rect.fromLTWH((ox + 1) * cell, (oy + 1) * cell, 5 * cell, 5 * cell),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH((ox + 2) * cell, (oy + 2) * cell, 3 * cell, 3 * cell),
        paint,
      );
    }

    eye(0, 0);
    eye(n - 7, 0);
    eye(0, n - 7);
  }

  @override
  bool shouldRepaint(covariant _QrPainter old) => old.data != data;
}
