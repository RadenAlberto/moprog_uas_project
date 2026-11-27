import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../UTILS/formatters.dart';
import '../UTILS/key_value_store.dart';
import 'app_state.dart';

const String _kTrackerKey = 'tracker_v1_';
const int _kMaxAlerts = 60;
const int _kMaxHistory = 30;

/// Jenis simulasi untuk mode demo.
enum TrackerSimulation { priceDrop, soldOut, restock }

/// Price Tracker & Restock Alert.
///
/// Membandingkan harga dan ketersediaan ukuran produk yang dilacak setiap kali
/// katalog diperbarui (saat aplikasi dibuka, saat pembaruan berkala, dan saat
/// pengguna menekan "Cek sekarang"). Perubahan menghasilkan notifikasi di
/// dalam aplikasi (banner di atas layar + daftar notifikasi + lencana).
class TrackerProvider extends ChangeNotifier {
  TrackerProvider({required KeyValueStore store, required AppState app})
      : _store = store,
        _app = app {
    _lastCatalog = _app.allProducts;
    _app.addListener(_onAppChanged);
  }

  final KeyValueStore _store;
  final AppState _app;

  final StreamController<TrackerAlert> _alertController =
      StreamController<TrackerAlert>.broadcast();

  /// Dipanggil untuk mengambil katalog terbaru dari server (opsional).
  Future<void> Function()? refresher;

  List<TrackedItem> _items = [];
  List<TrackerAlert> _alerts = [];
  List<Product> _lastCatalog = const [];
  Timer? _timer;
  String? _owner;
  bool _ready = false;
  bool _checking = false;
  DateTime? _lastChecked;

  List<TrackedItem> get items => List.unmodifiable(_items);
  List<TrackerAlert> get alerts => List.unmodifiable(_alerts);
  Stream<TrackerAlert> get alertStream => _alertController.stream;
  bool get checking => _checking;
  DateTime? get lastChecked => _lastChecked;

  int get unreadCount => _alerts.where((a) => !a.read).length;

  String get _key => '$_kTrackerKey${_owner ?? 'guest'}';

