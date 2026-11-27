/// Lokasi toko yang dimuat dari database server (dengan data fallback offline).
class StoreLocation {
  final String id;
  final String name;
  final String mall;
  final String city;
  final String address;
  final String province;
  final String phone;
  final double? latitude;
  final double? longitude;
  final int openHour;
  final int closeHour;
  final List<String> services;

  const StoreLocation({
    required this.id,
    required this.name,
    required this.mall,
    required this.city,
    required this.address,
    this.province = '',
    this.phone = '',
    this.latitude,
    this.longitude,
    this.openHour = 10,
    this.closeHour = 22,
    this.services = const [],
  });

  String get hoursLabel =>
      '${openHour.toString().padLeft(2, '0')}.00 - ${closeHour.toString().padLeft(2, '0')}.00';

  bool isOpenAt(DateTime now) => now.hour >= openHour && now.hour < closeHour;

  String get mapsQuery => 'UNIQLO $mall $city';

  factory StoreLocation.fromJson(Map<String, dynamic> json) => StoreLocation(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        mall: (json['mall'] ?? '').toString(),
        city: (json['city'] ?? '').toString(),
        address: (json['address'] ?? '').toString(),
        province: (json['province'] ?? '').toString(),
        phone: (json['phone'] ?? '').toString(),
        latitude: (json['lat'] as num?)?.toDouble(),
        longitude: (json['lng'] as num?)?.toDouble(),
        openHour: (json['open_hour'] as num?)?.toInt() ?? 10,
        closeHour: (json['close_hour'] as num?)?.toInt() ?? 22,
        services: (json['services'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}
