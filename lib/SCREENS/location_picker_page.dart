import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../MODELS/picked_location.dart';
import '../SERVICES/geo_service.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/external_link.dart';

/// Pusat peta awal (Jakarta) bila belum ada lokasi.
const LatLng kDefaultMapCenter = LatLng(-6.2088, 106.8456);

/// Memilih lokasi alamat lewat peta. Geser peta sampai pin merah tepat di
/// lokasi yang diinginkan, atau cari alamat / pakai GPS. Mengembalikan
/// [PickedLocation] lewat `Navigator.pop`.
class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, this.initial, this.geo});

  final PickedLocation? initial;

  /// Disediakan agar bisa diganti saat pengujian.
  final GeoService? geo;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _map = MapController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  late final GeoService _geo = widget.geo ?? GeoService();

  late LatLng _center;
  List<PlaceResult> _results = const [];
  bool _searching = false;
  bool _locating = false;
  bool _resolving = false;
  String? _notice;
  Timer? _debounce;
  int _resolveToken = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _center = initial == null
        ? kDefaultMapCenter
        : LatLng(initial.lat, initial.lng);
    _addressController.text = initial?.address ?? '';
    if (initial == null) {
      // Coba langsung ke posisi pengguna; bila ditolak tetap di Jakarta.
      WidgetsBinding.instance.addPostFrameCallback((_) => _useGps(silent: true));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _addressController.dispose();
    if (widget.geo == null) _geo.dispose();
    super.dispose();
  }

  void _onMove(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (!hasGesture) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _resolveAddress);
    setState(() => _results = const []);
  }

  Future<void> _resolveAddress() async {
    final token = ++_resolveToken;
    setState(() => _resolving = true);
    final text = await _geo.reverse(_center.latitude, _center.longitude);
    if (!mounted || token != _resolveToken) return;
    setState(() {
      _resolving = false;
      if (text != null) {
        _addressController.text = text;
        _notice = null;
      } else {
        _notice = 'Alamat tidak bisa diambil (offline?). Ketik alamat manual.';
      }
    });
  }

  void _moveTo(LatLng point, {double zoom = 17}) {
    _center = point;
    _map.move(point, zoom);
    _resolveAddress();
  }

  Future<void> _search() async {
    final text = _searchController.text.trim();
    if (text.length < 3) {
      setState(() => _notice = 'Ketik minimal 3 huruf untuk mencari.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _notice = null;
    });
    final found = await _geo.search(text);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = found;
      if (found.isEmpty) _notice = 'Alamat tidak ditemukan. Coba kata kunci lain.';
    });
  }

  Future<void> _useGps({bool silent = false}) async {
    setState(() => _locating = true);
    final result = await _geo.currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (!result.ok) {
      if (!silent) setState(() => _notice = result.error);
      return;
    }
    _moveTo(LatLng(result.lat!, result.lng!));
  }

  void _confirm() {
    final text = _addressController.text.trim();
    if (text.isEmpty) {
      setState(() => _notice = 'Alamat masih kosong. Tunggu sebentar atau ketik manual.');
      return;
    }
    Navigator.of(context).pop(PickedLocation(
      address: text,
      lat: _center.latitude,
      lng: _center.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PILIH LOKASI')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: widget.initial == null ? 12 : 17,
                    minZoom: 4,
                    maxZoom: 19,
                    onPositionChanged: _onMove,
                    onTap: (_, point) => _moveTo(point, zoom: _map.camera.zoom),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.project_uts',
                    ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                // Pin tetap di tengah; yang digeser adalah petanya.
                const IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 40),
                      child: Icon(Icons.location_on,
                          size: 48, color: AppColors.red),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: _SearchBox(
                    controller: _searchController,
                    searching: _searching,
                    onSearch: _search,
                    results: _results,
                    onPick: (place) {
                      setState(() => _results = const []);
                      _searchController.text = place.title;
                      _addressController.text = place.address;
                      _moveTo(LatLng(place.lat, place.lng));
                      _addressController.text = place.address;
                    },
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'gps',
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.ink,
                    tooltip: 'Lokasi saya',
                    onPressed: _locating ? null : _useGps,
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _addressController,
                        maxLines: 3,
                        minLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Alamat (bisa diedit)',
                          prefixIcon: const Icon(Icons.location_on_outlined),
                          suffixIcon: _resolving
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Koordinat: ${_center.latitude.toStringAsFixed(5)}, '
                              '${_center.longitude.toStringAsFixed(5)}',
                              style: const TextStyle(
                                  color: AppColors.muted, fontSize: 12),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => openExternalUrl(
                              context,
                              'https://www.google.com/maps/search/?api=1&query='
                              '${_center.latitude},${_center.longitude}',
                            ),
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: const Text('Google Maps'),
                          ),
                        ],
                      ),
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _notice!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 12),
                          ),
                        ),
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _confirm,
                          child: const Text(
                            'GUNAKAN LOKASI INI',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.searching,
    required this.onSearch,
    required this.results,
    required this.onPick,
  });

  final TextEditingController controller;
  final bool searching;
  final VoidCallback onSearch;
  final List<PlaceResult> results;
  final ValueChanged<PlaceResult> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(10),
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: 'Cari alamat, jalan, atau nama tempat',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Cari',
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: onSearch,
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final place = results[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(place.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(place.address,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => onPick(place),
                );
              },
            ),
          ),
      ],
    );
  }
}
