import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../DATA/product_data.dart';
import '../MODELS/activity_model.dart';
import '../MODELS/member_model.dart';
import '../MODELS/order_model.dart';
import '../MODELS/payment_model.dart';
import '../MODELS/point_model.dart';
import '../MODELS/pricing.dart';
import '../MODELS/product_model.dart';
import '../MODELS/stats_model.dart';
import '../MODELS/voucher_model.dart';
import '../UTILS/formatters.dart';
import '../UTILS/key_value_store.dart';

const String _kMembersKey = 'members_v1';
const String _kOrdersKey = 'orders_v1';
const String _kSessionKey = 'session_v1';
const String _kActivitiesKey = 'activities_v1';
const String _kLegacySeededKey = 'seeded_v1';
const String _legacyDemoEmail = 'member@uniqlo.demo';

/// Mengelola akun member, sesi login, poin, level, riwayat pesanan, dan log
/// aktivitas.
///
/// Data lokal menjadi cache agar antarmuka tetap responsif. Akun, pesanan,
/// saldo poin, level, dan status resmi pesanan dipulihkan dari backend saat
/// login. Saat server tersedia, autentikasi dilakukan server-first.
///
/// Password disimpan dengan PBKDF2-SHA256 + salt di backend; cache lokal
/// memakai hash terpisah dan tidak menjadi sumber otoritas akun.
class AuthProvider extends ChangeNotifier {
  AuthProvider({KeyValueStore? store}) : _store = store ?? MemoryStore() {
    _restore();
  }

  final KeyValueStore _store;
  final math.Random _random = math.Random();

  /// Dipanggil setelah masuk/daftar berhasil (password asli masih tersedia
  /// sesaat). Dipakai menyamakan akun lokal dengan akun di server.
  Future<void> Function(Member member, String password)? onSignedIn;

  /// Autentikasi server dilakukan lebih dahulu agar akun yang hanya ada di
  /// database tetap dapat masuk pada perangkat baru.
  Future<Map<String, dynamic>?> Function(String email, String password)? remoteLogin;
  Future<Map<String, dynamic>?> Function(String name, String email, String phone,
      String password, String address, String memberCode, int bonusPoints)? remoteRegister;
  Future<bool> Function(String orderId)? onCancelOrder;
  Future<bool> Function(String orderId, Map<String, dynamic> selection)? onSaveFulfillment;
  Future<bool> Function(String orderId)? onSimulatePayment;
  Future<void> Function()? onOrderCreated;
  Future<int?> Function()? onCheckIn;
  Future<Map<String, dynamic>?> Function()? onFetchBootstrap;

  /// Dipanggil setelah data member/pesanan/aktivitas berubah.
  VoidCallback? onMemberDataChanged;

  void _notifyMemberDataChanged() {
    final callback = onMemberDataChanged;
    if (callback != null) unawaited(Future<void>(() => callback()));
  }

  /// Dipanggil setelah keluar dari akun.
  VoidCallback? onSignedOut;

  Future<void> _notifySignedIn(Member member, String password) async {
    final callback = onSignedIn;
    if (callback == null) return;
    try {
      // Tunggu registrasi/login server dan snapshot awal selesai agar data
      // member langsung tercatat ketika alur daftar/masuk kembali ke UI.
      await callback(member, password);
    } catch (_) {
      // Aplikasi tetap dapat dipakai offline; sinkronisasi dicoba lagi
      // ketika ada perubahan data berikutnya.
    }
  }

  List<Member> _members = [];
  List<Order> _orders = [];
  List<ActivityEvent> _activities = [];
  String? _currentMemberId;
  int? _serverPointsOverride;
  double? _serverSpendOverride;
  double? _serverTransactionSpendOverride;
  double? _serverTransactionSavingsOverride;
  List<PointEntry>? _serverPointHistory;

  /// `false` bila penyimpanan hanya di memori (data hilang saat aplikasi ditutup).
  bool get isPersistent => _store.isPersistent;

  int get registeredMemberCount => _members.length;

  // ---------------------------------------------------------------------------
  // Getter
  // ---------------------------------------------------------------------------

  bool get isLoggedIn => currentMember != null;

