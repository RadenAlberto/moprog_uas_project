import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../MODELS/product_model.dart';
import '../MODELS/style_model.dart';
import '../SERVICES/api_service.dart';
import '../SERVICES/product_attributes.dart';
import '../SERVICES/style_recommender.dart';
import '../UTILS/key_value_store.dart';
import 'app_state.dart';

const String _kProfileKey = 'style_profile_v1_';
const String _kModelKey = 'style_model_v1_';
const String _kVotesKey = 'style_votes_v1_';
const String _kSavedAtKey = 'style_saved_at_v1_';
const String _kGuest = 'guest';

/// Jenis umpan balik pengguna terhadap sebuah rekomendasi.
enum StyleFeedback { like, dislike, cart }

/// Mengelola profil gaya (tinggi, berat, wajah, warna kulit), model ML
/// personal, hasil rekomendasi, serta sinkronisasi ke server.
///
/// Data disimpan per akun member (atau "tamu"). Foto tidak pernah disimpan;
/// hanya hasil ukur (bentuk wajah, nada kulit, tinggi, berat).
class StyleProvider extends ChangeNotifier {
  StyleProvider({
    required KeyValueStore store,
    required ApiService api,
    required AppState app,
  })  : _store = store,
        _api = api,
        _app = app {
    _loadOwner(_kGuest);
  }

  final KeyValueStore _store;
  final ApiService _api;
  final AppState _app;
  final StyleRecommender _recommender = const StyleRecommender();

  String _owner = _kGuest;
  BodyProfile? _profile;
  StyleModel _model = StyleModel();
  final Map<String, int> _votes = {};
  int _savedAt = 0;

  Map<String, double> _remotePopularity = {};
  bool _syncing = false;

  // Cache hasil rekomendasi.
  bool _dirty = true;
  List<Product>? _cachedCatalog;
  List<StyleRecommendation> _recs = const [];
  List<OutfitSuggestion> _outfits = const [];

  bool _disposed = false;

