import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../PROVIDERS/fit_provider.dart';
import '../MODELS/review_model.dart';
import '../PROVIDERS/ootd_provider.dart';
import '../PROVIDERS/style_provider.dart';
import '../PROVIDERS/stylist_provider.dart';
import '../PROVIDERS/tracker_provider.dart';
import '../PROVIDERS/wardrobe_provider.dart';
import '../DATA/store_data.dart';
import '../DATA/voucher_data.dart';
import '../MODELS/member_model.dart';
import '../MODELS/news_model.dart';
import '../MODELS/store_model.dart';
import '../MODELS/voucher_model.dart';
import '../SERVICES/api_service.dart';
import '../SERVICES/photo_store.dart';
import '../UTILS/key_value_store.dart';

/// Membuat [AuthProvider], [AppState], [ApiService], dan [StyleProvider] dari
/// satu penyimpanan dan menghubungkannya: setiap kali status login berubah,
/// keranjang, wishlist, dan profil gaya berpindah ke akun yang aktif (atau
/// ke mode tamu). Saat login, akun juga disamakan dengan server.
class AppProviders extends StatefulWidget {
  const AppProviders({
    super.key,
    required this.store,
    required this.child,
    this.autoSync = true,
    this.photoStore,
  });

  final KeyValueStore store;
  final Widget child;

  /// Penyimpanan foto lemari digital & OOTD. Bawaan: berkas di folder
  /// dokumen aplikasi.
  final PhotoStore? photoStore;

  /// Mengambil katalog dari server saat aplikasi dibuka. Dimatikan pada
  /// pengujian agar tidak ada permintaan jaringan.
  final bool autoSync;

  @override
  State<AppProviders> createState() => _AppProvidersState();
}

class _AppProvidersState extends State<AppProviders> {
  late final AuthProvider _auth;
  late final AppState _app;
  late final ApiService _api;
  late final StyleProvider _style;
  late final PhotoStore _photos;
  late final WardrobeProvider _wardrobe;
  late final StylistProvider _stylist;
  late final TrackerProvider _tracker;
  late final FitProvider _fit;
  late final OotdProvider _ootd;
  Future<void> _memberSyncQueue = Future<void>.value();
  bool _serverBootstrapLoaded = false;
  bool _serverReviewsLoaded = false;

  @override
  void initState() {
    super.initState();
    _auth = AuthProvider(store: widget.store);
    _app = AppState(store: widget.store);
    _api = ApiService(store: widget.store);
    _api.onUnauthorized = () => _auth.logout();
    _style = StyleProvider(store: widget.store, api: _api, app: _app);

    // Fitur Studio: lemari digital, stylist, price tracker, ukuran, OOTD.
    _photos = widget.photoStore ?? FilePhotoStore();
    _wardrobe = WardrobeProvider(store: widget.store, photos: _photos);
    _stylist = StylistProvider(store: widget.store);
    _tracker = TrackerProvider(store: widget.store, app: _app);
    _fit = FitProvider(store: widget.store);
    _ootd = OotdProvider(store: widget.store, photos: _photos);
    _tracker.refresher = () => _style.refreshFromServer();

    // Pulihkan keranjang/wishlist/profil gaya milik sesi yang sedang aktif.
    final memberId = _auth.currentMember?.id;
    _app.setActiveMember(memberId);
    _style.setActiveMember(memberId);
    _setStudioMember(memberId);
    _auth.addListener(_syncMember);

    // Samakan akun lokal dengan server saat masuk/daftar, dan putuskan sesi
    // server saat keluar.
    _auth.remoteLogin = (email, password) async {
      final response = await _api.login(email, password);
      if (!response.ok) throw Exception(response.error ?? 'Login server gagal.');
      final user = response.body?['user'];
      if (user is! Map) throw Exception('Respons akun server tidak valid.');
      return Map<String, dynamic>.from(user);
    };
    _auth.remoteRegister = (name, email, phone, password, address, memberCode, bonusPoints) async {
      final response = await _api.register(name: name, email: email, phone: phone,
        password: password, address: address, memberCode: memberCode,
        bonusPoints: bonusPoints);
      if (!response.ok) throw Exception(response.error ?? 'Registrasi server gagal.');
      final user = response.body?['user'];
      if (user is! Map) throw Exception('Respons registrasi server tidak valid.');
      return Map<String, dynamic>.from(user);
    };
    _auth.onCancelOrder = (orderId) => _api.cancelOrder(orderId);
    _auth.onSaveFulfillment = (orderId, selection) => _api.saveFulfillment(
      orderId: orderId,
      type: (selection['type'] ?? '').toString(),
      storeId: selection['store_id']?.toString(),
      storeName: selection['store_name']?.toString(),
      storeAddress: selection['store_address']?.toString(),
      addressId: (selection['address_id'] as num?)?.toInt(),
      deliveryService: selection['delivery_service']?.toString(),
    );
    _auth.onSimulatePayment = (orderId) => _api.simulatePayment(orderId);
    _auth.onOrderCreated = () async {
      await _memberSyncQueue;
      await _syncMemberDataNow();
    };
    _auth.onCheckIn = () => _api.checkIn();
    _auth.onFetchBootstrap = () => _api.fetchMemberBootstrap();
    _auth.onMemberDataChanged = _scheduleMemberSync;
    _app.onMemberDataChanged = _scheduleMemberSync;
    _app.onProductFeedback = (productId, action) {
      unawaited(_api.sendFeedback(productId, action));
    };
    _auth.onSignedIn = (member, password) async {
      await _style.refreshFromServer();
      await _style.afterServerLogin();
      await _restoreServerMemberData();
      await _syncMemberDataNow();
    };
    _auth.onSignedOut = () { _serverBootstrapLoaded = false; _serverReviewsLoaded = false; unawaited(_api.clearSession()); };
    if (!widget.autoSync) {
      // Mode test/offline: jangan mengakses jaringan.
      _auth.remoteLogin = null;
      _auth.remoteRegister = null;
      _auth.onSignedIn = null;
      _auth.onCancelOrder = null;
      _auth.onCheckIn = null;
      _auth.onFetchBootstrap = null;
      _app.onProductFeedback = null;
    }

    // Ambil katalog produk dari database server (bila tersedia).
    if (widget.autoSync) {
      unawaited(_style.refreshFromServer());
      unawaited(_syncPublicContent());
      _tracker.startAutoCheck();
      if (_api.hasSession && _auth.currentMember != null) {
        unawaited(_restoreAndSync());
      }
    }
  }