  Member? get currentMember {
    final id = _currentMemberId;
    if (id == null) return null;
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  /// Pesanan milik member yang sedang login, terbaru lebih dulu.
  List<Order> get myOrders {
    final id = _currentMemberId;
    if (id == null) return const [];
    final list = _orders.where((o) => o.memberId == id).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Order? orderById(String id) {
    for (final order in myOrders) {
      if (order.id == id) return order;
    }
    return null;
  }

  /// Jumlah pesanan yang masih berjalan (belum selesai/dibatalkan).
  int get activeOrderCount => myOrders.where((o) {
        final status = o.status;
        return status != OrderStatus.selesai &&
            status != OrderStatus.dibatalkan;
      }).length;

  /// Saldo poin = bonus + poin didapat - poin dipakai (pesanan batal diabaikan).
  int get points {
    final member = currentMember;
    if (member == null) return 0;
    if (_serverPointsOverride != null) return _serverPointsOverride!;
    var total = member.bonusPoints;
    for (final order in myOrders) {
      if (order.isCancelled) continue;
      total += order.pointsEarned - order.pointsUsed;
    }
    return math.max(0, total);
  }

  /// Total belanja kumulatif (tanpa ongkir, tanpa pesanan dibatalkan).
  double get totalSpend {
    if (_serverSpendOverride != null) return _serverSpendOverride!;
    var total = 0.0;
    for (final order in myOrders) {
      if (order.isCancelled) continue;
      total += order.merchandisePaid;
    }
    return total;
  }

  /// Total transaksi Paid yang belum dibatalkan/direfund untuk riwayat.
  /// Berbeda dari [totalSpend] yang khusus menentukan level membership.
  double get totalTransactionSpend {
    if (_serverTransactionSpendOverride != null) return _serverTransactionSpendOverride!;
    return myOrders.where((o) => !o.isCancelled && o.isPaid)
        .fold<double>(0, (sum, o) => sum + o.total);
  }

  double get totalTransactionSavings {
    if (_serverTransactionSavingsOverride != null) return _serverTransactionSavingsOverride!;
    return myOrders.where((o) => !o.isCancelled && o.isPaid)
        .fold<double>(0, (sum, o) => sum + o.totalSavings);
  }

  MemberTier get tier =>
      isLoggedIn ? tierForSpend(totalSpend) : MemberTier.regular;

  /// Sisa belanja untuk naik ke level berikutnya (0 jika sudah tertinggi).
  double get amountToNextTier {
    final next = tier.next;
    if (next == null) return 0;
    return math.max(0.0, next.minSpend - totalSpend);
  }

  /// Progres 0..1 menuju level berikutnya.
  double get tierProgress {
    final next = tier.next;
    if (next == null) return 1;
    final range = next.minSpend - tier.minSpend;
    if (range <= 0) return 1;
    return ((totalSpend - tier.minSpend) / range).clamp(0.0, 1.0).toDouble();
  }

  // ---------------------------------------------------------------------------
  // Riwayat pembayaran, poin, statistik, dan aktivitas
  // ---------------------------------------------------------------------------

  /// Riwayat pembayaran member (terbaru dulu).
  List<PaymentRecord> get paymentRecords => buildPaymentRecords(myOrders);

  /// Riwayat poin member (terbaru dulu).
  List<PointEntry> get pointHistory {
    final member = currentMember;
    if (member == null) return const [];
    return _serverPointHistory ?? buildPointHistory(member, myOrders, myActivities);
  }

  SpendingStats get stats => buildSpendingStats(
        myOrders,
        categoryOf: (id) {
          for (final product in kProducts) {
            if (product.id == id) return product.category;
          }
          return 'Lainnya';
        },
      );

  /// Log aktivitas member yang sedang login (terbaru dulu).
  List<ActivityEvent> get myActivities {
    final id = _currentMemberId;
    if (id == null) return const [];
    final list = _activities.where((e) => e.memberId == id).toList();
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  /// Mencatat aktivitas untuk member yang sedang login (mis. ulasan).
  Future<void> logActivity(
    ActivityType type,
    String title, {
    String detail = '',
    int points = 0,
  }) async {
    final id = _currentMemberId;
    if (id == null) return;
    _appendActivity(id, type, title, detail: detail, points: points);
    notifyListeners();
    await _persistActivities();
  }

  void _appendActivity(
    String memberId,
    ActivityType type,
    String title, {
    String detail = '',
    int points = 0,
  }) {
    final now = DateTime.now();
    _activities = [
      ..._activities,
      ActivityEvent(
        id: 'a-${now.microsecondsSinceEpoch}-${_activities.length}',
        memberId: memberId,
        type: type,
        title: title,
        detail: detail,
        at: now,
        points: points,
      ),
    ];
    // Batasi ukuran log agar penyimpanan tidak membengkak.
    if (_activities.length > 400) {
      _activities = _activities.sublist(_activities.length - 400);
    }
  }

  // ---------------------------------------------------------------------------
  // Check-in harian
  // ---------------------------------------------------------------------------

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Poin check-in: 5 poin hari pertama, naik 2 poin per hari beruntun
  /// (maksimal 15 poin).
  static int checkInReward(int streak) =>
      math.min(15, 5 + 2 * math.max(0, streak - 1));

  bool canCheckInToday({DateTime? now}) {
    final member = currentMember;
    if (member == null) return false;
    return member.lastCheckInDay != _dayKey(now ?? DateTime.now());
  }

  /// Hari beruntun saat ini (0 bila rantai sudah putus).
  int currentStreak({DateTime? now}) {
    final member = currentMember;
    if (member == null) return 0;
    final today = now ?? DateTime.now();
    final last = member.lastCheckInDay;
    if (last == null) return 0;
    if (last == _dayKey(today)) return member.checkInStreak;
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (last == _dayKey(yesterday)) return member.checkInStreak;
    return 0;
  }

  /// Check-in hari ini. Mengembalikan poin yang didapat, atau `null` bila
  /// sudah check-in / belum login.
  Future<int?> checkIn({DateTime? now}) async {
    final member = currentMember;
    final today = now ?? DateTime.now();
    if (member == null || !canCheckInToday(now: today)) return null;

    final streak = currentStreak(now: today) + 1;
    final remote = onCheckIn;
    final remoteReward = remote == null ? null : await remote();
    if (remote != null && remoteReward == null) return null;
    final reward = remoteReward ?? checkInReward(streak);
    final effectiveStreak = remoteReward == null
        ? streak : (reward >= 15 ? 6 : ((reward - 5) ~/ 2) + 1);

    _replaceMember(member.copyWith(
      bonusPoints: member.bonusPoints + reward,
      lastCheckInDay: _dayKey(today),
      checkInStreak: effectiveStreak,
    ));
    if (remote == null) {
      _appendActivity(
        member.id,
        ActivityType.checkIn,
        'Check-in harian',
        detail: 'Hari ke-$effectiveStreak berturut-turut',
        points: reward,
      );
    }
    notifyListeners();
    await _persistMembers();
    await _persistActivities();
    return reward;
  }

  // ---------------------------------------------------------------------------
  // Autentikasi
  // ---------------------------------------------------------------------------

  /// Mendaftarkan member baru lalu langsung masuk.
  /// Mengembalikan pesan error, atau `null` jika berhasil.
  Future<String?> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    String address = '',
  }) async {
    final mail = email.trim().toLowerCase();
    if (_members.any((m) => m.email == mail)) {
      return 'Email sudah terdaftar. Silakan masuk.';
    }
    final memberId = _generateMemberId();
    Map<String, dynamic>? serverUser;
    if (remoteRegister != null) {
      try {
        serverUser = await remoteRegister!(name.trim(), mail, phone.trim(),
            password, address.trim(), memberId, PricingRules.welcomeBonusPoints);
      } catch (e) {
        return e.toString().replaceFirst('Exception: ', '');
      }
    }
    final salt = _newSalt();
    final member = Member(
      id: (serverUser?['member_code']?.toString().trim().isNotEmpty ?? false)
          ? serverUser!['member_code'].toString() : memberId,
      name: name.trim(),
      email: mail,
      phone: phone.trim(),
      address: address.trim(),
      passwordHash: _hash(password, salt),
      salt: salt,
      joinedAt: DateTime.now(),
      bonusPoints: PricingRules.welcomeBonusPoints,
    );

    _members = [..._members, member];
    _currentMemberId = member.id;
    _appendActivity(
      member.id,
      ActivityType.register,
      'Mendaftar sebagai member',
      detail: 'Bonus ${PricingRules.welcomeBonusPoints} poin',
      points: PricingRules.welcomeBonusPoints,
    );
    notifyListeners();

    await _persistMembers();
    await _persistActivities();
    await _safeSave(_kSessionKey, member.id);
    await _notifySignedIn(member, password);
    return null;
  }

  /// Masuk sebagai member. Mengembalikan pesan error, atau `null` jika berhasil.
  Future<String?> login(String email, String password) async {
    final mail = email.trim().toLowerCase();
    Map<String, dynamic>? serverUser;
    if (remoteLogin != null) {
      try {
        serverUser = await remoteLogin!(mail, password);
      } catch (e) {
        return e.toString().replaceFirst('Exception: ', '');
      }
    }
    Member? found;
    for (final member in _members) {
      if (member.email == mail) { found = member; break; }
    }
    if (serverUser == null && remoteLogin != null) {
      return 'Akun tidak dapat diverifikasi di server.';
    }
    if (found == null && serverUser != null) {
      final salt = _newSalt();
      final created = serverUser['created_at'];
      final joined = created is num
          ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000)
          : DateTime.now();
      found = Member(
        id: (serverUser['member_code']?.toString().trim().isNotEmpty ?? false)
            ? serverUser['member_code'].toString() : '${serverUser['id']}',
        name: (serverUser['name'] ?? '').toString(),
        email: mail,
        phone: (serverUser['phone'] ?? '').toString(),
        address: (serverUser['address'] ?? '').toString(),
        passwordHash: _hash(password, salt), salt: salt, joinedAt: joined,
        bonusPoints: (serverUser['bonus_points'] as num?)?.toInt() ?? 0,
        lastCheckInDay: serverUser['last_check_in_day']?.toString(),
        checkInStreak: (serverUser['check_in_streak'] as num?)?.toInt() ?? 0,
      );
      _members = [..._members, found];
      await _persistMembers();
    } else if (found != null && serverUser != null) {
      final salt = _newSalt();
      found = found.copyWith(
        name: (serverUser['name'] ?? found.name).toString(),
        email: mail,
        phone: (serverUser['phone'] ?? found.phone).toString(),
        address: (serverUser['address'] ?? found.address).toString(),
        passwordHash: _hash(password, salt), salt: salt,
        bonusPoints: (serverUser['bonus_points'] as num?)?.toInt() ?? found.bonusPoints,
        lastCheckInDay: serverUser['last_check_in_day']?.toString(),
        checkInStreak: (serverUser['check_in_streak'] as num?)?.toInt() ?? found.checkInStreak,
      );
      _replaceMember(found);
      await _persistMembers();
    } else if (found == null) {
      return 'Email belum terdaftar. Silakan daftar terlebih dahulu.';
    } else if (_hash(password, found.salt) != found.passwordHash) {
      return 'Password salah. Coba lagi.';
    }

    _currentMemberId = found.id;
    _appendActivity(found.id, ActivityType.login, 'Masuk ke akun');
    notifyListeners();
    await _persistActivities();
    await _safeSave(_kSessionKey, found.id);
    await _notifySignedIn(found, password);
    return null;
  }

