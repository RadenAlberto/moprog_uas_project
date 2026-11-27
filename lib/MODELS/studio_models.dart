import 'package:flutter/material.dart';

import 'style_model.dart' show Gender;

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

// -----------------------------------------------------------------------------
// Virtual Wardrobe
// -----------------------------------------------------------------------------

/// Posisi pakaian pada tubuh. Dipakai untuk mix & match dan Virtual Try-On.
enum ClothingSlot {
  top('Atasan', Icons.checkroom),
  bottom('Bawahan', Icons.straighten),
  outer('Luaran', Icons.layers_outlined),
  dress('Terusan', Icons.woman),
  accessory('Aksesori', Icons.watch_outlined);

  const ClothingSlot(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Satu pakaian milik pengguna di lemari digital.
class WardrobeItem {
  const WardrobeItem({
    required this.id,
    required this.name,
    required this.slot,
    required this.colorArgb,
    required this.photo,
    required this.createdAt,
    this.note = '',
  });

  final String id;
  final String name;
  final ClothingSlot slot;
  final int colorArgb;

  /// Nama berkas foto (PNG tanpa latar) di `PhotoStore`.
  final String photo;
  final int createdAt;
  final String note;

  Color get color => Color(colorArgb);

  WardrobeItem copyWith({
    String? name,
    ClothingSlot? slot,
    int? colorArgb,
    String? note,
  }) {
    return WardrobeItem(
      id: id,
      name: name ?? this.name,
      slot: slot ?? this.slot,
      colorArgb: colorArgb ?? this.colorArgb,
      photo: photo,
      createdAt: createdAt,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slot': slot.name,
        'color': colorArgb,
        'photo': photo,
        'createdAt': createdAt,
        'note': note,
      };

  static WardrobeItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final photo = raw['photo'];
    final slot = _byName(ClothingSlot.values, raw['slot']);
    final color = raw['color'];
    if (id is! String || name is! String || photo is! String) return null;
    if (slot == null || color is! int) return null;
    return WardrobeItem(
      id: id,
      name: name,
      slot: slot,
      colorArgb: color,
      photo: photo,
      createdAt: raw['createdAt'] is int ? raw['createdAt'] as int : 0,
      note: raw['note'] is String ? raw['note'] as String : '',
    );
  }
}

// -----------------------------------------------------------------------------
// AI Stylist (cuaca + agenda)
// -----------------------------------------------------------------------------

/// Tingkat keformalan acara.
enum DressCode {
  sport('Olahraga', 0, Icons.directions_run),
  casual('Kasual', 1, Icons.weekend_outlined),
  smart('Smart casual', 2, Icons.badge_outlined),
  formal('Formal / meeting', 3, Icons.business_center_outlined);

  const DressCode(this.label, this.level, this.icon);

  final String label;
  final int level;
  final IconData icon;
}

class AgendaEvent {
  const AgendaEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.dressCode,
    this.place = '',
  });

  final String id;
  final String title;
  final DateTime start;
  final DressCode dressCode;
  final String place;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'dress': dressCode.name,
        'place': place,
      };

  static AgendaEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final start = raw['start'];
    final dress = _byName(DressCode.values, raw['dress']);
    if (id is! String || title is! String || start is! int || dress == null) {
      return null;
    }
    return AgendaEvent(
      id: id,
      title: title,
      start: DateTime.fromMillisecondsSinceEpoch(start),
      dressCode: dress,
      place: raw['place'] is String ? raw['place'] as String : '',
    );
  }
}

