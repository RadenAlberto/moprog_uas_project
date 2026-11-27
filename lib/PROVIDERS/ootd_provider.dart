import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../SERVICES/photo_store.dart';
import '../UTILS/key_value_store.dart';

const String _kOotdKey = 'ootd_v1';
const int _kMaxPosts = 100;

/// Komunitas OOTD: unggahan pengguna di perangkat ini, ditandai dengan produk
/// katalog. Foto disimpan lokal lewat [PhotoStore].
///
/// Contoh unggahan bawaan (tanpa foto) ditampilkan di bawah unggahan asli agar
/// halaman tidak kosong; ditandai "Contoh" dan tidak disimpan.
class OotdProvider extends ChangeNotifier {
  OotdProvider({required KeyValueStore store, required PhotoStore photos})
      : _store = store,
        _photos = photos {
    _posts = _load();
  }

  final KeyValueStore _store;
  final PhotoStore _photos;

  List<OotdPost> _posts = [];
  final Map<String, OotdPost> _sampleOverrides = {};
  List<OotdPost>? _samples;
  List<Product>? _samplesFor;

  List<OotdPost> get myPosts => List.unmodifiable(_posts);

  List<OotdPost> _load() {
    final raw = _store.getString(_kOotdKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final json = jsonDecode(raw);
      if (json is! List) return [];
      final posts = <OotdPost>[];
      for (final e in json) {
        final post = OotdPost.fromJson(e);
        if (post != null) posts.add(post);
      }
      return posts;
    } catch (_) {
      return [];
    }
  }

  void _persist() {
    unawaited(
      _store.setString(_kOotdKey, jsonEncode([for (final p in _posts) p.toJson()])),
    );
  }

  /// Semua unggahan: milik pengguna dulu (terbaru di atas), lalu contoh.
  List<OotdPost> feed(List<Product> catalog) {
    final sorted = [..._posts]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      ...sorted,
      for (final s in _samplePosts(catalog)) _sampleOverrides[s.id] ?? s,
    ];
  }

  OotdPost? byId(String id, List<Product> catalog) {
    for (final p in feed(catalog)) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<OotdPost> addPost({
    required String author,
    required String caption,
    Uint8List? photoPng,
    List<String> productIds = const [],
    double? heightCm,
    double? weightKg,
    String sizeWorn = '',
    SkinTone? skinTone,
  }) async {
    String? file;
    if (photoPng != null) {
      file = await _photos.save(photoPng, prefix: 'ootd');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final post = OotdPost(
      id: 'o$now',
      author: author,
      caption: caption.trim(),
      createdAt: now,
      photo: file,
      productIds: productIds,
      heightCm: heightCm,
      weightKg: weightKg,
      sizeWorn: sizeWorn,
      skinTone: skinTone,
    );
    _posts = [post, ..._posts];
    if (_posts.length > _kMaxPosts) {
      final removed = _posts.sublist(_kMaxPosts);
      _posts = _posts.sublist(0, _kMaxPosts);
      for (final r in removed) {
        final f = r.photo;
        if (f != null) unawaited(_photos.delete(f));
      }
    }
    _persist();
    notifyListeners();
    return post;
  }

  Future<void> deletePost(String id) async {
    OotdPost? target;
    for (final p in _posts) {
      if (p.id == id) target = p;
    }
    if (target == null) return;
    _posts = _posts.where((p) => p.id != id).toList();
    _persist();
    notifyListeners();
    final file = target.photo;
    if (file != null) await _photos.delete(file);
  }

  void _replace(OotdPost post) {
    if (post.isSample) {
      _sampleOverrides[post.id] = post;
    } else {
      _posts = [for (final p in _posts) p.id == post.id ? post : p];
      _persist();
    }
    notifyListeners();
  }

  void toggleLike(OotdPost post) {
    _replace(
      post.copyWith(
        likedByMe: !post.likedByMe,
        likes: post.likedByMe ? (post.likes - 1).clamp(0, 1 << 30).toInt() : post.likes + 1,
      ),
    );
  }

  void addComment(OotdPost post, String author, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _replace(
      post.copyWith(
        comments: [
          ...post.comments,
          OotdComment(
            author: author,
            text: clean,
            at: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
      ),
    );
  }

  // --- Contoh bawaan -----------------------------------------------------------

  List<OotdPost> _samplePosts(List<Product> catalog) {
    if (identical(_samplesFor, catalog) && _samples != null) return _samples!;
    _samplesFor = catalog;

    Product? first(bool Function(Product) test) {
      for (final p in catalog) {
        if (test(p)) return p;
      }
      return null;
    }

    bool text(Product p, String k) =>
        '${p.name} ${p.description} ${p.features.join(' ')}'.toLowerCase().contains(k);
    bool women(Product p) => p.audience == 'Women' || p.audience == 'Unisex';
    bool men(Product p) => p.audience == 'Men' || p.audience == 'Unisex';

    final specs = <(String, String, double, double, String, SkinTone, List<Product?>)>[
      (
        'Rani, Palembang',
        'Kemeja rayon dan celana ankle untuk kuliah pagi. Nyaman, tidak gerah.',
        158.0,
        49.0,
        'M',
        SkinTone.medium,
        [
          first((p) => p.category == 'Shirts' && p.audience == 'Women' && text(p, 'rayon')),
          first((p) => p.category == 'Pants' && women(p) && text(p, 'ankle')),
        ],
      ),
      (
        'Dimas',
        'Kaos oversized dan jeans, andalan akhir pekan. Ambil satu ukuran lebih kecil.',
        172.0,
        68.0,
        'L',
        SkinTone.deep,
        [
          first((p) => p.category == 'T-Shirts' && men(p) && text(p, 'oversize')),
          first((p) => p.category == 'Jeans' && men(p)),
        ],
      ),
      (
        'Salsa',
        'Outer tahan air buat musim hujan, ringan dan masih rapi untuk ke kantor.',
        165.0,
        58.0,
        'M',
        SkinTone.light,
        [
          first((p) => p.category == 'Outerwear' && women(p) && text(p, 'water')),
          first((p) => p.category == 'T-Shirts' && p.audience == 'Women'),
        ],
      ),
      (
        'Bagas',
        'Polo dan chino untuk hari kerja. Badan tinggi, ukuran XL pas di bahu.',
        180.0,
        82.0,
        'XL',
        SkinTone.medium,
        [
          first((p) => p.category == 'T-Shirts' && men(p) && text(p, 'polo')),
          first((p) => p.category == 'Pants' && men(p) && text(p, 'chino')),
        ],
      ),
    ];

    final samples = <OotdPost>[];
    var index = 0;
    for (final s in specs) {
      final ids = [
        for (final p in s.$7)
          if (p != null) p.id,
      ];
      index++;
      if (ids.isEmpty) continue;
      samples.add(
        OotdPost(
          id: 'sample$index',
          author: s.$1,
          caption: s.$2,
          createdAt: 0,
          productIds: ids,
          heightCm: s.$3,
          weightKg: s.$4,
          sizeWorn: s.$5,
          skinTone: s.$6,
          likes: 12 + index * 7,
          isSample: true,
        ),
      );
    }
    _samples = samples;
    return samples;
  }
}
