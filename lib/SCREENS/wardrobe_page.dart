import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../MODELS/style_model.dart' show Gender;
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/fit_provider.dart';
import '../PROVIDERS/wardrobe_provider.dart';
import '../SERVICES/color_utils.dart';
import '../SERVICES/image_tools.dart';
import '../SERVICES/outfit_engine.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/studio_widgets.dart';
import '../WIDGETS/ui_kit.dart';
import 'camera_capture_page.dart';
import 'try_on_page.dart';

/// Memilih sumber foto (kamera atau galeri) lalu membuka form tambah pakaian.
Future<void> startAddToWardrobe(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'Tambah pakaian',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Foto dengan kamera'),
            subtitle: const Text('Kamera belakang HP atau webcam laptop'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Pilih dari galeri / berkas'),
            onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;

  Uint8List? bytes;
  if (source == ImageSource.camera) {
    bytes = await pushPage<Uint8List>(
      context,
      const CameraCapturePage(
        title: 'Foto pakaian',
        hint: 'Letakkan pakaian di permukaan polos (kasur atau lantai) '
            'dengan cahaya terang agar latar mudah dipisahkan.',
        showFaceGuide: false,
        preferFront: false,
        useTimer: false,
      ),
    );
  } else {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 92,
      );
      bytes = await picked?.readAsBytes();
    } catch (_) {
      if (context.mounted) {
        showAppToast(
          context,
          'Foto tidak bisa dibuka.',
          color: AppColors.red,
          icon: Icons.error_outline,
        );
      }
    }
  }
  if (bytes == null || !context.mounted) return;
  await pushPage(context, WardrobeAddPage(bytes: bytes));
}

/// Daftar pakaian di lemari digital.
class WardrobePage extends StatefulWidget {
  const WardrobePage({super.key});

  @override
  State<WardrobePage> createState() => _WardrobePageState();
}

class _WardrobePageState extends State<WardrobePage> {
  ClothingSlot? _filter;

  @override
  Widget build(BuildContext context) {
    final all = context.watch<WardrobeProvider>().items;
    final items =
        _filter == null ? all : all.where((i) => i.slot == _filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LEMARI DIGITAL'),
        actions: [
          IconButton(
            tooltip: 'Tambah pakaian',
            onPressed: () => startAddToWardrobe(context),
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
        ],
      ),
      floatingActionButton: all.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              onPressed: () => startAddToWardrobe(context),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.checkroom,
              title: 'Lemarimu masih kosong',
              message: 'Foto pakaian yang sudah kamu punya. Aplikasi akan '
                  'menyarankan produk baru yang cocok dipadukan dengannya.',
              actionLabel: 'Tambah pakaian pertama',
              onAction: () => startAddToWardrobe(context),
            )
          : Column(
              children: [
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('Semua (${all.length})'),
                          selected: _filter == null,
                          onSelected: (_) => setState(() => _filter = null),
                        ),
                      ),
                      for (final slot in ClothingSlot.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${slot.label} (${all.where((i) => i.slot == slot).length})',
                            ),
                            selected: _filter == slot,
                            onSelected: (_) => setState(() => _filter = slot),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(child: Text('Belum ada pakaian di kategori ini'))
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: items.length,
                          itemBuilder: (context, i) => _WardrobeTile(item: items[i]),
                        ),
                ),
              ],
            ),
    );
  }
}

class _WardrobeTile extends StatelessWidget {
  const _WardrobeTile({required this.item});