/// Lokasi untuk ramalan cuaca.
class GeoPlace {
  const GeoPlace({
    required this.name,
    required this.admin,
    required this.country,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String admin;
  final String country;
  final double lat;
  final double lon;

  String get label {
    final parts = [name, if (admin.isNotEmpty) admin, if (country.isNotEmpty) country];
    return parts.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'admin': admin,
        'country': country,
        'lat': lat,
        'lon': lon,
      };

  static GeoPlace? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final lat = _num(raw['lat']);
    final lon = _num(raw['lon']);
    if (name is! String || lat == null || lon == null) return null;
    return GeoPlace(
      name: name,
      admin: raw['admin'] is String ? raw['admin'] as String : '',
      country: raw['country'] is String ? raw['country'] as String : '',
      lat: lat,
      lon: lon,
    );
  }
}

/// Ramalan cuaca satu hari.
class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.tMax,
    required this.tMin,
    required this.precipProbability,
    required this.code,
  });

  final DateTime date;
  final double tMax;
  final double tMin;

  /// Peluang hujan 0..100.
  final int precipProbability;

  /// Kode cuaca WMO (Open-Meteo).
  final int code;

  bool get isRainy =>
      (code >= 51 && code <= 67) ||
      (code >= 80 && code <= 82) ||
      code >= 95 ||
      precipProbability >= 50;

  String get description {
    if (code == 0) return 'Cerah';
    if (code <= 3) return 'Berawan';
    if (code == 45 || code == 48) return 'Berkabut';
    if (code >= 51 && code <= 57) return 'Gerimis';
    if (code >= 61 && code <= 67) return 'Hujan';
    if (code >= 80 && code <= 82) return 'Hujan sesaat';
    if (code >= 95) return 'Badai petir';
    return 'Berawan';
  }

  IconData get icon {
    if (code >= 95) return Icons.thunderstorm_outlined;
    if (isRainy) return Icons.water_drop_outlined;
    if (code == 0) return Icons.wb_sunny_outlined;
    return Icons.cloud_outlined;
  }
}

// -----------------------------------------------------------------------------
// Price Tracker
// -----------------------------------------------------------------------------

class PricePoint {
  const PricePoint(this.at, this.price);

  final int at;
  final double price;

  Map<String, dynamic> toJson() => {'at': at, 'price': price};

  static PricePoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    final price = _num(raw['price']);
    if (at is! int || price == null) return null;
    return PricePoint(at, price);
  }
}

/// Produk + ukuran yang dilacak pengguna.
class TrackedItem {
  const TrackedItem({
    required this.productId,
    required this.size,
    required this.startPrice,
    required this.lastPrice,
    required this.sizeAvailable,
    required this.createdAt,
    this.colorArgb,
    this.targetPrice,
    this.targetNotified = false,
    this.history = const [],
  });

  final String productId;
  final String size;
  final int? colorArgb;
  final double startPrice;
  final double lastPrice;
  final bool sizeAvailable;
  final int createdAt;

  /// Beri tahu saat harga <= nilai ini. `null` = setiap kali harga turun.
  final double? targetPrice;
  final bool targetNotified;
  final List<PricePoint> history;

  String get key => '$productId|$size';

  TrackedItem copyWith({
    double? lastPrice,
    bool? sizeAvailable,
    double? targetPrice,
    bool clearTarget = false,
    bool? targetNotified,
    List<PricePoint>? history,
  }) {
    return TrackedItem(
      productId: productId,
      size: size,
      colorArgb: colorArgb,
      startPrice: startPrice,
      lastPrice: lastPrice ?? this.lastPrice,
      sizeAvailable: sizeAvailable ?? this.sizeAvailable,
      createdAt: createdAt,
      targetPrice: clearTarget ? null : (targetPrice ?? this.targetPrice),
      targetNotified: targetNotified ?? this.targetNotified,
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'size': size,
        'color': colorArgb,
        'startPrice': startPrice,
        'lastPrice': lastPrice,
        'sizeAvailable': sizeAvailable,
        'createdAt': createdAt,
        'target': targetPrice,
        'targetNotified': targetNotified,
        'history': [for (final h in history) h.toJson()],
      };

  static TrackedItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final productId = raw['productId'];
    final size = raw['size'];
    final start = _num(raw['startPrice']);
    final last = _num(raw['lastPrice']);
    if (productId is! String || size is! String) return null;
    if (start == null || last == null) return null;
    final history = <PricePoint>[];
    final rawHistory = raw['history'];
    if (rawHistory is List) {
      for (final h in rawHistory) {
        final point = PricePoint.fromJson(h);
        if (point != null) history.add(point);
      }
    }
    return TrackedItem(
      productId: productId,
      size: size,
      colorArgb: raw['color'] is int ? raw['color'] as int : null,
      startPrice: start,
      lastPrice: last,
      sizeAvailable: raw['sizeAvailable'] != false,
      createdAt: raw['createdAt'] is int ? raw['createdAt'] as int : 0,
      targetPrice: _num(raw['target']),
      targetNotified: raw['targetNotified'] == true,
      history: history,
    );
  }
}

