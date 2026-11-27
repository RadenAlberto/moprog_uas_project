import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../DATA/news_data.dart';
import '../DATA/product_data.dart';
import '../DATA/review_data.dart';
import '../MODELS/news_model.dart';
import '../MODELS/order_model.dart';
import '../MODELS/product_model.dart';
import '../MODELS/review_model.dart';
import '../UTILS/key_value_store.dart';
import '../UTILS/toast.dart';

const String _kCartKey = 'cart_v1_';
const String _kWishlistKey = 'wishlist_v1_';
const String _kNewsReadKey = 'news_read_v1';
const String _kRecentSearchKey = 'recent_search_v1';
const String _kReviewsKey = 'reviews_v1';

const int _kMaxRecentSearches = 8;
const int _kMaxQuantity = 99;

/// Kata kunci bahasa Indonesia -> istilah pada data produk (bahasa Inggris).
const Map<String, List<String>> _synonyms = {
  'jaket': ['outerwear', 'parka', 'jacket'],
  'kaos': ['t-shirts', 'tshirt', 't-shirt'],
  'kemeja': ['shirts', 'shirt'],
  'celana': ['pants', 'jeans', 'shorts'],
  'rok': ['skirts'],
  'gaun': ['dresses'],
  'hoodie': ['sweatshirts', 'sweat'],
  'pria': ['men'],
  'wanita': ['women'],
  'anak': ['kids'],
  'bayi': ['baby'],
  'tas': ['bag'],
};

/// State belanja: katalog, pencarian, wishlist, keranjang, berita, dan ulasan.
///
/// Keranjang dan wishlist disimpan per akun (atau "tamu") di [KeyValueStore].
/// Saat tamu login, isi keranjang/wishlist tamu digabung ke akun tersebut.
/// Autentikasi, pesanan, dan poin ada di `AuthProvider`.
class AppState extends ChangeNotifier {
  /// Dipanggil setelah keranjang/wishlist lokal berubah untuk sinkronisasi server.
  VoidCallback? onMemberDataChanged;

  /// Mengirim peristiwa produk (like/dislike/cart/view) ke server.
  void Function(String productId, String action)? onProductFeedback;

  AppState({KeyValueStore? store}) : _store = store ?? MemoryStore() {
    _restoreShared();
  }

  final KeyValueStore _store;

  // ---------------------------------------------------------------------------
  // Katalog & pencarian
  // ---------------------------------------------------------------------------

  /// Katalog aktif: data bawaan aplikasi, lalu diganti data dari server
  /// (database produk) saat internet tersedia.
  List<Product> _products = kProducts;

  late Map<String, Product> _productIndex = _indexOf(_products);

  late List<Product> _saleProducts =
      _products.where((p) => p.isOnSale).toList(growable: false);

  late List<Product> _newProducts =
      _products.where((p) => p.isNew).toList(growable: false);

  static Map<String, Product> _indexOf(List<Product> products) => {
        for (final product in products) product.id: product,
      };

  List<Product> get allProducts => _products;

  /// `true` bila katalog berasal dari server.
  bool get isRemoteCatalog => !identical(_products, kProducts);

  /// Mengganti katalog dengan data dari server. Daftar kosong diabaikan.
  void replaceCatalog(List<Product> products) {
    if (products.isEmpty) return;
    _products = List<Product>.unmodifiable(products);
    _productIndex = _indexOf(_products);
    _saleProducts = _products.where((p) => p.isOnSale).toList(growable: false);
    _newProducts = _products.where((p) => p.isNew).toList(growable: false);
    // Wishlist menunjuk ke objek produk baru agar data (harga, foto) terbaru.
    _wishlist = [for (final p in _wishlist) _productIndex[p.id] ?? p];
    notifyListeners();
  }

  /// Produk yang sedang diskon (untuk Flash Sale).
  List<Product> get saleProducts => _saleProducts;

  /// Produk baru.
  List<Product> get newArrivals => _newProducts;

  Product? productById(String id) => _productIndex[id];

  /// Produk dengan rating tertinggi (untuk "Terlaris").
  List<Product> topRated({int limit = 8}) {
    final list = _products.toList();
    list.sort((a, b) {
      final ra = ratingOf(a);
      final rb = ratingOf(b);
      final byAverage = rb.average.compareTo(ra.average);
      if (byAverage != 0) return byAverage;
      return rb.count.compareTo(ra.count);
    });
    return list.take(limit).toList();
  }

