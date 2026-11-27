import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

/// Penyimpanan permanen berbasis `shared_preferences`
/// (Android/iOS: SharedPreferences, Web: localStorage).
class PrefsStore implements KeyValueStore {
  PrefsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  bool get isPersistent => true;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}
