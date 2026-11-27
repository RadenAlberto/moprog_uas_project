import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../MODELS/studio_models.dart';
import '../SERVICES/weather_service.dart';
import '../UTILS/key_value_store.dart';

const String _kPlaceKey = 'stylist_place_v1';
const String _kEventsKey = 'stylist_events_v1_';

const GeoPlace kDefaultPlace = GeoPlace(
  name: 'Palembang',
  admin: 'Sumatera Selatan',
  country: 'Indonesia',
  lat: -2.9761,
  lon: 104.7754,
);

/// Cuaca (Open-Meteo) dan agenda pengguna untuk AI Stylist.
///
/// Agenda disimpan di dalam aplikasi sehingga berjalan sama di HP maupun
/// laptop. Cuaca butuh internet; bila gagal, layar menawarkan pilihan manual.
class StylistProvider extends ChangeNotifier {
  StylistProvider({required KeyValueStore store, WeatherService? weather})
      : _store = store,
        _weather = weather ?? WeatherService() {
    _place = _loadPlace();
  }

  final KeyValueStore _store;
  final WeatherService _weather;

  late GeoPlace _place;
  List<WeatherDay> _forecast = const [];
  List<AgendaEvent> _events = [];
  bool _loading = false;
  String? _error;
  DateTime? _updatedAt;
  String? _owner;
  bool _ready = false;

  GeoPlace get place => _place;
  List<WeatherDay> get forecast => _forecast;
  List<AgendaEvent> get events => List.unmodifiable(_events);
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get updatedAt => _updatedAt;

  GeoPlace _loadPlace() {
    final raw = _store.getString(_kPlaceKey);
    if (raw == null) return kDefaultPlace;
    try {
      return GeoPlace.fromJson(jsonDecode(raw)) ?? kDefaultPlace;
    } catch (_) {
      return kDefaultPlace;
    }
  }

  String get _eventsKey => '$_kEventsKey${_owner ?? 'guest'}';

  void setActiveMember(String? memberId) {
    if (_ready && _owner == memberId) return;
    _owner = memberId;
    _ready = true;
    _events = _loadEvents();
    notifyListeners();
  }

  List<AgendaEvent> _loadEvents() {
    final raw = _store.getString(_eventsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final json = jsonDecode(raw);
      if (json is! List) return [];
      final events = <AgendaEvent>[];
      for (final entry in json) {
        final e = AgendaEvent.fromJson(entry);
        if (e != null) events.add(e);
      }
      events.sort((a, b) => a.start.compareTo(b.start));
      return events;
    } catch (_) {
      return [];
    }
  }

  void _persistEvents() {
    unawaited(
      _store.setString(
        _eventsKey,
        jsonEncode([for (final e in _events) e.toJson()]),
      ),
    );
  }

  // --- Cuaca -----------------------------------------------------------------

  Future<void> loadWeather() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final days = await _weather.forecast(_place.lat, _place.lon);
      if (days.isEmpty) throw Exception('Data cuaca kosong');
      _forecast = days;
      _updatedAt = DateTime.now();
    } catch (_) {
      _error = 'Cuaca tidak bisa dimuat. Periksa koneksi internet, '
          'atau atur cuaca secara manual.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<GeoPlace>> searchCity(String query) => _weather.searchCity(query);

  Future<void> setPlace(GeoPlace place) async {
    _place = place;
    _forecast = const [];
    unawaited(_store.setString(_kPlaceKey, jsonEncode(place.toJson())));
    notifyListeners();
    await loadWeather();
  }

  WeatherDay? weatherOn(DateTime day) {
    for (final d in _forecast) {
      if (d.date.year == day.year &&
          d.date.month == day.month &&
          d.date.day == day.day) {
        return d;
      }
    }
    return null;
  }

  // --- Agenda ----------------------------------------------------------------

  List<AgendaEvent> eventsOn(DateTime day) => _events
      .where((e) =>
          e.start.year == day.year &&
          e.start.month == day.month &&
          e.start.day == day.day)
      .toList(growable: false);

  /// Acara paling formal pada [day] (menentukan gaya outfit). `null` = tak ada.
  DressCode? dominantDressCode(DateTime day) {
    DressCode? top;
    for (final e in eventsOn(day)) {
      if (top == null || e.dressCode.level > top.level) top = e.dressCode;
    }
    return top;
  }

  void addEvent({
    required String title,
    required DateTime start,
    required DressCode dressCode,
    String place = '',
  }) {
    final event = AgendaEvent(
      id: 'e${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? dressCode.label : title.trim(),
      start: start,
      dressCode: dressCode,
      place: place.trim(),
    );
    _events = [..._events, event]..sort((a, b) => a.start.compareTo(b.start));
    _persistEvents();
    notifyListeners();
  }

  void removeEvent(String id) {
    _events = _events.where((e) => e.id != id).toList();
    _persistEvents();
    notifyListeners();
  }

  @override
  void dispose() {
    _weather.dispose();
    super.dispose();
  }
}
