import 'dart:convert';

import 'package:http/http.dart' as http;

import '../MODELS/studio_models.dart';

/// Ramalan cuaca dan pencarian kota lewat Open-Meteo (gratis, tanpa API key).
///
/// Untuk memakai OpenWeather, cukup ganti isi [forecast] dan [searchCity];
/// provider dan layar hanya bergantung pada [WeatherDay] dan [GeoPlace].
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  Future<List<GeoPlace>> searchCity(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': q,
      'count': '6',
      'language': 'id',
    });
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Pencarian kota gagal (${response.statusCode})');
    }
    return parsePlaces(response.body);
  }

  Future<List<WeatherDay>> forecast(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
      'timezone': 'auto',
      'forecast_days': '7',
    });
    final response = await _client.get(uri).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Cuaca tidak bisa dimuat (${response.statusCode})');
    }
    return parseForecast(response.body);
  }

  void dispose() => _client.close();

  /// Dipisahkan agar bisa diuji tanpa jaringan.
  static List<GeoPlace> parsePlaces(String body) {
    final json = jsonDecode(body);
    if (json is! Map) return const [];
    final results = json['results'];
    if (results is! List) return const [];
    final places = <GeoPlace>[];
    for (final r in results) {
      if (r is! Map) continue;
      final name = r['name'];
      final lat = r['latitude'];
      final lon = r['longitude'];
      if (name is! String || lat is! num || lon is! num) continue;
      places.add(
        GeoPlace(
          name: name,
          admin: r['admin1'] is String ? r['admin1'] as String : '',
          country: r['country'] is String ? r['country'] as String : '',
          lat: lat.toDouble(),
          lon: lon.toDouble(),
        ),
      );
    }
    return places;
  }

  static List<WeatherDay> parseForecast(String body) {
    final json = jsonDecode(body);
    if (json is! Map) return const [];
    final daily = json['daily'];
    if (daily is! Map) return const [];
    final times = daily['time'];
    final codes = daily['weather_code'];
    final maxes = daily['temperature_2m_max'];
    final mins = daily['temperature_2m_min'];
    final rain = daily['precipitation_probability_max'];
    if (times is! List || codes is! List || maxes is! List || mins is! List) {
      return const [];
    }
    final days = <WeatherDay>[];
    for (var i = 0; i < times.length; i++) {
      final date = DateTime.tryParse('${times[i]}');
      final code = i < codes.length ? codes[i] : null;
      final tMax = i < maxes.length ? maxes[i] : null;
      final tMin = i < mins.length ? mins[i] : null;
      if (date == null || code is! num || tMax is! num || tMin is! num) continue;
      final prob = rain is List && i < rain.length && rain[i] is num
          ? (rain[i] as num).round()
          : 0;
      days.add(
        WeatherDay(
          date: DateTime(date.year, date.month, date.day),
          tMax: tMax.toDouble(),
          tMin: tMin.toDouble(),
          precipProbability: prob,
          code: code.toInt(),
        ),
      );
    }
    return days;
  }
}
