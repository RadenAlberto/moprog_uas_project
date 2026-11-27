import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/auth_provider.dart';
import '../UTILS/toast.dart';
import '../UTILS/validators.dart';

/// Edit data profil member dan ubah password.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _savingProfile = false;
  bool _savingPassword = false;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    final member = context.read<AuthProvider>().currentMember;
    _nameController = TextEditingController(text: member?.name ?? '');
    _phoneController = TextEditingController(text: member?.phone ?? '');
    _addressController = TextEditingController(text: member?.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    if (!(_profileKey.currentState?.validate() ?? false)) return;

    setState(() => _savingProfile = true);
    final auth = context.read<AuthProvider>();
    await auth.updateProfile(
      name: _nameController.text,
      phone: _phoneController.text,
      address: _addressController.text,
    );
    if (!mounted) return;
    setState(() => _savingProfile = false);
    showAppToast(context, 'Profil berhasil diperbarui');
  }

  Future<void> _changePassword() async {
    if (_savingPassword) return;
    if (!(_passwordKey.currentState?.validate() ?? false)) return;

    setState(() {
      _savingPassword = true;
      _passwordError = null;
    });
    final auth = context.read<AuthProvider>();
    final error = await auth.changePassword(
      _oldPasswordController.text,
      _newPasswordController.text,
    );
    if (!mounted) return;
    setState(() {
      _savingPassword = false;
      _passwordError = error;
    });
    if (error == null) {
      _oldPasswordController.clear();
      _newPasswordController.clear();
      _confirmController.clear();
      showAppToast(context, 'Password berhasil diubah');
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = context.watch<AuthProvider>().currentMember;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'EDIT PROFIL',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 16,
          ),
        ),
      ),
      body: member == null
          ? const Center(child: Text('Anda belum masuk.'))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Form(
                          key: _profileKey,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: _cardDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Data Diri',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  initialValue: member.email,
                                  enabled: false,
                                  decoration: const InputDecoration(
                                    labelText: 'Email (tidak dapat diubah)',
                                    prefixIcon: Icon(Icons.mail_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  initialValue: member.id,
                                  enabled: false,
                                  decoration: const InputDecoration(
                                    labelText: 'ID Member',
                                    prefixIcon: Icon(Icons.badge_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _nameController,
                                  textCapitalization: TextCapitalization.words,
                                  validator: Validators.name,
                                  decoration: const InputDecoration(
                                    labelText: 'Nama lengkap',
                                    prefixIcon: Icon(Icons.person_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  validator: Validators.phone,
                                  decoration: const InputDecoration(
                                    labelText: 'Nomor HP',
                                    prefixIcon: Icon(Icons.phone_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _addressController,
                                  maxLines: 3,
                                  keyboardType: TextInputType.streetAddress,
                                  decoration: const InputDecoration(
                                    labelText: 'Alamat pengiriman utama',
                                    prefixIcon:
                                        Icon(Icons.location_on_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _PrimaryButton(
                                  label: 'SIMPAN PERUBAHAN',
                                  loading: _savingProfile,
                                  onPressed: _saveProfile,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Form(
                          key: _passwordKey,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: _cardDecoration(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Ubah Password',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextFormField(
                                  controller: _oldPasswordController,
                                  obscureText: true,
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Password lama wajib diisi'
                                      : null,
                                  decoration: const InputDecoration(
                                    labelText: 'Password lama',
                                    prefixIcon: Icon(Icons.lock_outline),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _newPasswordController,
                                  obscureText: true,
                                  validator: Validators.password,
                                  decoration: const InputDecoration(
                                    labelText: 'Password baru (min. 6 karakter)',
                                    prefixIcon: Icon(Icons.lock_reset_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _confirmController,
                                  obscureText: true,
                                  validator: (v) => Validators.confirmPassword(
                                    v,
                                    _newPasswordController.text,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Ulangi password baru',
                                    prefixIcon: Icon(Icons.lock_reset_outlined),
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                if (_passwordError != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _passwordError!,
                                    style: TextStyle(
                                      color: Colors.red.shade700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 16),
                                _PrimaryButton(
                                  label: 'UBAH PASSWORD',
                                  loading: _savingPassword,
                                  onPressed: _changePassword,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEC1C24),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
      ),
    );
  }
}