  /// Mencari produk. Semua kata harus cocok dengan awal kata pada nama,
  /// kategori, target pengguna, label teknologi, atau deskripsi.
  List<Product> searchProducts(String query) {
    final tokens = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return _products;

    final patterns = <List<RegExp>>[
      for (final token in tokens)
        [
          for (final term in [token, ...?_synonyms[token]])
            RegExp('(^|[^a-z0-9])${RegExp.escape(term)}'),
        ],
    ];

    return _products.where((product) {
      final haystack = [
        product.name,
        product.category,
        product.audience,
        product.features.join(' '),
        product.description,
      ].join(' ').toLowerCase();
      return patterns.every(
        (alternatives) => alternatives.any((re) => re.hasMatch(haystack)),
      );
    }).toList();
  }

  /// Produk untuk halaman Katalog berdasarkan filter [category]: `Semua`,
  /// target pengguna (Men, Women, ...), kategori (Pants, ...), atau label
  /// teknologi (AIRism, HEATTECH).
  List<Product> catalogProducts(String category) {
    if (category == 'Semua') return _products;
    final key = category.toLowerCase();
    return _products.where((p) {
      return p.audience.toLowerCase() == key ||
          p.category.toLowerCase() == key ||
          p.features.any((f) => f.toLowerCase() == key);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Tab navigasi & filter katalog
  // ---------------------------------------------------------------------------

  int _currentTab = 0;
  String _catalogCategory = 'Semua';

  int get currentTab => _currentTab;

  String get catalogCategory => _catalogCategory;

  void setTab(int index) {
    if (_currentTab == index) return;
    _currentTab = index;
    notifyListeners();
  }

  /// Mengubah filter katalog tanpa pindah tab.
  void setCatalogCategory(String category) {
    if (_catalogCategory == category) return;
    _catalogCategory = category;
    notifyListeners();
  }

  /// Membuka tab Katalog dengan filter [category].
  void showCategory(String category) {
    _catalogCategory = category;
    _currentTab = 1;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Pemilik data (tamu / member)
  // ---------------------------------------------------------------------------

  String? _activeMemberId;
  bool _ownerReady = false;

  String _ownerKey(String? memberId) => memberId ?? 'guest';

  /// Memuat keranjang & wishlist milik [memberId] (`null` = tamu).
  ///
  /// Bila tamu baru saja login, isi keranjang dan wishlist tamu digabung ke
  /// akun, jadi tidak ada yang hilang.
  void setActiveMember(String? memberId) {
    if (_ownerReady && _activeMemberId == memberId) return;

    final firstLoad = !_ownerReady;
    final previous = _activeMemberId;
    _ownerReady = true;

    final carryCart = <CartItem>[];
    final carryWishlist = <Product>[];
    if (!firstLoad && previous == null && memberId != null) {
      carryCart.addAll(_cart);
      carryWishlist.addAll(_wishlist);
    }

    _activeMemberId = memberId;
    _cart = _decodeCart(_store.getString('$_kCartKey${_ownerKey(memberId)}'));
    _wishlist = _decodeWishlist(
      _store.getString('$_kWishlistKey${_ownerKey(memberId)}'),
    );

    if (carryCart.isNotEmpty || carryWishlist.isNotEmpty) {
      for (final line in carryCart) {
        _mergeLine(line);
      }
      for (final product in carryWishlist) {
        if (!isWishlisted(product)) _wishlist.add(product);
      }
      _remove('$_kCartKey${_ownerKey(null)}');
      _remove('$_kWishlistKey${_ownerKey(null)}');
      _persistCart();
      _persistWishlist();
    }

    notifyListeners();
  }

  /// Mengganti cache keranjang dan wishlist dari snapshot server saat login.
  /// Baris produk yang tidak lagi ada di katalog dilewati dengan aman.
  void applyServerCartWishlist({required List<dynamic> cart, required List<dynamic> wishlist, bool replaceCart = true, bool replaceWishlist = true}) {
    final restoredCart = <CartItem>[];
    for (final raw in cart) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final product = _productIndex[item['product_id']?.toString()];
      if (product == null) continue;
      final colorRaw = item['color_code']?.toString() ?? '';
      final colorValue = int.tryParse(colorRaw) ?? (product.availableColors.isNotEmpty ? product.availableColors.first.toARGB32() : 0xFF000000);
      restoredCart.add(CartItem(product: product,
        selectedSize: (item['size'] ?? '').toString(),
        selectedColor: Color(colorValue),
        quantity: ((item['quantity'] as num?)?.toInt() ?? 1).clamp(1, _kMaxQuantity).toInt(),
        isChecked: item['is_selected'] == true || item['is_selected'] == 1));
    }
    final restoredWishlist = <Product>[];
    for (final raw in wishlist) {
      final product = _productIndex[raw.toString()];
      if (product != null && !restoredWishlist.any((p) => p.id == product.id)) restoredWishlist.add(product);
    }
    if (replaceCart) _cart = restoredCart;
    if (replaceWishlist) _wishlist = restoredWishlist;
    if (replaceCart) _persistCart();
    if (replaceWishlist) _persistWishlist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Wishlist
  // ---------------------------------------------------------------------------

  List<Product> _wishlist = [];

  List<Product> get wishlist => List.unmodifiable(_wishlist);

  bool isWishlisted(Product product) {
    return _wishlist.any((p) => p.id == product.id);
  }

  void toggleWishlist(Product product, BuildContext context) {
    if (isWishlisted(product)) {
      _wishlist.removeWhere((p) => p.id == product.id);
      onProductFeedback?.call(product.id, 'dislike');
      showAppToast(
        context,
        '${product.name} dihapus dari wishlist',
        color: Colors.grey.shade900,
        icon: Icons.favorite_border,
      );
    } else {
      _wishlist.add(product);
      onProductFeedback?.call(product.id, 'like');
      showAppToast(
        context,
        'Item ditambahkan ke wishlist',
        icon: Icons.favorite,
      );
    }
    _persistWishlist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Keranjang
  // ---------------------------------------------------------------------------

  List<CartItem> _cart = [];

  List<CartItem> get cart => List.unmodifiable(_cart);

  int get cartCount => _cart.fold(0, (sum, item) => sum + item.quantity);

  List<CartItem> get checkedCartItems =>
      _cart.where((item) => item.isChecked).toList();

  double get selectedCartTotal {
    var total = 0.0;
    for (final item in _cart) {
      if (item.isChecked) total += item.lineTotal;
    }
    return total;
  }

  bool _sameLine(CartItem a, Product product, String size, Color color) {
    return a.product.id == product.id &&
        a.selectedSize == size &&
        a.selectedColor.toARGB32() == color.toARGB32();
  }

  /// Menambah [line] ke keranjang; jumlah digabung bila produk, ukuran, dan
  /// warna sama.
  void _mergeLine(CartItem line) {
    final index = _cart.indexWhere(
      (item) => _sameLine(item, line.product, line.selectedSize, line.selectedColor),
    );
    if (index >= 0) {
      final merged = _cart[index].quantity + line.quantity;
      _cart[index].quantity = merged > _kMaxQuantity ? _kMaxQuantity : merged;
    } else {
      _cart.add(line);
    }
  }

  void addToCart(
    Product product,
    String size,
    Color color,
    BuildContext context,
  ) {
    _mergeLine(CartItem(
      product: product,
      selectedSize: size,
      selectedColor: color,
    ));
    onProductFeedback?.call(product.id, 'cart');
    _persistCart();
    notifyListeners();
    showAppToast(
      context,
      'Item ditambahkan ke keranjang',
      icon: Icons.shopping_bag,
    );
  }

  /// "Beli lagi": memasukkan item pesanan lama. Mengembalikan jumlah baris
  /// yang berhasil ditambahkan (produk yang sudah tidak ada dilewati).
  int addOrderItemsToCart(List<OrderItem> items) {
    var added = 0;
    for (final item in items) {
      final product = _productIndex[item.productId];
      if (product == null) continue;
      final size = product.availableSizes.contains(item.size)
          ? item.size
          : (product.availableSizes.isNotEmpty
              ? product.availableSizes.first
              : item.size);
      _mergeLine(CartItem(
        product: product,
        selectedSize: size,
        selectedColor: item.color,
        quantity: item.quantity,
      ));
      added++;
    }
    if (added > 0) {
      _persistCart();
      notifyListeners();
    }
    return added;
  }

  void toggleCartCheck(int index) {
    if (index < 0 || index >= _cart.length) return;
    _cart[index].isChecked = !_cart[index].isChecked;
    _persistCart();
    notifyListeners();
  }

  void updateQuantity(int index, int change) {
    if (index < 0 || index >= _cart.length) return;
    final next = _cart[index].quantity + change;
    if (next <= 0) {
      _cart.removeAt(index);
    } else {
      _cart[index].quantity = next > _kMaxQuantity ? _kMaxQuantity : next;
    }
    _persistCart();
    notifyListeners();
  }

  void removeFromCart(int index) {
    if (index < 0 || index >= _cart.length) return;
    _cart.removeAt(index);
    _persistCart();
    notifyListeners();
  }

  void clearCheckedCart() {
    _cart.removeWhere((item) => item.isChecked);
    _persistCart();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Berita & notifikasi
  // ---------------------------------------------------------------------------

  late final List<NewsItem> _news = sortedNews(kNews);
  final Set<String> _readNews = <String>{};

  List<NewsItem> get news => _news;

  void replaceNews(List<NewsItem> items) {
    _news
      ..clear()
      ..addAll(sortedNews(items));
    notifyListeners();
  }

  NewsItem? newsById(String id) {
    for (final item in _news) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool isNewsRead(String id) => _readNews.contains(id);

  int get unreadNewsCount =>
      _news.where((item) => !_readNews.contains(item.id)).length;

  void markNewsRead(String id) {
    if (!_readNews.add(id)) return;
    _save(_kNewsReadKey, jsonEncode(_readNews.toList()));
    notifyListeners();
  }

  void markAllNewsRead() {
    final before = _readNews.length;
    _readNews.addAll(_news.map((item) => item.id));
    if (_readNews.length == before) return;
    _save(_kNewsReadKey, jsonEncode(_readNews.toList()));
    notifyListeners();
  }

  /// Pemberitahuan umum yang tampil di pusat notifikasi.
  List<String> get notifications => const [
        'Koleksi LifeWear terbaru sudah tersedia.',
        'Temukan item AIRism dan HEATTECH untuk kebutuhan harian.',
        'Gabung member untuk diskon level, poin, dan voucher eksklusif.',
      ];

  // ---------------------------------------------------------------------------
  // Riwayat pencarian
  // ---------------------------------------------------------------------------

  List<String> _recentSearches = [];

  List<String> get recentSearches => List.unmodifiable(_recentSearches);

  void addRecentSearch(String query) {
    final text = query.trim();
    if (text.length < 2) return;
    _recentSearches.removeWhere((q) => q.toLowerCase() == text.toLowerCase());
    _recentSearches.insert(0, text);
    if (_recentSearches.length > _kMaxRecentSearches) {
      _recentSearches = _recentSearches.take(_kMaxRecentSearches).toList();
    }
    _save(_kRecentSearchKey, jsonEncode(_recentSearches));
    notifyListeners();
  }

  void removeRecentSearch(String query) {
    if (!_recentSearches.remove(query)) return;
    _save(_kRecentSearchKey, jsonEncode(_recentSearches));
    notifyListeners();
  }

  void clearRecentSearches() {
    if (_recentSearches.isEmpty) return;
    _recentSearches = [];
    _remove(_kRecentSearchKey);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Terakhir dilihat (hanya selama aplikasi berjalan)
  // ---------------------------------------------------------------------------

  final List<Product> _recentlyViewed = [];

  List<Product> get recentlyViewed => List.unmodifiable(_recentlyViewed);

  void markViewed(Product product) {
    onProductFeedback?.call(product.id, 'view');
    if (_recentlyViewed.isNotEmpty && _recentlyViewed.first.id == product.id) {
      return;
    }
    _recentlyViewed.removeWhere((p) => p.id == product.id);
    _recentlyViewed.insert(0, product);
    if (_recentlyViewed.length > 10) _recentlyViewed.removeLast();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Ulasan & rating
  // ---------------------------------------------------------------------------

  List<Review> _userReviews = [];
  List<Review> _serverReviews = [];
  bool _serverReviewsLoaded = false;

  void replaceServerReviews(List<Review> reviews) {
    _serverReviews = List<Review>.unmodifiable(reviews);
    _serverReviewsLoaded = true;
    notifyListeners();
  }

  List<Review> get userReviews => List.unmodifiable(_userReviews);

  /// Ulasan produk (ulasan pengguna + data contoh), terbaru lebih dulu.
  List<Review> reviewsFor(String productId) {
    final list = _serverReviewsLoaded
        ? <String, Review>{
            for (final r in _serverReviews.where((r) => r.productId == productId)) r.id: r,
            for (final r in _userReviews.where((r) => r.productId == productId)) r.id: r,
          }.values.toList()
        : [
            ..._userReviews.where((r) => r.productId == productId),
            ...sampleReviewsFor(productId),
          ];
    list.sort((a, b) => b.at.compareTo(a.at));
    return list;
  }

  RatingSummary ratingOf(Product product) {
    // Rating resmi Uniqlo + ulasan nyata dari pengguna aplikasi (ulasan
    // contoh tidak ikut dihitung bila produk sudah punya rating resmi).
    if (product.ratingCount > 0) {
      var total = product.ratingAverage * product.ratingCount;
      var count = product.ratingCount;
      for (final r in reviewsFor(product.id)) {
        if (r.isSample) continue;
        total += r.rating;
        count++;
      }
      return RatingSummary(total / count, count);
    }
    final reviews = reviewsFor(product.id);
    if (reviews.isEmpty) return const RatingSummary(0, 0);
    final total = reviews.fold<int>(0, (sum, r) => sum + r.rating);
    return RatingSummary(total / reviews.length, reviews.length);
  }

  bool hasReviewed(String productId, String memberId) {
    return [..._userReviews, ..._serverReviews].any(
      (r) => !r.isSample && r.productId == productId && r.memberId == memberId,
    );
  }

  Future<void> addReview({
    required Product product,
    required String memberId,
    required String author,
    required int rating,
    required String text,
  }) async {
    final now = DateTime.now();
    _userReviews = [
      ..._userReviews,
      Review(
        id: 'r-${now.microsecondsSinceEpoch}',
        productId: product.id,
        memberId: memberId,
        author: author,
        rating: rating.clamp(1, 5).toInt(),
        text: text.trim(),
        at: now,
      ),
    ];
    notifyListeners();
    _save(
      _kReviewsKey,
      jsonEncode(_userReviews.map((r) => r.toJson()).toList()),
    );
    onMemberDataChanged?.call();
  }

  // ---------------------------------------------------------------------------
  // Penyimpanan lokal
  // ---------------------------------------------------------------------------

  void _save(String key, String value) {
    unawaited(_store.setString(key, value).catchError((Object _) {}));
  }

  void _remove(String key) {
    unawaited(_store.remove(key).catchError((Object _) {}));
  }

  void _persistCart() {
    _save(
      '$_kCartKey${_ownerKey(_activeMemberId)}',
      jsonEncode([
        for (final item in _cart)
          {
            'productId': item.product.id,
            'size': item.selectedSize,
            'color': item.selectedColor.toARGB32(),
            'quantity': item.quantity,
            'checked': item.isChecked,
          },
      ]),
    );
    onMemberDataChanged?.call();
  }

  void _persistWishlist() {
    _save(
      '$_kWishlistKey${_ownerKey(_activeMemberId)}',
      jsonEncode(_wishlist.map((p) => p.id).toList()),
    );
    onMemberDataChanged?.call();
  }

  List<CartItem> _decodeCart(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final result = <CartItem>[];
      for (final entry in jsonDecode(raw) as List) {
        final map = Map<String, dynamic>.from(entry as Map);
        final product = _productIndex[map['productId']];
        if (product == null) continue;
        result.add(CartItem(
          product: product,
          selectedSize: map['size'] as String,
          selectedColor: Color((map['color'] as num).toInt()),
          quantity:
              ((map['quantity'] as num).toInt()).clamp(1, _kMaxQuantity).toInt(),
          isChecked: (map['checked'] as bool?) ?? true,
        ));
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  List<Product> _decodeWishlist(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final result = <Product>[];
      for (final id in jsonDecode(raw) as List) {
        final product = _productIndex[id];
        if (product != null) result.add(product);
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  void _restoreShared() {
    try {
      final read = _store.getString(_kNewsReadKey);
      if (read != null) {
        _readNews.addAll((jsonDecode(read) as List).map((e) => e.toString()));
      }
    } catch (_) {}

    try {
      final recent = _store.getString(_kRecentSearchKey);
      if (recent != null) {
        _recentSearches =
            (jsonDecode(recent) as List).map((e) => e.toString()).toList();
      }
    } catch (_) {}

    try {
      final reviews = _store.getString(_kReviewsKey);
      if (reviews != null) {
        _userReviews = (jsonDecode(reviews) as List)
            .map((e) => Review.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
  }
}