  @override
  void notifyListeners() {
    // Pekerjaan async (server) bisa selesai setelah provider dibuang.
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Getter
  // ---------------------------------------------------------------------------

  BodyProfile? get profile => _profile;

  bool get hasProfile => _profile != null;

  /// `true` bila profil sudah menyertakan hasil analisis wajah/kulit.
  bool get hasAnalysis => _profile?.hasFace ?? false;

  StyleModel get model => _model;

  /// Jumlah umpan balik yang sudah dipelajari model.
  int get learnedSamples => _model.samples;

  bool get isSyncing => _syncing;

  ApiService get api => _api;

  /// 1 = disukai, -1 = ditandai kurang cocok, 0 = belum dinilai.
  int voteFor(String productId) => _votes[productId] ?? 0;

  /// Rekomendasi terurut. Produk yang ditandai kurang cocok dipindah ke belakang.
  List<StyleRecommendation> get recommendations {
    _ensure();
    return _recs;
  }

  /// Set pakaian lengkap hasil rekomendasi.
  List<OutfitSuggestion> get outfits {
    _ensure();
    return _outfits;
  }

  List<String> get tips {
    final p = _profile;
    return p == null ? const [] : _recommender.styleTips(p);
  }

  List<ColorFamily> get bestColors {
    final p = _profile;
    return p == null ? const [] : _recommender.bestColorFamilies(p);
  }

  double popularityOf(Product product) {
    final rating = _app.ratingOf(product);
    final fromRating = rating.count > 0 ? (rating.average / 5).clamp(0.0, 1.0) : 0.5;
    final remote = _remotePopularity[product.id];
    if (remote == null) return fromRating.toDouble();
    return (0.5 * fromRating + 0.5 * remote).toDouble();
  }

  void _ensure() {
    final catalog = _app.allProducts;
    if (!_dirty && identical(catalog, _cachedCatalog)) return;
    _cachedCatalog = catalog;
    _dirty = false;

    final p = _profile;
    if (p == null) {
      _recs = const [];
      _outfits = const [];
      return;
    }
    final ranked = _recommender.recommend(
      profile: p,
      products: catalog,
      model: _model,
      popularity: popularityOf,
    );
    final liked = <StyleRecommendation>[];
    final disliked = <StyleRecommendation>[];
    for (final rec in ranked) {
      if (voteFor(rec.product.id) < 0) {
        disliked.add(rec);
      } else {
        liked.add(rec);
      }
    }
    _recs = [...liked, ...disliked];
    _outfits = _recommender.buildOutfits(p, liked.isEmpty ? ranked : liked);
  }

  // ---------------------------------------------------------------------------
  // Profil
  // ---------------------------------------------------------------------------

  /// Menyimpan profil hasil analisis/pengisian data.
  Future<void> saveProfile(BodyProfile profile) async {
    _profile = profile;
    _touch();
    notifyListeners();
    await _persist();
    unawaited(pushRemote());
  }

  /// Menghapus profil (foto tidak pernah disimpan, jadi hanya data hasil ukur).
  Future<void> clearProfile() async {
    _profile = null;
    _votes.clear();
    _model = StyleModel();
    _touch();
    notifyListeners();
    await _persist();
    unawaited(pushRemote());
  }

  void _touch() {
    _dirty = true;
    _savedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  // ---------------------------------------------------------------------------
  // Umpan balik -> pembelajaran model
  // ---------------------------------------------------------------------------

  /// Model belajar dari umpan balik [kind] pada rekomendasi [rec].
  Future<void> giveFeedback(
    StyleRecommendation rec,
    StyleFeedback kind,
  ) async {
    final positive = kind != StyleFeedback.dislike;
    _model.learnFrom(
      rec.product,
      rec.features,
      positive: positive,
      rate: kind == StyleFeedback.cart ? 0.18 : 0.12,
    );
    switch (kind) {
      case StyleFeedback.like:
        _votes[rec.product.id] = 1;
      case StyleFeedback.dislike:
        _votes[rec.product.id] = -1;
      case StyleFeedback.cart:
        _votes.putIfAbsent(rec.product.id, () => 1);
    }
    _touch();
    notifyListeners();
    await _persist();

    final action = switch (kind) {
      StyleFeedback.like => 'like',
      StyleFeedback.dislike => 'dislike',
      StyleFeedback.cart => 'cart',
    };
    unawaited(_api.sendFeedback(rec.product.id, action));
    unawaited(pushRemote());
  }

  // ---------------------------------------------------------------------------
  // Akun
  // ---------------------------------------------------------------------------

  /// Dipanggil saat status login berubah. Data profil berpindah ke akun aktif;
  /// profil tamu diadopsi bila akun belum punya profil.
  void setActiveMember(String? memberId) {
    final next = memberId ?? _kGuest;
    if (next == _owner) return;

    final wasGuest = _owner == _kGuest;
    final guestProfile = _profile;
    final guestModel = _model;
    final guestVotes = Map<String, int>.from(_votes);

    _loadOwner(next);

    if (wasGuest && next != _kGuest && _profile == null && guestProfile != null) {
      _profile = guestProfile;
      _model = guestModel;
      _votes
        ..clear()
        ..addAll(guestVotes);
      _touch();
      unawaited(_persist());
    }
    _dirty = true;
    notifyListeners();
  }

  /// Dipanggil setelah akun lokal berhasil disamakan dengan server.
  Future<void> afterServerLogin() async {
    await _api.flushQueue();
    await pullRemote();
  }

  // ---------------------------------------------------------------------------
  // Server
  // ---------------------------------------------------------------------------

  /// Mengecek server, mengambil katalog produk dan popularitas, lalu
  /// menyamakan profil. Aman dipanggil berulang; gagal tanpa error bila
  /// server tidak tersedia.
  Future<bool> refreshFromServer() async {
    if (_syncing) return _api.isOnline;
    _syncing = true;
    notifyListeners();
    try {
      final online = await _api.ping();
      if (!online) return false;

      final popularity = <String, double>{};
      final products = await _api.fetchProducts(popularity: popularity);
      if (products != null) {
        _remotePopularity = popularity;
        _app.replaceCatalog(products);
      }
      await _api.flushQueue();
      await pullRemote();
      _dirty = true;
      return true;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Menyamakan profil & model dengan server (data yang lebih baru menang).
  Future<void> pullRemote() async {
    if (_owner == _kGuest || !_api.hasSession) return;
    final data = await _api.fetchProfile();
    if (data == null) return;

    final remoteProfile = BodyProfile.fromJson(data['profile']);
    final updated = data['updated_at'];
    final remoteUpdated = updated is num ? updated.toInt() : 0;

    if (remoteProfile != null && remoteUpdated > _savedAt) {
      _profile = remoteProfile;
      _model = StyleModel.fromJson(data['model']);
      _savedAt = remoteUpdated;
      _dirty = true;
      notifyListeners();
      await _persist();
    } else if (_profile != null) {
      await pushRemote();
    }
  }

  /// Mengirim profil & model ke server (bila sudah login di server).
  Future<void> pushRemote() async {
    final p = _profile;
    if (p == null || _owner == _kGuest || !_api.hasSession) return;
    await _api.saveProfile(p.toJson(), _model.toJson());
  }

  // ---------------------------------------------------------------------------
  // Penyimpanan lokal
  // ---------------------------------------------------------------------------

  Object? _decode(String key) {
    final raw = _store.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void _loadOwner(String owner) {
    _owner = owner;
    _profile = BodyProfile.fromJson(_decode('$_kProfileKey$owner'));
    _model = StyleModel.fromJson(_decode('$_kModelKey$owner'));
    _votes.clear();
    final votes = _decode('$_kVotesKey$owner');
    if (votes is Map) {
      votes.forEach((key, value) {
        if (key is String && value is num && (value == 1 || value == -1)) {
          _votes[key] = value.toInt();
        }
      });
    }
    _savedAt = int.tryParse(_store.getString('$_kSavedAtKey$owner') ?? '') ?? 0;
    _dirty = true;
  }

  Future<void> _save(String key, String value) async {
    try {
      await _store.setString(key, value);
    } catch (_) {
      // Penyimpanan gagal tidak boleh menjatuhkan aplikasi.
    }
  }

  Future<void> _persist() async {
    final owner = _owner;
    final p = _profile;
    if (p == null) {
      try {
        await _store.remove('$_kProfileKey$owner');
      } catch (_) {}
    } else {
      await _save('$_kProfileKey$owner', jsonEncode(p.toJson()));
    }
    await _save('$_kModelKey$owner', jsonEncode(_model.toJson()));
    await _save('$_kVotesKey$owner', jsonEncode(_votes));
    await _save('$_kSavedAtKey$owner', '$_savedAt');
  }
}
