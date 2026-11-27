import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../MODELS/style_model.dart' show Gender;
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/fit_provider.dart';
import '../PROVIDERS/stylist_provider.dart';
import '../PROVIDERS/wardrobe_provider.dart';
import '../SERVICES/stylist_engine.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';
import '../WIDGETS/studio_widgets.dart';
import 'wardrobe_page.dart';

const List<String> _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// Cuaca yang dipilih manual bila data cuaca tidak tersedia.
enum _ManualWeather {
  auto('Otomatis'),
  sunny('Cerah'),
  rain('Hujan'),
  hot('Panas'),
  cold('Dingin / AC');

  const _ManualWeather(this.label);

  final String label;
}

/// AI Stylist: outfit sesuai cuaca (Open-Meteo) dan agenda pengguna.
///
/// "AI" di sini berupa mesin aturan (bukan model bahasa): acara menentukan
/// keformalan, cuaca menentukan bahan, lalu katalog diurutkan dengan skor.
class StylistPage extends StatefulWidget {
  const StylistPage({super.key});

  @override
  State<StylistPage> createState() => _StylistPageState();
}

class _StylistPageState extends State<StylistPage> {
  late DateTime _day;
  _ManualWeather _manual = _ManualWeather.auto;
  DressCode? _dressOverride;
  Gender? _gender;
  bool _genderInit = false;