  Future<void> _restoreServerMemberData() async {
    if (!_api.hasSession || _auth.currentMember == null || _serverBootstrapLoaded) return;
    final payload = await _api.fetchMemberBootstrap();
    if (payload == null) return;
    final memberCode = _auth.currentMember!.id;
    final wasBootstrapped = _api.hasMemberBootstrap(memberCode);
    await _auth.applyServerBootstrap(payload);
    final cart = payload['cart'];
    final wishlist = payload['wishlist'];
    final serverHasShoppingData = (cart is List && cart.isNotEmpty) ||
        (wishlist is List && wishlist.isNotEmpty);
    if (serverHasShoppingData || wasBootstrapped) {
      _app.applyServerCartWishlist(
        cart: cart is List ? cart : const [],
        wishlist: wishlist is List ? wishlist : const [],
        replaceCart: wasBootstrapped || (cart is List && cart.isNotEmpty) || _app.cart.isEmpty,
        replaceWishlist: wasBootstrapped || (wishlist is List && wishlist.isNotEmpty) || _app.wishlist.isEmpty,
      );
    }
    // Kalau server sudah punya pesanan, applyServerBootstrap telah mengganti
    // riwayat lokal. Kalau belum, snapshot lokal akan diunggah secara insert-only.
    _serverBootstrapLoaded = true;
  }

  Future<void> _restoreAndSync() async {
    await _style.refreshFromServer();
    await _restoreServerMemberData();
    await _syncMemberDataNow();
  }

  void _scheduleMemberSync() {
    // Serialkan snapshot supaya request yang lebih lama tidak menimpa
    // perubahan terbaru (mis. cart berubah beberapa kali dengan cepat).
    _memberSyncQueue = _memberSyncQueue.then((_) => _syncMemberDataNow()).catchError((_) {});
  }

  Future<void> _syncMemberDataNow() async {
    if (!_api.hasSession || _auth.currentMember == null) return;
    final member = _auth.currentMember!;
    final synced = await _api.syncMemberData(
      cart: [
        for (final item in _app.cart)
          {
            'product_id': item.product.id,
            'color_code': item.selectedColor.toARGB32().toString(),
            'size': item.selectedSize,
            'quantity': item.quantity,
            'is_selected': item.isChecked,
          },
      ],
      wishlist: _app.wishlist.map((product) => product.id).toList(),
      orders: _auth.myOrders.map((order) => order.toJson()).toList(),
      activities: _auth.myActivities.map((event) => event.toJson()).toList(),
      reviews: _app.userReviews.map((review) => review.toJson()).toList(),
      member: {
        'name': member.name,
        'email': member.email,
        'phone': member.phone,
        'address': member.address,
        'member_code': member.id,
        'bonus_points': member.bonusPoints,
        'last_check_in_day': member.lastCheckInDay,
        'check_in_streak': member.checkInStreak,
      },
      bonusPoints: member.bonusPoints,
    );
    if (synced) await _api.markMemberBootstrap(member.id);
    final latest = await _api.fetchMemberBootstrap();
    if (latest != null) await _auth.applyServerBootstrap(latest);
    final serverReviews = _serverReviewsLoaded ? null : await _api.fetchReviews();
    if (serverReviews != null) {
      _serverReviewsLoaded = true;
      final reviews = serverReviews.map((item) {
        final raw = <String, dynamic>{
          'id': item['id'], 'productId': item['product_id'],
          'memberId': item['member_code'] ?? '', 'author': item['author'],
          'rating': item['rating'], 'text': item['review_text'],
          'at': item['created_at'], 'source': item['source'],
          'is_sample': item['is_sample'],
        };
        return Review.fromJson(raw);
      }).toList();
      _app.replaceServerReviews(reviews);
    }
  }

