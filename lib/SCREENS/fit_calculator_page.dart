import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../MODELS/studio_models.dart';
import '../MODELS/style_model.dart' show Gender;
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/fit_provider.dart';
import '../PROVIDERS/style_provider.dart';
import '../SERVICES/fit_engine.dart';
import '../UTILS/app_theme.dart';
import '../WIDGETS/app_network_image.dart';
import '../WIDGETS/studio_widgets.dart';

/// Kalkulator ukuran: tinggi, berat, dan gaya favorit -> ukuran per produk.
///
/// Bila dibuka dari detail produk, tombol "Pakai ukuran ini" mengembalikan
/// ukuran terpilih lewat `Navigator.pop`.
class FitCalculatorPage extends StatefulWidget {
  const FitCalculatorPage({super.key, this.product});

  final Product? product;

  @override
  State<FitCalculatorPage> createState() => _FitCalculatorPageState();
}

class _FitCalculatorPageState extends State<FitCalculatorPage> {
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late FitProfile _profile;
  Product? _product;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    final fit = context.read<FitProvider>();
    var profile = fit.profile;
    if (!fit.hasSavedProfile) {
      // Awali dari profil gaya (Stylist) bila pengguna sudah mengisinya.
      final body = context.read<StyleProvider>().profile;
      if (body != null) {
        profile = profile.copyWith(
          gender: body.gender,
          heightCm: body.heightCm,
          weightKg: body.weightKg,
        );
      }
    }
    _profile = profile;
    _height = TextEditingController(text: profile.heightCm.round().toString());
    _weight = TextEditingController(text: profile.weightKg.round().toString());
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _apply() {
    final h = double.tryParse(_height.text.replaceAll(',', '.'));
    final w = double.tryParse(_weight.text.replaceAll(',', '.'));
    var next = _profile;
    if (h != null && h >= 100 && h <= 230) next = next.copyWith(heightCm: h);
    if (w != null && w >= 25 && w <= 250) next = next.copyWith(weightKg: w);
    setState(() => _profile = next);
    context.read<FitProvider>().update(next);
  }

  void _setProfile(FitProfile next) {
    setState(() => _profile = next);
    context.read<FitProvider>().update(next);
  }

  Future<void> _pickProduct() async {
    final catalog = context.read<AppState>().allProducts;
    final p = await pickCatalogProduct(
      context,
      catalog,
      title: 'Pilih produk',
      filter: (p) => p.category != 'Accessories',
    );
    if (p != null) setState(() => _product = p);
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final result = product == null ? null : recommendSize(_profile, product);

    return Scaffold(
      appBar: AppBar(title: const Text('KALKULATOR UKURAN')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Data tubuh', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 10),
                  SegmentedButton<Gender>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: Gender.female, label: Text('Wanita')),
                      ButtonSegment(value: Gender.male, label: Text('Pria')),
                    ],
                    selected: {_profile.gender},
                    onSelectionChanged: (s) => _setProfile(_profile.copyWith(gender: s.first)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _height,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _apply(),
                          decoration: const InputDecoration(
                            labelText: 'Tinggi (cm)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _weight,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => _apply(),
                          decoration: const InputDecoration(
                            labelText: 'Berat (kg)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Suka pakaian yang...', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  SegmentedButton<FitPreference>(
                    showSelectedIcon: false,
                    segments: [
                      for (final p in FitPreference.values)
                        ButtonSegment(value: p, label: Text(p.label)),
                    ],
                    selected: {_profile.preference},
                    onSelectionChanged: (s) =>
                        _setProfile(_profile.copyWith(preference: s.first)),
                  ),
                  const SizedBox(height: 20),
                  const Text('Produk', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 8),
                  if (product == null)
                    OutlinedButton.icon(
                      onPressed: _pickProduct,
                      icon: const Icon(Icons.search),
                      label: const Text('Pilih produk untuk dihitung'),
                    )
                  else
                    _ProductHeader(product: product, onChange: _pickProduct),
                  if (result != null) ...[
                    const SizedBox(height: 16),
                    _ResultCard(
                      product: product!,
                      result: result,
                      preference: _profile.preference,
                      onUse: widget.product == null
                          ? null
                          : (size) => Navigator.of(context).pop<String>(size),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Ini perkiraan dari tinggi, berat, dan potongan produk. '
                    'Bandingkan dengan panduan ukuran di detail produk.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.product, required this.onChange});

  final Product product;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: cardDecoration(radius: 12, border: true, shadow: false),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 68,
            child: AppNetworkImage(product.image, borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(product.formattedPrice, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
          TextButton(onPressed: onChange, child: const Text('Ganti')),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.product,
    required this.result,
    required this.preference,
    this.onUse,
  });

  final Product product;
  final FitResult result;
  final FitPreference preference;
  final ValueChanged<String>? onUse;

  @override
  Widget build(BuildContext context) {
    if (!result.supported) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: cardDecoration(radius: 14, border: true, shadow: false),
        child: Text(result.summary, style: const TextStyle(height: 1.4)),
      );
    }
    final size = result.size!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(radius: 14, border: true, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  size,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ukuran untukmu', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      'Potongan ${result.cut.label}: ${result.cut.description}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                    if (result.alternative != null)
                      Text(
                        'Alternatif: ${result.alternative}',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(result.summary, style: const TextStyle(height: 1.4)),
          for (final n in result.notes)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(n, style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35)),
            ),
          if (result.verdicts.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Perkiraan jatuhnya tiap ukuran',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in result.verdicts.entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: e.key == size ? AppColors.redSoft : Colors.white,
                      border: Border.all(
                        color: e.key == size ? AppColors.red : AppColors.line,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(e.key, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(e.value.label,
                            style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (onUse != null) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
              ),
              onPressed: () => onUse!(size),
              child: Text('PAKAI UKURAN $size'),
            ),
          ],
        ],
      ),
    );
  }
}