  String? _outfitKey;
  StylistOutfit? _outfit;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final stylist = context.read<StylistProvider>();
      if (stylist.forecast.isEmpty) stylist.loadWeather();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_genderInit) {
      _genderInit = true;
      final fit = context.read<FitProvider>();
      if (fit.hasSavedProfile) _gender = fit.profile.gender;
    }
  }

  List<DateTime> get _days {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
  }

  String _dayLabel(DateTime d, int index) {
    if (index == 0) return 'Hari ini';
    if (index == 1) return 'Besok';
    return '${_weekdays[d.weekday - 1]} ${d.day}';
  }

  /// Cuaca efektif: manual bila dipilih, kalau tidak dari ramalan.
  ({bool rainy, double? tMax, String summary}) _effectiveWeather(WeatherDay? w) {
    switch (_manual) {
      case _ManualWeather.sunny:
        return (rainy: false, tMax: 30.0, summary: 'Cerah (manual)');
      case _ManualWeather.rain:
        return (rainy: true, tMax: 27.0, summary: 'Hujan (manual)');
      case _ManualWeather.hot:
        return (rainy: false, tMax: 34.0, summary: 'Panas (manual)');
      case _ManualWeather.cold:
        return (rainy: false, tMax: 21.0, summary: 'Dingin / ber-AC (manual)');
      case _ManualWeather.auto:
        if (w == null) return (rainy: false, tMax: null, summary: 'Cuaca belum tersedia');
        return (
          rainy: w.isRainy,
          tMax: w.tMax,
          summary: '${w.description}, ${w.tMin.round()}–${w.tMax.round()}°C',
        );
    }
  }

  StylistOutfit _computeOutfit({
    required List<Product> catalog,
    required DressCode dress,
    required bool rainy,
    required double? tMax,
  }) {
    final key = '${_day.millisecondsSinceEpoch}|${dress.name}|$rainy|'
        '${tMax?.round()}|${_gender?.name}|${identityHashCode(catalog)}';
    if (key != _outfitKey || _outfit == null) {
      _outfitKey = key;
      _outfit = buildOutfit(
        catalog: catalog,
        gender: _gender,
        dress: dress,
        rainy: rainy,
        tMax: tMax,
      );
    }
    return _outfit!;
  }

  Future<void> _changeCity() async {
    final stylist = context.read<StylistProvider>();
    final place = await showDialog<GeoPlace>(
      context: context,
      builder: (_) => _CitySearchDialog(search: stylist.searchCity),
    );
    if (place != null) await stylist.setPlace(place);
  }

  void _addEvent() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddEventSheet(day: _day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stylist = context.watch<StylistProvider>();
    final catalog = context.watch<AppState>().allProducts;
    final wardrobe = context.watch<WardrobeProvider>().items;

    final weather = stylist.weatherOn(_day);
    final eff = _effectiveWeather(weather);
    final events = stylist.eventsOn(_day);
    final agendaDress = stylist.dominantDressCode(_day);
    final dress = _dressOverride ?? agendaDress ?? DressCode.casual;

    final outfit = _computeOutfit(
      catalog: catalog,
      dress: dress,
      rainy: eff.rainy,
      tMax: eff.tMax,
    );
    final ideas = wardrobeIdeas(picks: outfit.picks, wardrobe: wardrobe);

    return Scaffold(
      appBar: AppBar(title: const Text('AI STYLIST')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Lokasi
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.place_outlined, size: 18, color: AppColors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    stylist.place.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(onPressed: _changeCity, child: const Text('Ganti kota')),
              ],
            ),
          ),
          // Pilih hari
          SizedBox(
            height: 50,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: 7,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = _days[i];
                return ChoiceChip(
                  label: Text(_dayLabel(d, i)),
                  selected: d == _day,
                  onSelected: (_) => setState(() {
                    _day = d;
                    _dressOverride = null;
                  }),
                );
              },
            ),
          ),
          // Cuaca
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration(radius: 16, border: true, shadow: false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (stylist.loading)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    else
                      Icon(
                        _manual == _ManualWeather.auto && weather != null
                            ? weather.icon
                            : Icons.thermostat,
                        size: 32,
                        color: AppColors.red,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eff.summary,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_manual == _ManualWeather.auto && weather != null)
                            Text(
                              'Peluang hujan ${weather.precipProbability}%',
                              style: const TextStyle(color: AppColors.muted),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Muat ulang cuaca',
                      onPressed: stylist.loading ? null : stylist.loadWeather,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                if (stylist.error != null && _manual == _ManualWeather.auto)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      stylist.error!,
                      style: const TextStyle(color: AppColors.red, fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final m in _ManualWeather.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: _manual == m,
                        onSelected: (_) => setState(() => _manual = m),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Agenda
          StudioSectionTitle(
            'Agenda hari ini',
            trailing: TextButton.icon(
              onPressed: _addEvent,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah'),
            ),
          ),
          if (events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Belum ada agenda. Tambahkan meeting atau acara agar saran '
                'outfit menyesuaikan.',
                style: TextStyle(color: AppColors.muted, height: 1.4),
              ),
            ),
          for (final e in events)
            ListTile(
              dense: true,
              leading: Icon(e.dressCode.icon, color: AppColors.red),
              title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${e.start.hour.toString().padLeft(2, '0')}:'
                '${e.start.minute.toString().padLeft(2, '0')} • ${e.dressCode.label}'
                '${e.place.isEmpty ? '' : ' • ${e.place}'}',
              ),
              trailing: IconButton(
                tooltip: 'Hapus',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => context.read<StylistProvider>().removeEvent(e.id),
              ),
            ),
          // Gaya & target
          StudioSectionTitle('Gaya hari ini: ${dress.label}'),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final d in DressCode.values.reversed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(d.icon, size: 16),
                      label: Text(d.label),
                      selected: dress == d,
                      onSelected: (_) => setState(() => _dressOverride = d),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                const Text('Untuk: ', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<Gender?>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment<Gender?>(value: null, label: Text('Semua')),
                      ButtonSegment<Gender?>(value: Gender.female, label: Text('Wanita')),
                      ButtonSegment<Gender?>(value: Gender.male, label: Text('Pria')),
                    ],
                    selected: {_gender},
                    onSelectionChanged: (s) => setState(() => _gender = s.first),
                  ),
                ),
              ],
            ),
          ),
          // Hasil
          const StudioSectionTitle('Rekomendasi outfit'),
          if (outfit.picks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Belum ada produk yang cocok di katalog saat ini.'),
            )
          else
            SizedBox(
              height: 300,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: outfit.picks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final pick = outfit.picks[i];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          pick.slot.label.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.red,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      Expanded(
                        child: MiniProductTile(
                          product: pick.match.product,
                          color: pick.match.color,
                          caption: pick.why,
                          width: 150,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (outfit.tips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tip in outfit.tips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.star),
                          const SizedBox(width: 6),
                          Expanded(child: Text(tip, style: const TextStyle(height: 1.35))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          // Dari lemari
          const StudioSectionTitle('Padukan dengan lemarimu'),
          if (wardrobe.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tambahkan pakaianmu ke Lemari Digital untuk melihat '
                      'padanan dengan outfit ini.',
                      style: TextStyle(color: AppColors.muted, height: 1.4),
                    ),
                  ),
                  TextButton(
                    onPressed: () => pushPage(context, const WardrobePage()),
                    child: const Text('Buka lemari'),
                  ),
                ],
              ),
            )
          else if (ideas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Belum ada pakaian di lemarimu yang warnanya serasi dengan outfit ini.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            for (final idea in ideas)
              ListTile(
                leading: SizedBox(
                  width: 48,
                  height: 48,
                  child: StoredImage(idea.item.photo, fit: BoxFit.contain),
                ),
                title: Text(idea.item.name),
                subtitle: Text(
                  'Serasi dengan ${idea.partner.slot.label.toLowerCase()} '
                  '${idea.partner.match.colorName.toLowerCase()} • '
                  '${idea.harmony.kind.description}',
                ),
                onTap: () => pushPage(context, WardrobeItemPage(itemId: idea.item.id)),
              ),
        ],
      ),
    );
  }
}

