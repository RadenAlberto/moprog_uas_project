import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/style_provider.dart';
import '../SERVICES/api_service.dart';
import '../UTILS/app_theme.dart';

/// Penanda koneksi ke server. Ketuk untuk membuka pengaturan alamat server.
class ServerStatusChip extends StatelessWidget {
  const ServerStatusChip({super.key});

  @override
  Widget build(BuildContext context) {
    final online = context.select<ApiService, bool>((api) => api.isOnline);
    final color = online ? AppColors.success : AppColors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showServerSettings(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              online ? 'Terhubung ke server' : 'Mode offline',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog pengaturan alamat server + tes koneksi.
Future<void> showServerSettings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ServerSettingsDialog(),
  );
}

class _ServerSettingsDialog extends StatefulWidget {
  const _ServerSettingsDialog();

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  late final TextEditingController _controller;
  bool _testing = false;
  String? _result;
  bool? _success;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<ApiService>().baseUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final api = context.read<ApiService>();
    final style = context.read<StyleProvider>();
    setState(() {
      _testing = true;
      _result = null;
      _success = null;
    });
    await api.setBaseUrl(_controller.text);
    final ok = await style.refreshFromServer();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _success = ok;
      _result = ok
          ? 'Terhubung. Katalog dan profil disinkronkan dengan server.'
          : 'Server tidak terjangkau. Aplikasi tetap berjalan dengan data '
              'di perangkat (mode offline).';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server UNIQLO PLUS'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Server menyimpan database produk, akun member, dan profil gaya. '
              'Jalankan "python3 server.py" di folder backend.',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Alamat server',
                hintText: 'http://10.0.2.2:8000',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Emulator Android: http://10.0.2.2:8000\n'
              'HP asli: alamat IP komputer, mis. http://192.168.1.10:8000\n'
              'Windows/Web: http://localhost:8000',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Text(
                _result!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _success == true ? AppColors.success : AppColors.redDark,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: _testing ? null : _save,
          child: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Simpan & tes'),
        ),
      ],
    );
  }
}
