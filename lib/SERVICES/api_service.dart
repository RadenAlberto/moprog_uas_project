import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../MODELS/product_model.dart';
import '../UTILS/key_value_store.dart';
import 'product_json.dart';

const String _kBaseUrlKey = 'api_base_url_v1';
const String _kSessionKey = 'api_session_v1';
const String _kQueueKey = 'api_feedback_queue_v1';
const Duration _kTimeout = Duration(seconds: 6);
const int _kMaxQueue = 200;

/// Hasil panggilan ke server.
class ApiResponse {
  const ApiResponse({this.status = 0, this.body, this.error, this.offline = false});

  final int status;
  final Map<String, dynamic>? body;

  /// Pesan error siap tampil (null bila sukses).
  final String? error;

  /// `true` bila server tidak terjangkau (internet mati / server belum jalan).
  final bool offline;

  bool get ok => error == null && status >= 200 && status < 300;
}

/// Klien REST ke server UNIQLO PLUS (lihat folder `backend/`).
///
/// Server menyimpan database produk, akun member, profil gaya, dan umpan
/// balik semua pengguna. Bila server tidak terjangkau, aplikasi tetap
/// berjalan dengan data lokal ([isOnline] = false).
class ApiService extends ChangeNotifier {
  ApiService({KeyValueStore? store, http.Client? client})
      : _store = store ?? MemoryStore(),
        _client = client ?? http.Client() {
    _baseUrl = _store.getString(_kBaseUrlKey) ?? defaultBaseUrl();
    _restoreSession();
  }

  final KeyValueStore _store;
  final http.Client _client;

  late String _baseUrl;
  String? _token;
  String? _sessionEmail;
  bool _online = false;
  bool _checked = false;
  String? _lastOperationError;
  Future<void> Function()? onUnauthorized;