class _CitySearchDialog extends StatefulWidget {
  const _CitySearchDialog({required this.search});

  final Future<List<GeoPlace>> Function(String) search;

  @override
  State<_CitySearchDialog> createState() => _CitySearchDialogState();
}

class _CitySearchDialogState extends State<_CitySearchDialog> {
  final TextEditingController _controller = TextEditingController();
  List<GeoPlace> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.search(_controller.text);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
        if (r.isEmpty) _error = 'Kota tidak ditemukan.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Pencarian gagal. Periksa koneksi internet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cari kota'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: 'Contoh: Palembang',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _run,
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: AppColors.red)),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in _results)
                    ListTile(
                      dense: true,
                      title: Text(p.name),
                      subtitle: Text(
                        [if (p.admin.isNotEmpty) p.admin, p.country].join(', '),
                      ),
                      onTap: () => Navigator.of(context).pop(p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}

class _AddEventSheet extends StatefulWidget {
  const _AddEventSheet({required this.day});

  final DateTime day;

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _place = TextEditingController();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  DressCode _dress = DressCode.formal;

  @override
  void dispose() {
    _title.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  void _save() {
    final start = DateTime(
      widget.day.year,
      widget.day.month,
      widget.day.day,
      _time.hour,
      _time.minute,
    );
    context.read<StylistProvider>().addEvent(
          title: _title.text,
          start: start,
          dressCode: _dress,
          place: _place.text,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tambah agenda',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Nama acara (mis. Meeting klien)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _place,
              decoration: const InputDecoration(
                labelText: 'Tempat (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text('Jam ${_time.format(context)}'),
            ),
            const SizedBox(height: 12),
            const Text('Dress code', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final d in DressCode.values.reversed)
                  ChoiceChip(
                    avatar: Icon(d.icon, size: 16),
                    label: Text(d.label),
                    selected: _dress == d,
                    onSelected: (_) => setState(() => _dress = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
              onPressed: _save,
              child: const Text('SIMPAN AGENDA'),
            ),
          ],
        ),
      ),
    );
  }
}