  Future<void> refreshServerData() async {
    final fetch = onFetchBootstrap;
    if (fetch == null || currentMember == null) return;
    final payload = await fetch();
    if (payload != null) await applyServerBootstrap(payload);
  }

  /// Memulihkan transaksi dan ringkasan dari database server setelah login.
  /// Server menjadi sumber kebenaran untuk status pesanan, poin, dan level.
  Future<void> applyServerBootstrap(Map<String, dynamic> payload) async {
    final member = currentMember;
    if (member == null) return;
    final serverMember = payload['member'] ?? payload['user'];
    if (serverMember is Map) {
      final updated = member.copyWith(
        name: (serverMember['name'] ?? member.name).toString(),
        email: (serverMember['email'] ?? member.email).toString(),
        phone: (serverMember['phone'] ?? member.phone).toString(),
        address: (serverMember['address'] ?? member.address).toString(),
        bonusPoints: (serverMember['bonus_points'] as num?)?.toInt() ?? member.bonusPoints,
        lastCheckInDay: serverMember['last_check_in_day']?.toString(),
        checkInStreak: (serverMember['check_in_streak'] as num?)?.toInt() ?? member.checkInStreak,
      );
      _replaceMember(updated);
      await _safeSave(_kMembersKey, jsonEncode(_members.map((m) => m.toJson()).toList()));
    }
    final summary = payload['summary'];
    if (summary is Map) {
      _serverPointsOverride = (summary['points'] as num?)?.toInt() ?? 0;
      _serverSpendOverride = (summary['total_spend'] as num?)?.toDouble() ?? 0;
      _serverTransactionSpendOverride = (summary['transaction_spend'] as num?)?.toDouble() ?? 0;
      _serverTransactionSavingsOverride = (summary['transaction_savings'] as num?)?.toDouble() ?? 0;
    }
    final ledger = payload['points_ledger'];
    if (ledger is List) {
      _serverPointHistory = [for (final raw in ledger) if (raw is Map)
        PointEntry(
          title: (raw['reason'] ?? 'Transaksi poin').toString(),
          detail: (raw['order_id'] ?? raw['source'] ?? '').toString(),
          points: (raw['points_delta'] as num?)?.toInt() ?? 0,
          at: raw['created_at'] is num
              ? DateTime.fromMillisecondsSinceEpoch((raw['created_at'] as num).toInt() * 1000)
              : DateTime.tryParse((raw['created_at'] ?? '').toString()) ?? DateTime.now(),
        )];
    }
    final earnedByOrder = <String, int>{};
    if (ledger is List) {
      for (final raw in ledger) {
        if (raw is! Map) continue;
        final reason = (raw['reason'] ?? '').toString();
        if (reason != 'Poin pesanan selesai' && reason != 'Koreksi poin karena pembatalan/refund') continue;
        final orderId = raw['order_id']?.toString();
        if (orderId == null) continue;
        earnedByOrder[orderId] = (earnedByOrder[orderId] ?? 0) + ((raw['points_delta'] as num?)?.toInt() ?? 0);
      }
    }
    final rawOrders = payload['orders'];
    if (rawOrders is List && rawOrders.isNotEmpty) {
      final restored = <Order>[];
      for (final raw in rawOrders) {
        if (raw is! Map) continue;
        final snapshot = raw['snapshot'];
        if (snapshot is! Map) continue;
        final data = Map<String, dynamic>.from(snapshot);
        final status = (raw['order_status'] ?? data['status'] ?? 'diproses').toString().toLowerCase();
        data['serverStatus'] = OrderStatus.values.any((x) => x.name == status) ? status : 'diproses';
        data['paymentStatus'] = (raw['payment_status'] ?? data['paymentStatus'] ?? 'Pending').toString();
        data['memberId'] = member.id;
        data['pointsEarned'] = math.max(0, earnedByOrder[raw['id']?.toString()] ?? 0);
        if (status == 'dibatalkan' && data['cancelledAt'] == null) {
          data['cancelledAt'] = DateTime.now().toIso8601String();
        }
        try { restored.add(Order.fromJson(data)); } catch (_) {}
      }
      final merged = <String, Order>{
        for (final o in _orders.where((o) => o.memberId == member.id)) o.id: o,
        for (final o in restored) o.id: o,
      };
      _orders = [..._orders.where((o) => o.memberId != member.id), ...merged.values];
      await _safeSave(_kOrdersKey, jsonEncode(_orders.map((o) => o.toJson()).toList()));
    }
    final rawActivities = payload['activities'];
    if (rawActivities is List && rawActivities.isNotEmpty) {
      final restored = <ActivityEvent>[];
      for (final raw in rawActivities) {
        if (raw is! Map) continue;
        final typeName = (raw['activity_type'] ?? 'profile').toString();
        restored.add(ActivityEvent(
          id: (raw['id'] ?? '').toString(), memberId: member.id,
          type: ActivityType.values.firstWhere((x) => x.name == typeName, orElse: () => ActivityType.profile),
          title: (raw['title'] ?? 'Aktivitas').toString(), detail: (raw['detail'] ?? '').toString(),
          at: DateTime.tryParse((raw['created_at'] ?? '').toString()) ?? DateTime.now(),
          points: (raw['points'] as num?)?.toInt() ?? 0,
        ));
      }
      final merged = <String, ActivityEvent>{
        for (final a in _activities.where((a) => a.memberId == member.id)) a.id: a,
        for (final a in restored) a.id: a,
      };
      _activities = [..._activities.where((a) => a.memberId != member.id), ...merged.values];
      await _safeSave(_kActivitiesKey, jsonEncode(_activities.map((a) => a.toJson()).toList()));
    }
    notifyListeners();
  }

