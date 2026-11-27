/// Abstraksi penyimpanan key-value sederhana.
///
/// Provider tidak bergantung langsung pada plugin `shared_preferences`.
/// Aplikasi memakai `PrefsStore` (permanen), sedangkan unit test dan mode
/// darurat memakai `MemoryStore` (hilang saat aplikasi ditutup).
abstract class KeyValueStore {
  /// `true` bila data bertahan setelah aplikasi ditutup.
  bool get isPersistent;

  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// Penyimpanan di memori saja.
class MemoryStore implements KeyValueStore {
  final Map<String, String> _data = <String, String>{};

  @override
  bool get isPersistent => false;

  @override
  String? getString(String key) => _data[key];

  @override
  Future<void> setString(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _data.remove(key);
  }
}