  final WardrobeItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => pushPage(context, WardrobeItemPage(itemId: item.id)),
      child: Container(
        decoration: cardDecoration(radius: 14, border: true, shadow: false),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                color: const Color(0xFFF1F1F3),
                padding: const EdgeInsets.all(8),
                child: StoredImage(item.photo, fit: BoxFit.contain),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      ColorDot(item.color, size: 11),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          '${item.slot.label} • ${colorNameId(item.color)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tambah pakaian
// -----------------------------------------------------------------------------

/// Memproses foto (hapus latar, deteksi warna) lalu menyimpan ke lemari.
class WardrobeAddPage extends StatefulWidget {
  const WardrobeAddPage({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<WardrobeAddPage> createState() => _WardrobeAddPageState();
}

class _WardrobeAddPageState extends State<WardrobeAddPage> {
  final TextEditingController _name = TextEditingController();
  CutoutResult? _result;
  bool _processing = true;
  bool _removeBackground = true;
  bool _saving = false;
  String? _error;
  ClothingSlot _slot = ClothingSlot.top;
  Color _color = const Color(0xFF9E9E9E);
  bool _nameEdited = false;

  @override
  void initState() {
    super.initState();
    _process(initial: true);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _process({bool initial = false}) async {
    if (!initial) {
      setState(() {
        _processing = true;
        _error = null;
      });
    }
    try {
      final result = await cutoutGarment(
        widget.bytes,
        removeBackground: _removeBackground,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _color = Color(result.dominantArgb);
        _processing = false;
      });
      _suggestName();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _error = 'Foto tidak bisa diproses. Coba foto lain.';
      });
    }
  }

  void _suggestName() {
    if (_nameEdited) return;
    _name.text = '${_slot.label} ${colorNameId(_color).toLowerCase()}';
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    try {
      await context.read<WardrobeProvider>().addItem(
            name: _name.text,
            slot: _slot,
            colorArgb: _color.toARGB32(),
            png: result.png,
          );
      if (!mounted) return;
      showAppToast(context, 'Tersimpan di lemari digital');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(
        context,
        'Gagal menyimpan foto.',
        color: AppColors.red,
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('TAMBAH PAKAIAN')),
      body: _processing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Memisahkan pakaian dari latar...'),
                ],
              ),
            )
          : _error != null
              ? EmptyState(
                  icon: Icons.error_outline,
                  title: 'Gagal memproses foto',
                  message: _error,
                  actionLabel: 'Coba lagi',
                  onAction: () => _process(),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 300,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F1F3),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: result == null
                                  ? null
                                  : Image.memory(result.png, fit: BoxFit.contain),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _removeBackground,
                              title: const Text('Hapus latar otomatis'),
                              subtitle: Text(
                                result != null && !result.backgroundRemoved && _removeBackground
                                    ? 'Latar tidak bisa dipisahkan. Pakai latar polos '
                                        'dan cahaya merata.'
                                    : 'Cocok untuk foto di latar polos.',
                              ),
                              onChanged: (v) {
                                setState(() => _removeBackground = v);
                                _process();
                              },
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _name,
                              onChanged: (_) => _nameEdited = true,
                              decoration: const InputDecoration(
                                labelText: 'Nama pakaian',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Jenis pakaian',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final slot in ClothingSlot.values)
                                  ChoiceChip(
                                    avatar: Icon(slot.icon, size: 16),
                                    label: Text(slot.label),
                                    selected: _slot == slot,
                                    onSelected: (_) {
                                      setState(() => _slot = slot);
                                      _suggestName();
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Warna: ${colorNameId(_color)}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 8),
                            _ColorChooser(
                              selected: _color,
                              detected: result == null ? null : Color(result.dominantArgb),
                              onChanged: (c) {
                                setState(() => _color = c);
                                _suggestName();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _processing || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Menyimpan...' : 'SIMPAN KE LEMARI'),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ColorChooser extends StatelessWidget {
  const _ColorChooser({
    required this.selected,
    required this.detected,
    required this.onChanged,
  });

  final Color selected;
  final Color? detected;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <Color>[
      if (detected != null) detected!,
      ...kWardrobePalette,
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < options.length; i++)
          GestureDetector(
            onTap: () => onChanged(options[i]),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: options[i],
                shape: BoxShape.circle,
                border: Border.all(
                  color: options[i].toARGB32() == selected.toARGB32()
                      ? AppColors.red
                      : Colors.black26,
                  width: options[i].toARGB32() == selected.toARGB32() ? 3 : 1,
                ),
              ),
              child: i == 0 && detected != null
                  ? const Icon(Icons.auto_fix_high, size: 16, color: Colors.white70)
                  : null,
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Detail pakaian + padu padan
// -----------------------------------------------------------------------------

class WardrobeItemPage extends StatefulWidget {
  const WardrobeItemPage({super.key, required this.itemId});

  final String itemId;

  @override
  State<WardrobeItemPage> createState() => _WardrobeItemPageState();
}

class _WardrobeItemPageState extends State<WardrobeItemPage> {
  /// `null` = semua (Pria + Wanita + Unisex).
  Gender? _gender;
  bool _genderInit = false;

  // Cache hasil padu padan supaya tidak dihitung ulang tiap rebuild.
  String? _matchKey;
  Map<ClothingSlot, List<OutfitMatch>> _matches = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_genderInit) {
      _genderInit = true;
      final fit = context.read<FitProvider>();
      if (fit.hasSavedProfile) _gender = fit.profile.gender;
    }
  }

  Map<ClothingSlot, List<OutfitMatch>> _compute(
    WardrobeItem item,
    List<Product> catalog,
  ) {
    final key = '${item.id}|${item.colorArgb}|${item.slot.name}|'
        '${_gender?.name}|${identityHashCode(catalog)}';
    if (key != _matchKey) {
      _matchKey = key;
      _matches = mixAndMatch(anchor: item, catalog: catalog, gender: _gender);
    }
    return _matches;
  }

  Future<void> _rename(WardrobeItem item) async {
    final controller = TextEditingController(text: item.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ubah nama'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    context.read<WardrobeProvider>().updateItem(item.id, name: name);
  }

  Future<void> _delete(WardrobeItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus dari lemari?'),
        content: Text('"${item.name}" akan dihapus dari lemari digitalmu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    StoredImage.evict(item.photo);
    await context.read<WardrobeProvider>().removeItem(item.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final item = context.watch<WardrobeProvider>().byId(widget.itemId);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PAKAIAN')),
        body: const EmptyState(
          icon: Icons.checkroom,
          title: 'Pakaian tidak ditemukan',
        ),
      );
    }
    final catalog = context.watch<AppState>().allProducts;
    final matches = _compute(item, catalog);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Ubah nama',
            onPressed: () => _rename(item),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Hapus',
            onPressed: () => _delete(item),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            height: 240,
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1F3),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(12),
            child: StoredImage(item.photo, fit: BoxFit.contain),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ColorDot(item.color, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${item.slot.label} • ${colorNameId(item.color)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.red,
                    side: const BorderSide(color: AppColors.red),
                  ),
                  onPressed: () => pushPage(context, TryOnPage(wardrobeItem: item)),
                  icon: const Icon(Icons.view_in_ar_outlined, size: 18),
                  label: const Text('Coba di kamera'),
                ),
              ],
            ),
          ),
          StudioSectionTitle(
            'Padu padan dengan produk baru',
            trailing: SegmentedButton<Gender?>(
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
          if (matches.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Belum ada produk yang cocok di katalog saat ini.',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          for (final entry in matches.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '${entry.key.label} yang serasi',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.muted,
                ),
              ),
            ),
            SizedBox(
              height: 285,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: entry.value.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final m = entry.value[i];
                  return MiniProductTile(
                    product: m.product,
                    color: m.color,
                    caption: m.reason,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
