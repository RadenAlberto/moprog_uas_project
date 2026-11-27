/// Kumpulan validator untuk `TextFormField`.
class Validators {
  Validators._();

  static String? notEmpty(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName wajib diisi';
    }
    return null;
  }

  static String? name(String? value) {
    final empty = notEmpty(value, 'Nama');
    if (empty != null) return empty;
    if (value!.trim().length < 3) return 'Nama minimal 3 karakter';
    return null;
  }

  static String? email(String? value) {
    final empty = notEmpty(value, 'Email');
    if (empty != null) return empty;
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value!.trim());
    if (!ok) return 'Format email tidak valid';
    return null;
  }

  static String? phone(String? value) {
    final empty = notEmpty(value, 'Nomor HP');
    if (empty != null) return empty;
    final digits = value!.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 9 || digits.length > 15) {
      return 'Nomor HP harus 9-15 digit';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password wajib diisi';
    if (value.length < 6) return 'Password minimal 6 karakter';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Konfirmasi password wajib diisi';
    if (value != original) return 'Konfirmasi password tidak sama';
    return null;
  }
}