  /// Alamat server bawaan sesuai platform.
  static String defaultBaseUrl() {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.contains('localhost') || origin.contains('127.0.0.1')) {
        return 'http://localhost:8000';
      }
      return origin;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 = komputer host dari dalam emulator Android.
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }

  String get baseUrl => _baseUrl;
  String? get lastOperationError => _lastOperationError;

  /// Terhubung ke server pada pengecekan terakhir.
  bool get isOnline => _online;

  /// Sudah pernah mengecek koneksi.
  bool get hasChecked => _checked;

  /// Sudah punya sesi login di server.
  bool get hasSession => _token != null;

  String? get sessionEmail => _sessionEmail;

  Future<void> setBaseUrl(String url) async {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.isEmpty) value = defaultBaseUrl();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    _baseUrl = value;
    _online = false;
    _checked = false;
    notifyListeners();
    try {
      await _store.setString(_kBaseUrlKey, value);
    } catch (_) {}
  }

  void _restoreSession() {
    final raw = _store.getString(_kSessionKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['token'] is String) {
        _token = data['token'] as String;
        _sessionEmail = data['email'] as String?;
      }
    } catch (_) {}
  }

  Future<void> _saveSession(String token, String email) async {
    _token = token;
    _sessionEmail = email;
    try {
      await _store.setString(
        _kSessionKey,
        jsonEncode({'token': token, 'email': email}),
      );
    } catch (_) {}
  }

  /// Menghapus sesi server (saat keluar dari akun).
  Future<void> clearSession() async {
    _token = null;
    _sessionEmail = null;
    try {
      await _store.remove(_kSessionKey);
    } catch (_) {}
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Permintaan dasar
  // ---------------------------------------------------------------------------

  Future<ApiResponse> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (auth && _token != null) 'Authorization': 'Bearer $_token',
    };
    try {
      late final http.Response response;
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(_kTimeout);
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(_kTimeout);
        case 'PUT':
          response = await _client
              .put(uri, headers: headers, body: jsonEncode(body ?? {}))
              .timeout(_kTimeout);
        case 'DELETE':
          response = await _client.delete(uri, headers: headers).timeout(_kTimeout);
        default:
          return const ApiResponse(error: 'Metode tidak didukung.');
      }
      _setOnline(true);

      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) json = Map<String, dynamic>.from(decoded);
      } catch (_) {}

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return ApiResponse(status: response.statusCode, body: json);
      }
      final message = json != null && json['error'] is String
          ? json['error'] as String
          : 'Server menolak permintaan (${response.statusCode}).';
      if (response.statusCode == 401 && auth) {
        // Token kedaluwarsa/tidak valid atau akun dinonaktifkan.
        _token = null;
        unawaited(clearSession());
        final callback = onUnauthorized;
        if (callback != null) await callback();
      }
      return ApiResponse(status: response.statusCode, body: json, error: message);
    } on TimeoutException {
      _setOnline(false);
      return const ApiResponse(
        error: 'Server tidak merespons. Periksa koneksi internet.',
        offline: true,
      );
    } catch (_) {
      _setOnline(false);
      return const ApiResponse(
        error: 'Tidak dapat terhubung ke server.',
        offline: true,
      );
    }
  }

  void _setOnline(bool value) {
    final changed = _online != value || !_checked;
    _online = value;
    _checked = true;
    if (changed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Endpoint
  // ---------------------------------------------------------------------------

  /// Mengecek koneksi ke server.
  Future<bool> ping() async {
    final response = await _request('GET', '/api/health');
    return response.ok;
  }

  /// Mengambil katalog produk dari database server.
  /// Mengembalikan `null` bila gagal; [popularity] diisi skor 0..1 per produk.
  Future<List<Product>?> fetchProducts({Map<String, double>? popularity}) async {
    final response = await _request('GET', '/api/products');
    if (!response.ok) return null;
    final list = response.body?['products'];
    if (list is! List) return null;
    final products = <Product>[];
    for (final item in list) {
      final product = productFromJson(item);
      if (product == null) continue;
      products.add(product);
      final value = popularityFromJson(item);
      if (popularity != null && value != null) popularity[product.id] = value;
    }
    return products.isEmpty ? null : products;
  }

  /// Daftar di server. Sesi disimpan bila sukses.
  Future<ApiResponse> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String address = '',
    String memberCode = '',
    int bonusPoints = 0,
  }) async {
    final response = await _request('POST', '/api/auth/register', body: {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'member_code': memberCode,
      'bonus_points': bonusPoints,
      'password': password,
    });
    final token = response.body?['token'];
    if (response.ok && token is String) {
      await _saveSession(token, email.trim().toLowerCase());
      notifyListeners();
    }
    return response;
  }

  /// Masuk di server. Sesi disimpan bila sukses.
  Future<ApiResponse> login(String email, String password) async {
    final response = await _request('POST', '/api/auth/login', body: {
      'email': email,
      'password': password,
    });
    final token = response.body?['token'];
    if (response.ok && token is String) {
      await _saveSession(token, email.trim().toLowerCase());
      notifyListeners();
    }
    return response;
  }

  /// Menyamakan akun lokal dengan server: coba masuk, bila email belum ada
  /// di server maka didaftarkan. Gagal diam-diam bila server tidak ada.
  Future<bool> ensureServerAccount({
    required String name,
    required String email,
    required String phone,
    required String password,
    String address = '',
    String memberCode = '',
    int bonusPoints = 0,
  }) async {
    final login = await this.login(email, password);
    if (login.ok) {
      await updateMember(name: name, phone: phone, address: address,
          memberCode: memberCode, bonusPoints: bonusPoints);
      return true;
    }
    if (login.offline) return false;
    if (login.status == 401 && (login.error ?? '').contains('belum terdaftar')) {
      final created = await register(
        name: name,
        email: email,
        phone: phone,
        password: password,
        address: address,
        memberCode: memberCode,
        bonusPoints: bonusPoints,
      );
      return created.ok;
    }
    return false;
  }

  /// Memperbarui atribut akun member pada database server.
  Future<bool> updateMember({
    String? name,
    String? phone,
    String? address,
    String? memberCode,
    int? bonusPoints,
  }) async {
    if (!hasSession) return false;
    final data = <String, dynamic>{
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
      if (memberCode != null) 'member_code': memberCode,
    };
    final response = await _request('PUT', '/api/me', body: data, auth: true);
    return response.ok;
  }

  /// Sinkronisasi keranjang, wishlist, pesanan, aktivitas, dan poin member.
  Future<bool> syncMemberData({
    required List<Map<String, dynamic>> cart,
    required List<String> wishlist,
    required List<Map<String, dynamic>> orders,
    required List<Map<String, dynamic>> activities,
    required List<Map<String, dynamic>> reviews,
    required Map<String, dynamic> member,
    required int bonusPoints,
  }) async {
    if (!hasSession) return false;
    final response = await _request('POST', '/api/member/sync', auth: true, body: {
      'cart': cart,
      'wishlist': wishlist,
      'orders': orders,
      'activities': activities,
      'reviews': reviews,
      'member': member,
      'bonus_points': bonusPoints,
    });
    return response.ok;
  }

  String _memberBootstrapKey(String memberCode) => 'member_bootstrap_v1_$memberCode';

  bool hasMemberBootstrap(String memberCode) =>
      _store.getString(_memberBootstrapKey(memberCode)) == '1';

  Future<void> markMemberBootstrap(String memberCode) =>
      _store.setString(_memberBootstrapKey(memberCode), '1');

  /// Mengambil seluruh data member yang disimpan server untuk pemulihan lintas perangkat.
  Future<Map<String, dynamic>?> fetchMemberBootstrap() async {
    if (!hasSession) return null;
    final response = await _request('GET', '/api/member/bootstrap', auth: true);
    return response.ok ? response.body : null;
  }

  /// Mengambil buku alamat milik member yang sedang login.
  Future<List<Map<String, dynamic>>?> fetchAddresses() async {
    if (!hasSession) return null;
    final response = await _request('GET', '/api/addresses', auth: true);
    if (!response.ok || response.body?['addresses'] is! List) return null;
    return [for (final item in response.body!['addresses'] as List)
      if (item is Map) Map<String, dynamic>.from(item)];
  }

  Future<Map<String, dynamic>?> saveAddress({
    int? id, required String recipientName, required String phone,
    required String address, String city = '', String postalCode = '',
    String label = 'Rumah', bool isDefault = false,
  }) async {
    if (!hasSession) return null;
    final body = {'recipient_name': recipientName, 'phone': phone,
      'address': address, 'city': city, 'postal_code': postalCode,
      'label': label, 'is_default': isDefault};
    final response = await _request(id == null ? 'POST' : 'PUT',
      id == null ? '/api/addresses' : '/api/addresses/$id',
      auth: true, body: body);
    return response.ok ? (response.body?['address'] is Map
      ? Map<String, dynamic>.from(response.body!['address'] as Map)
      : <String, dynamic>{...body, if (id != null) 'id': id}) : null;
  }

  Future<bool> setDefaultAddress(int id) async {
    if (!hasSession) return false;
    return (await _request('POST', '/api/addresses/$id/default', auth: true)).ok;
  }

  Future<bool> deleteAddress(int id) async {
    if (!hasSession) return false;
    return (await _request('DELETE', '/api/addresses/$id', auth: true)).ok;
  }

  Future<bool> saveFulfillment({
    required String orderId,
    required String type,
    String? storeId,
    String? storeName,
    String? storeAddress,
    int? addressId,
    String? deliveryService,
  }) async {
    if (!hasSession) return false;
    final response = await _request('POST', '/api/orders/$orderId/fulfillment',
      auth: true, body: {
        'type': type,
        if (storeId != null) 'store_id': storeId,
        if (storeName != null) 'store_name': storeName,
        if (storeAddress != null) 'store_address': storeAddress,
        if (addressId != null) 'address_id': addressId,
        if (deliveryService != null) 'delivery_service': deliveryService,
      });
    _lastOperationError = response.error;
    return response.ok;
  }

  Future<bool> simulatePayment(String orderId) async {
    if (!hasSession) return false;
    final response = await _request('POST', '/api/orders/$orderId/simulate-payment',
      auth: true, body: const {});
    return response.ok;
  }

  Future<bool> cancelOrder(String orderId) async {
    if (!hasSession) return false;
    final response = await _request('POST', '/api/orders/$orderId/cancel', auth: true, body: const {});
    // 404 berarti snapshot order belum sempat tersinkron; cancelledAt lokal
    // akan membuat server memasukkannya sebagai dibatalkan saat sync berikutnya.
    return response.ok || response.status == 404;
  }

  Future<int?> checkIn() async {
    if (!hasSession) return null;
    final response = await _request('POST', '/api/points/checkin', auth: true, body: const {});
    return response.ok ? (response.body?['reward'] as num?)?.toInt() : null;
  }

  /// Mengambil ulasan dari database server (termasuk ulasan contoh yang sudah dimigrasikan).
  Future<List<Map<String, dynamic>>?> fetchReviews() async {
    if (!hasSession) return null;
    final response = await _request('GET', '/api/reviews?product_id=all', auth: true);
    if (!response.ok || response.body?['reviews'] is! List) return null;
    return [for (final item in response.body!['reviews'] as List)
      if (item is Map) Map<String, dynamic>.from(item)];
  }

  /// Mengambil konten yang dikelola melalui control panel.
  Future<Map<String, List<Map<String, dynamic>>>?> fetchPublicContent() async {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final name in const ['news', 'vouchers', 'stores']) {
      final response = await _request('GET', '/api/$name');
      if (!response.ok) return null;
      final raw = response.body?[name];
      if (raw is! List) return null;
      result[name] = [
        for (final item in raw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    }
    return result;
  }

  /// Memberi tahu layar yang memakai data konten server agar membangun ulang.
  void notifyContentUpdated() => notifyListeners();

  /// Profil gaya + model ML milik member dari server.
  Future<Map<String, dynamic>?> fetchProfile() async {
    if (!hasSession) return null;
    final response = await _request('GET', '/api/profile', auth: true);
    return response.ok ? response.body : null;
  }

  Future<bool> saveProfile(
    Map<String, dynamic> profile,
    Map<String, dynamic> model,
  ) async {
    if (!hasSession) return false;
    final response = await _request(
      'PUT',
      '/api/profile',
      body: {'profile': profile, 'model': model},
      auth: true,
    );
    return response.ok;
  }

  /// Mengirim umpan balik (like/dislike/cart/view). Bila gagal, disimpan di
  /// antrean dan dicoba lagi pada [flushQueue].
  Future<void> sendFeedback(String productId, String action) async {
    if (!hasSession) return;
    final response = await _request(
      'POST',
      '/api/feedback',
      body: {'product_id': productId, 'action': action},
      auth: true,
    );
    if (!response.ok && response.offline) {
      _enqueue(productId, action);
    }
  }

  /// Skor popularitas semua produk dari seluruh pengguna.
  Future<Map<String, double>?> fetchPopularity() async {
    final response = await _request('GET', '/api/popularity');
    if (!response.ok) return null;
    final raw = response.body?['popularity'];
    if (raw is! Map) return null;
    final out = <String, double>{};
    raw.forEach((key, value) {
      if (key is String && value is num) {
        out[key] = value.toDouble().clamp(0.0, 1.0).toDouble();
      }
    });
    return out;
  }

  // ---------------------------------------------------------------------------
  // Antrean umpan balik offline
  // ---------------------------------------------------------------------------

  List<Map<String, String>> _readQueue() {
    final raw = _store.getString(_kQueueKey);
    if (raw == null) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return [
        for (final item in data)
          if (item is Map &&
              item['p'] is String &&
              item['a'] is String)
            {'p': item['p'] as String, 'a': item['a'] as String},
      ];
    } catch (_) {
      return [];
    }
  }

  void _writeQueue(List<Map<String, String>> queue) {
    try {
      unawaited(_store.setString(_kQueueKey, jsonEncode(queue)));
    } catch (_) {}
  }

  void _enqueue(String productId, String action) {
    final queue = _readQueue()..add({'p': productId, 'a': action});
    while (queue.length > _kMaxQueue) {
      queue.removeAt(0);
    }
    _writeQueue(queue);
  }

  /// Jumlah umpan balik yang menunggu dikirim.
  int get pendingFeedback => _readQueue().length;

  /// Mengirim ulang umpan balik yang tertunda.
  Future<void> flushQueue() async {
    if (!hasSession) return;
    final queue = _readQueue();
    if (queue.isEmpty) return;
    final remaining = <Map<String, String>>[];
    var failed = false;
    for (final item in queue) {
      if (failed) {
        remaining.add(item);
        continue;
      }
      final response = await _request(
        'POST',
        '/api/feedback',
        body: {'product_id': item['p'], 'action': item['a']},
        auth: true,
      );
      if (!response.ok && response.offline) {
        failed = true;
        remaining.add(item);
      }
    }
    _writeQueue(remaining);
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    // Panggilan jaringan bisa selesai setelah service dibuang.
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