enum AlertKind {
  priceDrop('Harga turun', Icons.trending_down, Color(0xFF2E7D32)),
  targetReached('Harga target tercapai', Icons.flag_outlined, Color(0xFFEC1C24)),
  restock('Stok kembali', Icons.inventory_2_outlined, Color(0xFF1565C0)),
  soldOut('Ukuran habis', Icons.remove_shopping_cart_outlined, Color(0xFF6B6B70));

  const AlertKind(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}

class TrackerAlert {
  const TrackerAlert({
    required this.id,
    required this.kind,
    required this.productId,
    required this.title,
    required this.body,
    required this.at,
    this.read = false,
  });

  final String id;
  final AlertKind kind;
  final String productId;
  final String title;
  final String body;
  final int at;
  final bool read;

  TrackerAlert markRead() => TrackerAlert(
        id: id,
        kind: kind,
        productId: productId,
        title: title,
        body: body,
        at: at,
        read: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'productId': productId,
        'title': title,
        'body': body,
        'at': at,
        'read': read,
      };

  static TrackerAlert? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = _byName(AlertKind.values, raw['kind']);
    final id = raw['id'];
    final productId = raw['productId'];
    final title = raw['title'];
    final body = raw['body'];
    final at = raw['at'];
    if (kind == null || id is! String || productId is! String) return null;
    if (title is! String || body is! String || at is! int) return null;
    return TrackerAlert(
      id: id,
      kind: kind,
      productId: productId,
      title: title,
      body: body,
      at: at,
      read: raw['read'] == true,
    );
  }
}

// -----------------------------------------------------------------------------
// Fit & Size
// -----------------------------------------------------------------------------

enum FitPreference {
  snug('Pas badan', -1),
  regular('Reguler', 0),
  loose('Longgar', 1);

  const FitPreference(this.label, this.level);

  final String label;

  /// -1 ketat, 0 reguler, 1 longgar.
  final int level;
}

class FitProfile {
  const FitProfile({
    this.gender = Gender.female,
    this.heightCm = 160,
    this.weightKg = 52,
    this.preference = FitPreference.regular,
  });

  final Gender gender;
  final double heightCm;
  final double weightKg;
  final FitPreference preference;

  double get bmi {
    final m = heightCm / 100;
    return m <= 0 ? 0 : weightKg / (m * m);
  }

  FitProfile copyWith({
    Gender? gender,
    double? heightCm,
    double? weightKg,
    FitPreference? preference,
  }) {
    return FitProfile(
      gender: gender ?? this.gender,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      preference: preference ?? this.preference,
    );
  }

  Map<String, dynamic> toJson() => {
        'gender': gender.name,
        'height': heightCm,
        'weight': weightKg,
        'pref': preference.name,
      };

  static FitProfile? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final gender = _byName(Gender.values, raw['gender']);
    final height = _num(raw['height']);
    final weight = _num(raw['weight']);
    final pref = _byName(FitPreference.values, raw['pref']);
    if (gender == null || height == null || weight == null || pref == null) {
      return null;
    }
    if (height < 100 || height > 230 || weight < 25 || weight > 250) return null;
    return FitProfile(
      gender: gender,
      heightCm: height,
      weightKg: weight,
      preference: pref,
    );
  }
}

