import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../SERVICES/fit_engine.dart';
import '../UTILS/key_value_store.dart';

const String _kFitKey = 'fit_profile_v1_';

/// Profil tubuh untuk Kalkulator Fit & Size (per akun).
class FitProvider extends ChangeNotifier {
  FitProvider({required KeyValueStore store}) : _store = store;

  final KeyValueStore _store;

  FitProfile _profile = const FitProfile();
  bool _saved = false;
  String? _owner;
  bool _ready = false;

  FitProfile get profile => _profile;

  /// `true` bila pengguna pernah menyimpan profil ukuran.
  bool get hasSavedProfile => _saved;

  String get _key => '$_kFitKey${_owner ?? 'guest'}';

  void setActiveMember(String? memberId) {
    if (_ready && _owner == memberId) return;
    _owner = memberId;
    _ready = true;
    FitProfile? loaded;
    final raw = _store.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        loaded = FitProfile.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    _profile = loaded ?? const FitProfile();
    _saved = loaded != null;
    notifyListeners();
  }

  void update(FitProfile profile) {
    _profile = profile;
    _saved = true;
    unawaited(_store.setString(_key, jsonEncode(profile.toJson())));
    notifyListeners();
  }

  /// Mengisi profil awal (mis. dari profil gaya) bila belum pernah disimpan.
  void seedIfEmpty(FitProfile seed) {
    if (_saved) return;
    _profile = seed;
    notifyListeners();
  }

  FitResult recommend(Product product) => recommendSize(_profile, product);
}
