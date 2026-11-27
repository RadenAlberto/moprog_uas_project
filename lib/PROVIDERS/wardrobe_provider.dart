import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../MODELS/studio_models.dart';
import '../SERVICES/photo_store.dart';
import '../UTILS/key_value_store.dart';

const String _kWardrobeKey = 'wardrobe_v1_';

/// Lemari digital: pakaian milik pengguna (foto tanpa latar) per akun.
class WardrobeProvider extends ChangeNotifier {
  WardrobeProvider({required KeyValueStore store, required PhotoStore photos})
      : _store = store,
        _photos = photos;

  final KeyValueStore _store;
  final PhotoStore _photos;

  List<WardrobeItem> _items = [];
  String? _owner;
  bool _ready = false;

  List<WardrobeItem> get items => List.unmodifiable(_items);

  List<WardrobeItem> bySlot(ClothingSlot slot) =>
      _items.where((i) => i.slot == slot).toList(growable: false);

  WardrobeItem? byId(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  String get _key => '$_kWardrobeKey${_owner ?? 'guest'}';

  /// Memuat lemari milik [memberId] (`null` = tamu).
  void setActiveMember(String? memberId) {
    if (_ready && _owner == memberId) return;
    _owner = memberId;
    _ready = true;
    _items = _load();
    notifyListeners();
  }

  List<WardrobeItem> _load() {
    final raw = _store.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final json = jsonDecode(raw);
      if (json is! List) return [];
      return [
        for (final entry in json)
          if (WardrobeItem.fromJson(entry) != null) WardrobeItem.fromJson(entry)!,
      ];
    } catch (_) {
      return [];
    }
  }

  void _persist() {
    unawaited(
      _store.setString(_key, jsonEncode([for (final i in _items) i.toJson()])),
    );
  }

  /// Menyimpan pakaian baru. [png] adalah foto tanpa latar.
  Future<WardrobeItem> addItem({
    required String name,
    required ClothingSlot slot,
    required int colorArgb,
    required Uint8List png,
    String note = '',
  }) async {
    final file = await _photos.save(png, prefix: 'wardrobe');
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = WardrobeItem(
      id: 'w$now',
      name: name.trim().isEmpty ? slot.label : name.trim(),
      slot: slot,
      colorArgb: colorArgb,
      photo: file,
      createdAt: now,
      note: note,
    );
    _items = [item, ..._items];
    _persist();
    notifyListeners();
    return item;
  }

  void updateItem(
    String id, {
    String? name,
    ClothingSlot? slot,
    int? colorArgb,
    String? note,
  }) {
    final index = _items.indexWhere((i) => i.id == id);
    if (index < 0) return;
    final trimmed = name?.trim();
    final next = List<WardrobeItem>.of(_items);
    next[index] = _items[index].copyWith(
      name: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      slot: slot,
      colorArgb: colorArgb,
      note: note,
    );
    _items = next;
    _persist();
    notifyListeners();
  }

  Future<void> removeItem(String id) async {
    final item = byId(id);
    if (item == null) return;
    _items = _items.where((i) => i.id != id).toList();
    _persist();
    notifyListeners();
    await _photos.delete(item.photo);
  }
}