  void setActiveMember(String? memberId) {
    if (_ready && _owner == memberId) return;
    _owner = memberId;
    _ready = true;
    _items = [];
    _alerts = [];
    final raw = _store.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map) {
          final rawItems = json['items'];
          if (rawItems is List) {
            for (final e in rawItems) {
              final item = TrackedItem.fromJson(e);
              if (item != null) _items.add(item);
            }
          }
          final rawAlerts = json['alerts'];
          if (rawAlerts is List) {
            for (final e in rawAlerts) {
              final alert = TrackerAlert.fromJson(e);
              if (alert != null) _alerts.add(alert);
            }
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  void _persist() {
    unawaited(
      _store.setString(
        _key,
        jsonEncode({
          'items': [for (final i in _items) i.toJson()],
          'alerts': [for (final a in _alerts) a.toJson()],
        }),
      ),
    );
  }

  // --- Pelacakan -------------------------------------------------------------

  bool isTracked(String productId, String size) =>
      _items.any((i) => i.productId == productId && i.size == size);

  TrackedItem? find(String productId, String size) {
    for (final i in _items) {
      if (i.productId == productId && i.size == size) return i;
    }
    return null;
  }

  /// Mulai melacak [product] ukuran [size]. [targetPrice] `null` = beri tahu
  /// setiap kali harga turun.
  void track(
    Product product,
    String size, {
    Color? color,
    double? targetPrice,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = TrackedItem(
      productId: product.id,
      size: size,
      colorArgb: color?.toARGB32(),
      startPrice: product.price,
      lastPrice: product.price,
      sizeAvailable: product.availableSizes.contains(size),
      createdAt: now,
      targetPrice: targetPrice,
      history: [PricePoint(now, product.price)],
    );
    _items = [
      item,
      for (final i in _items)
        if (i.key != item.key) i,
    ];
    _persist();
    notifyListeners();
  }

  void untrack(String productId, String size) {
    _items = _items
        .where((i) => !(i.productId == productId && i.size == size))
        .toList();
    _persist();
    notifyListeners();
  }

  void setTarget(String productId, String size, double? target) {
    _items = [
      for (final i in _items)
        if (i.productId == productId && i.size == size)
          i.copyWith(
            targetPrice: target,
            clearTarget: target == null,
            targetNotified: false,
          )
        else
          i,
    ];
    _persist();
    notifyListeners();
  }

  // --- Pengecekan ------------------------------------------------------------

  void _onAppChanged() {
    if (identical(_app.allProducts, _lastCatalog)) return;
    _lastCatalog = _app.allProducts;
    checkNow();
  }

  /// Memulai pengecekan berkala (hanya saat aplikasi terbuka).
  void startAutoCheck({Duration interval = const Duration(minutes: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => unawaited(refreshAndCheck()));
  }

  /// Mengambil katalog terbaru (bila ada server) lalu membandingkan.
  Future<void> refreshAndCheck() async {
    if (_checking) return;
    _checking = true;
    notifyListeners();
    try {
      await refresher?.call();
    } catch (_) {}
    _checking = false;
    checkNow();
  }

  /// Membandingkan katalog sekarang dengan catatan terakhir.
  void checkNow() {
    _lastChecked = DateTime.now();
    final next = <TrackedItem>[];
    final fresh = <TrackerAlert>[];
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final t in _items) {
      final p = _app.productById(t.productId);
      if (p == null) {
        next.add(t);
        continue;
      }
      var item = t;
      final price = p.price;
      final available = p.availableSizes.contains(t.size);

      if ((price - t.lastPrice).abs() >= 1) {
        final history = [...t.history, PricePoint(now, price)];
        if (history.length > _kMaxHistory) {
          history.removeRange(0, history.length - _kMaxHistory);
        }
        item = item.copyWith(lastPrice: price, history: history);

        if (price < t.lastPrice) {
          final percent = ((1 - price / t.lastPrice) * 100).round();
          final target = t.targetPrice;
          if (target == null) {
            fresh.add(_alert(
              AlertKind.priceDrop,
              p,
              'Harga turun $percent%',
              '${p.name} (${t.size}): ${formatRupiah(t.lastPrice)} '
                  '→ ${formatRupiah(price)}',
              now,
            ));
          } else if (price <= target && !t.targetNotified) {
            fresh.add(_alert(
              AlertKind.targetReached,
              p,
              'Harga target tercapai',
              '${p.name} (${t.size}) kini ${formatRupiah(price)}, '
                  'target kamu ${formatRupiah(target)}.',
              now,
            ));
            item = item.copyWith(targetNotified: true);
          }
        } else if (t.targetPrice != null && price > t.targetPrice!) {
          item = item.copyWith(targetNotified: false);
        }
      }

      if (t.sizeAvailable && !available) {
        fresh.add(_alert(
          AlertKind.soldOut,
          p,
          'Ukuran ${t.size} habis',
          '${p.name} ukuran ${t.size} sedang tidak tersedia. '
              'Kami kabari saat stok kembali.',
          now,
        ));
      } else if (!t.sizeAvailable && available) {
        fresh.add(_alert(
          AlertKind.restock,
          p,
          'Stok kembali!',
          '${p.name} ukuran ${t.size} tersedia lagi.',
          now,
        ));
      }
      item = item.copyWith(sizeAvailable: available);
      next.add(item);
    }

    _items = next;
    if (fresh.isNotEmpty) {
      _alerts = [...fresh.reversed, ..._alerts];
      if (_alerts.length > _kMaxAlerts) {
        _alerts = _alerts.sublist(0, _kMaxAlerts);
      }
    }
    _persist();
    notifyListeners();
    for (final a in fresh) {
      if (!_alertController.isClosed) _alertController.add(a);
    }
  }

  int _alertCounter = 0;

  TrackerAlert _alert(
    AlertKind kind,
    Product p,
    String title,
    String body,
    int now,
  ) {
    return TrackerAlert(
      id: 'a${now}_${_alertCounter++}',
      kind: kind,
      productId: p.id,
      title: title,
      body: body,
      at: now,
    );
  }

  // --- Notifikasi ------------------------------------------------------------

  void markAllRead() {
    if (unreadCount == 0) return;
    _alerts = [for (final a in _alerts) a.markRead()];
    _persist();
    notifyListeners();
  }

  void markRead(String id) {
    _alerts = [for (final a in _alerts) a.id == id ? a.markRead() : a];
    _persist();
    notifyListeners();
  }

  void clearAlerts() {
    _alerts = [];
    _persist();
    notifyListeners();
  }

  // --- Mode demo -------------------------------------------------------------

  /// Mengubah katalog di dalam aplikasi (diskon/stok) agar alur notifikasi
  /// bisa didemokan tanpa menunggu perubahan di server.
  void simulate(TrackedItem item, TrackerSimulation kind) {
    final p = _app.productById(item.productId);
    if (p == null) return;

    final Product changed;
    switch (kind) {
      case TrackerSimulation.priceDrop:
        final dropped = ((p.price * 0.8) / 1000).round() * 1000.0;
        changed = p.withOverrides(
          price: dropped < p.price ? dropped : p.price - 1000,
          originalPrice: p.isOnSale ? p.originalPrice : p.price,
        );
        break;
      case TrackerSimulation.soldOut:
        changed = p.withOverrides(
          availableSizes: [
            for (final s in p.availableSizes)
              if (s != item.size) s,
          ],
        );
        break;
      case TrackerSimulation.restock:
        changed = p.availableSizes.contains(item.size)
            ? p
            : p.withOverrides(availableSizes: [...p.availableSizes, item.size]);
        break;
    }

    _app.replaceCatalog([
      for (final q in _app.allProducts) q.id == p.id ? changed : q,
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _app.removeListener(_onAppChanged);
    _alertController.close();
    super.dispose();
  }
}