// -----------------------------------------------------------------------------
// Komunitas OOTD
// -----------------------------------------------------------------------------

enum SkinTone {
  light('Cerah'),
  medium('Sedang'),
  deep('Gelap');

  const SkinTone(this.label);

  final String label;
}

class OotdComment {
  const OotdComment({
    required this.author,
    required this.text,
    required this.at,
  });

  final String author;
  final String text;
  final int at;

  Map<String, dynamic> toJson() => {'author': author, 'text': text, 'at': at};

  static OotdComment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final author = raw['author'];
    final text = raw['text'];
    final at = raw['at'];
    if (author is! String || text is! String || at is! int) return null;
    return OotdComment(author: author, text: text, at: at);
  }
}

class OotdPost {
  const OotdPost({
    required this.id,
    required this.author,
    required this.caption,
    required this.createdAt,
    this.photo,
    this.productIds = const [],
    this.heightCm,
    this.weightKg,
    this.sizeWorn = '',
    this.skinTone,
    this.likes = 0,
    this.likedByMe = false,
    this.comments = const [],
    this.isSample = false,
  });

  final String id;
  final String author;
  final String caption;
  final int createdAt;

  /// Berkas foto di `PhotoStore`; `null` = tanpa foto (contoh).
  final String? photo;
  final List<String> productIds;
  final double? heightCm;
  final double? weightKg;
  final String sizeWorn;
  final SkinTone? skinTone;
  final int likes;
  final bool likedByMe;
  final List<OotdComment> comments;

  /// Contoh bawaan aplikasi (tidak disimpan).
  final bool isSample;

  OotdPost copyWith({
    int? likes,
    bool? likedByMe,
    List<OotdComment>? comments,
  }) {
    return OotdPost(
      id: id,
      author: author,
      caption: caption,
      createdAt: createdAt,
      photo: photo,
      productIds: productIds,
      heightCm: heightCm,
      weightKg: weightKg,
      sizeWorn: sizeWorn,
      skinTone: skinTone,
      likes: likes ?? this.likes,
      likedByMe: likedByMe ?? this.likedByMe,
      comments: comments ?? this.comments,
      isSample: isSample,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'caption': caption,
        'createdAt': createdAt,
        'photo': photo,
        'products': productIds,
        'height': heightCm,
        'weight': weightKg,
        'size': sizeWorn,
        'skin': skinTone?.name,
        'likes': likes,
        'liked': likedByMe,
        'comments': [for (final c in comments) c.toJson()],
      };

  static OotdPost? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final author = raw['author'];
    final caption = raw['caption'];
    if (id is! String || author is! String || caption is! String) return null;
    final comments = <OotdComment>[];
    final rawComments = raw['comments'];
    if (rawComments is List) {
      for (final c in rawComments) {
        final comment = OotdComment.fromJson(c);
        if (comment != null) comments.add(comment);
      }
    }
    final rawProducts = raw['products'];
    return OotdPost(
      id: id,
      author: author,
      caption: caption,
      createdAt: raw['createdAt'] is int ? raw['createdAt'] as int : 0,
      photo: raw['photo'] is String ? raw['photo'] as String : null,
      productIds: rawProducts is List
          ? [for (final p in rawProducts) if (p is String) p]
          : const [],
      heightCm: _num(raw['height']),
      weightKg: _num(raw['weight']),
      sizeWorn: raw['size'] is String ? raw['size'] as String : '',
      skinTone: _byName(SkinTone.values, raw['skin']),
      likes: raw['likes'] is int ? raw['likes'] as int : 0,
      likedByMe: raw['liked'] == true,
      comments: comments,
    );
  }
}