  /// Keluar dari akun. Data member (pesanan, poin, level) tetap tersimpan.
  Future<void> logout() async {
    final id = _currentMemberId;
    if (id != null) {
      _appendActivity(id, ActivityType.logout, 'Keluar dari akun');
    }
    _currentMemberId = null;
    _serverPointsOverride = null;
    _serverSpendOverride = null;
    _serverTransactionSpendOverride = null;
    _serverTransactionSavingsOverride = null;
    _serverPointHistory = null;
    notifyListeners();
    await _persistActivities();
    try {
      await _store.remove(_kSessionKey);
    } catch (_) {}
    onSignedOut?.call();
  }

  Future<void> updateProfile({
    required String name,
    required String phone,
    required String address,
  }) async {
    final member = currentMember;
    if (member == null) return;
    _replaceMember(member.copyWith(
      name: name.trim(),
      phone: phone.trim(),
      address: address.trim(),
    ));
    _appendActivity(member.id, ActivityType.profile, 'Profil diperbarui');
    notifyListeners();
    await _persistMembers();
    await _persistActivities();
  }

  /// Mengubah password. Mengembalikan pesan error, atau `null` jika berhasil.
  Future<String?> changePassword(String oldPassword, String newPassword) async {
    final member = currentMember;
    if (member == null) return 'Anda belum masuk.';
    if (_hash(oldPassword, member.salt) != member.passwordHash) {
      return 'Password lama salah.';
    }
    final salt = _newSalt();
    _replaceMember(member.copyWith(
      salt: salt,
      passwordHash: _hash(newPassword, salt),
    ));
    _appendActivity(member.id, ActivityType.password, 'Password diganti');
    notifyListeners();
    await _persistMembers();
    await _persistActivities();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Pesanan
  // ---------------------------------------------------------------------------

  /// Membuat nomor pesanan unik, contoh: UNQ-20261015-4821.
  String newOrderId({DateTime? now}) {
    final date = now ?? DateTime.now();
    final day = '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    String id;
    do {
      id = 'UNQ-$day-${1000 + _random.nextInt(9000)}';
    } while (_orders.any((o) => o.id == id));
    return id;
  }

  /// Menyimpan pesanan baru untuk member yang sedang login.
  /// Mengembalikan `null` jika belum login (pembelian tamu tidak disimpan).
  Future<Order?> placeOrder({
    required List<CartItem> items,
    required PriceBreakdown pricing,
    required String paymentMethod,
    required String recipient,
    required String phone,
    required String address,
    int? addressId,
    Voucher? voucher,
    String? gatewayRef,
    String? paymentInfo,
  }) async {
    final member = currentMember;
    if (member == null || items.isEmpty) return null;

    final order = Order(
      id: newOrderId(),
      memberId: member.id,
      createdAt: DateTime.now(),
      items: items.map(OrderItem.fromCartItem).toList(),
      paymentMethod: paymentMethod,
      paymentStatus: paymentMethod.toUpperCase().startsWith('COD') ||
              paymentMethod.toLowerCase().contains('bayar di tempat')
          ? 'Unpaid'
          : 'Paid',
      recipient: recipient.trim(),
      phone: phone.trim(),
      address: address.trim(),
      addressId: addressId,
      subtotal: pricing.subtotal,
      memberDiscount: pricing.memberDiscount,
      voucherCode: pricing.voucherDiscount > 0 ||
              voucher?.type == VoucherType.freeShipping
          ? voucher?.code
          : null,
      voucherDiscount: pricing.voucherDiscount,
      pointsUsed: pricing.pointsUsed,
      pointsDiscount: pricing.pointsDiscount,
      shippingFee: pricing.shippingFee,
      shippingDiscount: pricing.shippingDiscount,
      pointsEarned: pricing.pointsEarned,
      gatewayRef: gatewayRef,
      paymentInfo: paymentInfo,
    );

    _orders = [..._orders, order];
    _appendActivity(
      member.id,
      ActivityType.order,
      'Pesanan ${order.id} dibuat',
      detail:
          '${order.itemCount} item, dibayar ${formatRupiah(order.total)} via ${order.paymentMethod}',
    );
    notifyListeners();
    await _persistOrders();
    await _persistActivities();
    // Pastikan record order sudah dibuat di server sebelum halaman fulfillment
    // mengirim perubahan penerimaan. Ini mencegah race 404 saat checkout.
    final syncCreatedOrder = onOrderCreated;
    if (syncCreatedOrder != null) await syncCreatedOrder();
    return orderById(order.id) ?? order;
  }

  /// Menyimpan pilihan penerimaan setelah pembayaran.
  ///
  /// Ambil di toko: ongkir yang sudah dibayar dikembalikan (dicatat di
  /// `shippingRefund`) dan dibuat kode ambil. Diantar: alamat boleh diubah.
  Future<Order?> setFulfillment(
    String orderId, {
    required String type,
    String? storeId,
    String? storeName,
    String? storeAddress,
    String? deliveryService,
    int? addressId,
    String? recipient,
    String? phone,
    String? address,
  }) async {
    final index = _orders.indexWhere(
      (o) => o.id == orderId && o.memberId == _currentMemberId,
    );
    if (index < 0) return null;
    final old = _orders[index];
    if (old.isCancelled || old.fulfillmentType != null) return null;
    final saveRemote = onSaveFulfillment;
    if (saveRemote != null) {
      final saved = await saveRemote(orderId, {
        'type': type,
        if (storeId != null) 'store_id': storeId,
        if (storeName != null) 'store_name': storeName,
        if (storeAddress != null) 'store_address': storeAddress,
        if (addressId != null) 'address_id': addressId,
        if (deliveryService != null) 'delivery_service': deliveryService,
      });
      if (!saved) return null;
    }
    final paidShipping =
        math.max(0.0, old.shippingFee - old.shippingDiscount);
    final pickup = type == kFulfillPickup;
    final updated = old.copyWith(
      fulfillmentType: type,
      fulfillmentAt: DateTime.now(),
      storeId: pickup ? storeId : null,
      storeName: pickup ? storeName : null,
      storeAddress: pickup ? storeAddress : null,
      pickupCode: pickup ? (old.pickupCode ?? _pickupCode(old.id)) : null,
      deliveryService: pickup ? null : deliveryService,
      recipient: recipient,
      phone: phone,
      address: pickup ? null : address,
      addressId: addressId,
      clearAddressId: pickup,
      shippingFee: pickup ? 0.0 : null,
      shippingDiscount: pickup ? 0.0 : null,
      shippingRefund: pickup ? paidShipping : null,
    );
    _orders = [
      for (var i = 0; i < _orders.length; i++) i == index ? updated : _orders[i],
    ];
    _appendActivity(
      old.memberId,
      ActivityType.order,
      pickup
          ? 'Pesanan ${old.id} diambil di ${updated.storeName}'
          : 'Pesanan ${old.id} diantar ke alamat',
    );
    notifyListeners();
    await _persistOrders();
    await _persistActivities();
    return updated;
  }

  Future<bool> simulatePayment(String orderId) async {
    final callback = onSimulatePayment;
    if (callback == null) return false;
    final ok = await callback(orderId);
    if (ok) await refreshServerData();
    return ok;
  }

  String _pickupCode(String orderId) {
    final digits = orderId.replaceAll(RegExp(r'[^0-9]'), '');
    final tail = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    return 'PU-$tail-${letters[_random.nextInt(letters.length)]}'
        '${letters[_random.nextInt(letters.length)]}';
  }

  /// Membatalkan pesanan selama statusnya belum Selesai atau Dibatalkan.
  Future<bool> cancelOrder(String orderId) async {
    final index = _orders.indexWhere(
      (o) => o.id == orderId && o.memberId == _currentMemberId,
    );
    if (index < 0) return false;
    if (!_orders[index].canCancel) return false;

    final cancelledId = _orders[index].id;
    final remoteCancel = onCancelOrder;
    if (remoteCancel != null) {
      final ok = await remoteCancel(cancelledId);
      if (!ok) return false;
    }
    _orders = [..._orders];
    _orders[index] = _orders[index].copyWith(
      cancelledAt: DateTime.now(), serverStatus: OrderStatus.dibatalkan, paymentStatus: _orders[index].paymentStatus.toLowerCase() == 'paid' ? 'Refunded' : _orders[index].paymentStatus);
    final memberId = _currentMemberId;
    if (memberId != null) {
      _appendActivity(
        memberId,
        ActivityType.cancel,
        'Pesanan $cancelledId dibatalkan',
        detail: 'Dana dan poin dikembalikan',
      );
    }
    notifyListeners();
    await _persistOrders();
    await _persistActivities();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Hash & ID
  // ---------------------------------------------------------------------------

  String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }

  String _newSalt() {
    final secure = math.Random.secure();
    return List<String>.generate(
      16,
      (_) => secure.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String _generateMemberId() {
    String id;
    do {
      id = 'UNQ${10000000 + _random.nextInt(90000000)}';
    } while (_members.any((m) => m.id == id));
    return id;
  }

  void _replaceMember(Member updated) {
    _members = [
      for (final m in _members)
        if (m.id == updated.id) updated else m,
    ];
  }

  // ---------------------------------------------------------------------------
  // Penyimpanan lokal
  // ---------------------------------------------------------------------------

  Future<void> _safeSave(String key, String value) async {
    try {
      await _store.setString(key, value);
    } catch (_) {
      // Penyimpanan gagal: aplikasi tetap berjalan dengan data di memori.
    }
  }

  Future<void> _persistMembers() async {
    await _safeSave(_kMembersKey, jsonEncode(_members.map((m) => m.toJson()).toList()));
    _notifyMemberDataChanged();
  }

  Future<void> _persistOrders() async {
    await _safeSave(_kOrdersKey, jsonEncode(_orders.map((o) => o.toJson()).toList()));
    _notifyMemberDataChanged();
  }

  Future<void> _persistActivities() async {
    await _safeSave(_kActivitiesKey, jsonEncode(_activities.map((e) => e.toJson()).toList()));
    _notifyMemberDataChanged();
  }

  void _restore() {
    try {
      final rawMembers = _store.getString(_kMembersKey);
      if (rawMembers != null) {
        _members = (jsonDecode(rawMembers) as List)
            .map((e) => Member.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final rawOrders = _store.getString(_kOrdersKey);
      if (rawOrders != null) {
        _orders = (jsonDecode(rawOrders) as List)
            .map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      final rawActivities = _store.getString(_kActivitiesKey);
      if (rawActivities != null) {
        _activities = (jsonDecode(rawActivities) as List)
            .map((e) =>
                ActivityEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      _currentMemberId = _store.getString(_kSessionKey);
    } catch (_) {
      _members = [];
      _orders = [];
      _activities = [];
      _currentMemberId = null;
    }

    _purgeLegacyDemo();

    // Sesi yang menunjuk member yang sudah tidak ada dianggap tidak valid.
    if (_currentMemberId != null && currentMember == null) {
      _currentMemberId = null;
    }
  }

  /// Versi aplikasi sebelumnya membuat akun demo otomatis. Akun itu (beserta
  /// pesanan dan aktivitasnya) dihapus agar hanya akun yang didaftarkan
  /// pengguna yang ada.
  void _purgeLegacyDemo() {
    final demoIds = _members
        .where((m) => m.email == _legacyDemoEmail)
        .map((m) => m.id)
        .toSet();

    if (demoIds.isNotEmpty) {
      _members = _members.where((m) => !demoIds.contains(m.id)).toList();
      _orders = _orders.where((o) => !demoIds.contains(o.memberId)).toList();
      _activities =
          _activities.where((e) => !demoIds.contains(e.memberId)).toList();
      if (_currentMemberId != null && demoIds.contains(_currentMemberId)) {
        _currentMemberId = null;
        _store.remove(_kSessionKey).catchError((Object _) {});
      }
      _persistMembers();
      _persistOrders();
      _persistActivities();
    }

    if (_store.getString(_kLegacySeededKey) != null) {
      _store.remove(_kLegacySeededKey).catchError((Object _) {});
    }
  }
}