  Future<void> _syncPublicContent() async {
    final content = await _api.fetchPublicContent();
    if (content == null) return;

    final news = (content['news'] ?? []).map((item) {
      final category = NewsCategory.values.firstWhere(
        (value) => value.name == item['category'],
        orElse: () => NewsCategory.info,
      );
      final action = NewsAction.values.firstWhere(
        (value) => value.name == item['action'],
        orElse: () => NewsAction.none,
      );
      return NewsItem(
        id: (item['id'] ?? '').toString(),
        title: (item['title'] ?? '').toString(),
        summary: (item['summary'] ?? '').toString(),
        content: (item['content'] ?? '').toString(),
        image: (item['image'] ?? '').toString(),
        category: category,
        date: DateTime.tryParse((item['date'] ?? '').toString()) ?? DateTime.now(),
        isPinned: item['is_pinned'] == true || item['is_pinned'] == 1,
        action: action,
        actionLabel: (item['action_label'] ?? '').toString(),
      );
    }).where((item) => item.id.isNotEmpty && item.title.isNotEmpty).toList();

    final vouchers = (content['vouchers'] ?? []).map((item) {
      final type = VoucherType.values.firstWhere(
        (value) => value.name == item['type'],
        orElse: () => VoucherType.fixed,
      );
      final tierName = item['min_tier']?.toString();
      MemberTier? tier;
      for (final candidate in MemberTier.values) {
        if (candidate.name == tierName) tier = candidate;
      }
      return Voucher(
        code: (item['code'] ?? '').toString(),
        title: (item['title'] ?? '').toString(),
        description: (item['description'] ?? '').toString(),
        type: type,
        value: (item['value'] as num?)?.toDouble() ?? 0,
        maxDiscount: (item['max_discount'] as num?)?.toDouble(),
        minSpend: (item['min_spend'] as num?)?.toDouble() ?? 0,
        memberOnly: item['member_only'] == true || item['member_only'] == 1,
        minTier: tier,
        expiresAt: DateTime.tryParse((item['expires_at'] ?? '').toString()) ?? DateTime.now(),
      );
    }).where((item) => item.code.isNotEmpty).toList();

    final stores = (content['stores'] ?? []).map(StoreLocation.fromJson)
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty).toList();

    _app.replaceNews(news);
    kVouchers
      ..clear()
      ..addAll(vouchers);
    kStores
      ..clear()
      ..addAll(stores);
    _api.notifyContentUpdated();
  }

  void _setStudioMember(String? id) {
    _wardrobe.setActiveMember(id);
    _stylist.setActiveMember(id);
    _tracker.setActiveMember(id);
    _fit.setActiveMember(id);
  }

  void _syncMember() {
    final id = _auth.currentMember?.id;
    _app.setActiveMember(id);
    _style.setActiveMember(id);
    _setStudioMember(id);
  }

  @override
  void dispose() {
    _auth.removeListener(_syncMember);
    _auth.onSignedIn = null;
    _auth.remoteLogin = null;
    _auth.remoteRegister = null;
    _auth.onCancelOrder = null;
    _auth.onCheckIn = null;
    _auth.onFetchBootstrap = null;
    _auth.onSignedOut = null;
    _api.onUnauthorized = null;
    _auth.onMemberDataChanged = null;
    _app.onMemberDataChanged = null;
    _app.onProductFeedback = null;
    _auth.dispose();
    _tracker.dispose();
    _wardrobe.dispose();
    _stylist.dispose();
    _fit.dispose();
    _ootd.dispose();
    _style.dispose();
    _api.dispose();
    _app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<AppState>.value(value: _app),
        ChangeNotifierProvider<ApiService>.value(value: _api),
        ChangeNotifierProvider<StyleProvider>.value(value: _style),
        Provider<PhotoStore>.value(value: _photos),
        ChangeNotifierProvider<WardrobeProvider>.value(value: _wardrobe),
        ChangeNotifierProvider<StylistProvider>.value(value: _stylist),
        ChangeNotifierProvider<TrackerProvider>.value(value: _tracker),
        ChangeNotifierProvider<FitProvider>.value(value: _fit),
        ChangeNotifierProvider<OotdProvider>.value(value: _ootd),
      ],
      child: widget.child,
    );
  }
}
