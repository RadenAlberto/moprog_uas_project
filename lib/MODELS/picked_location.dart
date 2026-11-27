/// Lokasi yang dipilih pengguna lewat peta: teks alamat + koordinat.
class PickedLocation {
  final String address;
  final double lat;
  final double lng;

  const PickedLocation({
    required this.address,
    required this.lat,
    required this.lng,
  });

  /// Tautan Google Maps ke titik ini.
  String get mapsUrl =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  String get coordinateLabel =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  PickedLocation copyWith({String? address}) =>
      PickedLocation(address: address ?? this.address, lat: lat, lng: lng);
}
