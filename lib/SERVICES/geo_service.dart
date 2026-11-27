import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Hasil pencarian tempat (Nominatim / OpenStreetMap).
class PlaceResult {
  final String title;
  final String address;
  final double lat;
  final double lng;

  const PlaceResult({
    required this.title,
    required this.address,
    required this.lat,
    required this.lng,
  });
}

/// Hasil permintaan GPS: posisi, atau pesan kesalahan siap tampil.
class GpsResult {
  final double? lat;
  final double? lng;
  final String? error;

  const GpsResult.ok(this.lat, this.lng) : error = null;
  const GpsResult.fail(this.error)
      : lat = null,
        lng = null;

  bool get ok => error == null;
}

/// Pencarian alamat (geocoding), alamat dari titik peta (reverse geocoding),
/// dan posisi GPS. Memakai Nominatim OpenStreetMap, tanpa API key.
class GeoService {
  GeoService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _host = 'nominatim.openstreetmap.org';
  static const _timeout = Duration(seconds: 12);
  static const _headers = {
    'Accept': 'application/json',
    'Accept-Language': 'id',
  };

  /// Mencari tempat/alamat di Indonesia. Daftar kosong bila tidak ada / gagal.
  Future<List<PlaceResult>> search(String query) async {
    final text = query.trim();
    if (text.length < 3) return const [];
    try {
      final uri = Uri.https(_host, '/search', {
        'q': text,
        'format': 'jsonv2',
        'countrycodes': 'id',
        'limit': '6',
        'addressdetails': '0',
      });
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return const [];
      final results = <PlaceResult>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final lat = double.tryParse('${item['lat']}');
        final lng = double.tryParse('${item['lon']}');
        if (lat == null || lng == null) continue;
        final full = '${item['display_name'] ?? ''}';
        final name = '${item['name'] ?? ''}'.trim();
        results.add(PlaceResult(
          title: name.isNotEmpty ? name : full.split(',').first,
          address: full,
          lat: lat,
          lng: lng,
        ));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Alamat teks dari koordinat. `null` bila gagal (mis. offline).
  Future<String?> reverse(double lat, double lng) async {
    try {
      final uri = Uri.https(_host, '/reverse', {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'jsonv2',
        'zoom': '18',
      });
      final response =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['display_name'] is String) {
        return decoded['display_name'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// Posisi perangkat saat ini lewat GPS (meminta izin bila perlu).
  Future<GpsResult> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const GpsResult.fail('Layanan lokasi (GPS) belum aktif.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const GpsResult.fail('Izin lokasi ditolak.');
      }
      if (permission == LocationPermission.deniedForever) {
        return const GpsResult.fail(
            'Izin lokasi diblokir. Aktifkan lewat pengaturan perangkat/browser.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return GpsResult.ok(position.latitude, position.longitude);
    } on TimeoutException {
      return const GpsResult.fail('Lokasi tidak ditemukan. Coba lagi.');
    } catch (_) {
      return const GpsResult.fail('Tidak bisa mengambil lokasi saat ini.');
    }
  }

  void dispose() => _client.close();
}
