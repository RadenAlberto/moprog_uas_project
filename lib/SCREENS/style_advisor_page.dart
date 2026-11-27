import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../MODELS/style_model.dart';
import '../PROVIDERS/style_provider.dart';
import '../SERVICES/face_analyzer.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/nav.dart';
import '../WIDGETS/face_shape_icon.dart';
import '../WIDGETS/server_status.dart';
import '../WIDGETS/ui_kit.dart';
import 'camera_capture_page.dart';
import 'style_result_page.dart';

/// Pilihan batas harga per produk.
const List<(double?, String)> _kBudgets = [
  (null, 'Tanpa batas'),
  (200000.0, 'Maks. Rp200 rb'),
  (400000.0, 'Maks. Rp400 rb'),
  (700000.0, 'Maks. Rp700 rb'),
];

/// Wizard UNIQLO PLUS Stylist: data diri -> foto selfie -> konfirmasi hasil
/// -> rekomendasi produk.
class StyleAdvisorPage extends StatefulWidget {
  const StyleAdvisorPage({super.key});

  @override
  State<StyleAdvisorPage> createState() => _StyleAdvisorPageState();
}

class _StyleAdvisorPageState extends State<StyleAdvisorPage> {
  static const int _lastStep = 3;

  int _step = 0;
  int _minStep = 0;

  Gender? _gender;
  final TextEditingController _heightCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();
  Set<StyleGoal> _goals = {StyleGoal.casual};
  int _budgetIndex = 0;
  String? _dataError;

  Uint8List? _photo;
  bool _analyzing = false;
  FaceAnalysisResult? _analysis;
  bool _fromPhoto = false;

  FaceShape _face = FaceShape.oval;
  Undertone _undertone = Undertone.neutral;
  SkinDepth _depth = SkinDepth.medium;
  int? _skinColor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = context.read<StyleProvider>().profile;
    if (existing != null) {
      _gender = existing.gender;
      _heightCtrl.text = _fmt(existing.heightCm);
      _weightCtrl.text = _fmt(existing.weightKg);
      _goals = {...existing.goals};
      for (var i = 0; i < _kBudgets.length; i++) {
        if (_kBudgets[i].$1 == existing.maxPrice) _budgetIndex = i;
      }
      _face = existing.faceShape ?? FaceShape.oval;
      _undertone = existing.undertone ?? Undertone.neutral;
      _depth = existing.depth ?? SkinDepth.medium;
      _skinColor = existing.skinColorArgb;
      _step = 1;
      _minStep = 1;
    }
  }

  @override
  void dispose() {
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  static String _fmt(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1);

  static double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  // ---------------------------------------------------------------------------
  // Aksi
  // ---------------------------------------------------------------------------

  bool _validateData() {
    final height = _parse(_heightCtrl.text);
    final weight = _parse(_weightCtrl.text);
    String? error;
    if (_gender == null) {
      error = 'Pilih jenis kelamin terlebih dahulu.';
    } else if (height == null || height < 120 || height > 220) {
      error = 'Tinggi badan harus antara 120 dan 220 cm.';
    } else if (weight == null || weight < 30 || weight > 200) {
      error = 'Berat badan harus antara 30 dan 200 kg.';
    }
    setState(() => _dataError = error);
    return error == null;
  }

  Future<void> _takePhoto() async {
    final bytes = await pushPage<Uint8List>(context, const CameraCapturePage());
    if (bytes == null || !mounted) return;
    setState(() {
      _photo = bytes;
      _analyzing = true;
      _analysis = null;
    });
    final result = await const FaceAnalyzer().analyze(bytes);
    if (!mounted) return;
    setState(() {
      _analyzing = false;
      _analysis = result;
      if (result.ok) {
        _face = result.faceShape ?? _face;
        _undertone = result.undertone ?? _undertone;
        _depth = result.depth ?? _depth;
        _skinColor = result.skinColorArgb;
        _fromPhoto = true;
      }
    });
  }

  void _skipPhoto() {
    setState(() {
      _fromPhoto = false;
      _photo = null;
      _analysis = null;
      _skinColor = null;
      _step = 3;
    });
  }

  int _defaultSkin(SkinDepth depth) {
    switch (depth) {
      case SkinDepth.light:
        return 0xFFF1D1B5;
      case SkinDepth.medium:
        return 0xFFC99B76;
      case SkinDepth.deep:
        return 0xFF7A5238;
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    final gender = _gender;
    final height = _parse(_heightCtrl.text);
    final weight = _parse(_weightCtrl.text);
    if (gender == null || height == null || weight == null) {
      setState(() => _step = 1);
      return;
    }
    setState(() => _saving = true);
    final profile = BodyProfile(
      gender: gender,
      heightCm: height,
      weightKg: weight,
      faceShape: _face,
      undertone: _undertone,
      depth: _depth,
      skinColorArgb: _skinColor ?? _defaultSkin(_depth),
      goals: _goals.isEmpty ? {StyleGoal.casual} : _goals,
      maxPrice: _kBudgets[_budgetIndex].$1,
      analyzedAt: DateTime.now(),
    );
    await context.read<StyleProvider>().saveProfile(profile);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const StyleResultPage()),
    );
  }

  void _next() {
    if (_step == 1 && !_validateData()) return;
    if (_step >= _lastStep) {
      _finish();
      return;
    }
    setState(() => _step++);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step <= _minStep,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('UNIQLO PLUS Stylist'),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 10),
              child: Center(child: ServerStatusChip()),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (_step + 1) / (_lastStep + 1),
                minHeight: 3,
                backgroundColor: AppColors.line,
                color: AppColors.red,
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: KeyedSubtree(
                          key: ValueKey<int>(_step),
                          child: _buildStep(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildIntro();
      case 1:
        return _buildData();
      case 2:
        return _buildPhoto();
      default:
        return _buildConfirm();
    }
  }

  Widget _buildBottomBar() {
    final String label;
    switch (_step) {
      case 0:
        label = 'Mulai';
      case 1:
        label = 'Lanjut ke foto';
      case 2:
        label = 'Lanjut';
      default:
        label = 'Lihat rekomendasi';
    }
    final canContinue = switch (_step) {
      2 => _analysis?.ok == true && !_analyzing,
      3 => !_saving,
      _ => true,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          if (_step > _minStep) ...[
            OutlinedButton(
              onPressed: () => setState(() => _step--),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                minimumSize: const Size(52, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: canContinue ? _next : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Langkah 0: pengantar
  // ---------------------------------------------------------------------------

  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Center(child: IconBadge(icon: Icons.auto_awesome, size: 72)),
        const SizedBox(height: 18),
        const Text(
          'Bingung memilih baju yang cocok?',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.25),
        ),
        const SizedBox(height: 8),
        const Text(
          'UNIQLO PLUS Stylist membantumu menemukan pakaian yang pas, '
          'tanpa perlu paham fashion.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.45),
        ),
        const SizedBox(height: 22),
        const _IntroStep(
          icon: Icons.straighten,
          title: 'Isi tinggi & berat badan',
          text: 'Dipakai untuk memilih potongan dan ukuran yang nyaman.',
        ),
        const _IntroStep(
          icon: Icons.face_retouching_natural,
          title: 'Foto selfie',
          text: 'Aplikasi membaca bentuk wajah dan warna kulitmu untuk '
              'memilih model leher dan warna yang serasi.',
        ),
        const _IntroStep(
          icon: Icons.psychology_outlined,
          title: 'Rekomendasi yang makin pintar',
          text: 'Model machine learning belajar dari tanda suka/kurang cocok '
              'darimu dan dari tren pengguna lain.',
        ),
        const SizedBox(height: 8),
        SurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.lock_outline, size: 20, color: AppColors.success),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Privasi: foto hanya diproses di perangkatmu, tidak '
                  'disimpan, dan tidak dikirim ke server. Yang tersimpan '
                  'hanya hasil ukur (bentuk wajah, nada kulit, tinggi, berat).',
                  style: TextStyle(fontSize: 12.5, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Langkah 1: data diri
  // ---------------------------------------------------------------------------

  Widget _buildData() {
    final height = _parse(_heightCtrl.text);
    final weight = _parse(_weightCtrl.text);
    final gender = _gender;
    BodyProfile? preview;
    if (gender != null &&
        height != null &&
        weight != null &&
        height >= 120 &&
        height <= 220 &&
        weight >= 30 &&
        weight <= 200) {
      preview = BodyProfile(gender: gender, heightCm: height, weightKg: weight);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          title: 'Data dirimu',
          subtitle: 'Tinggi dan berat diisi manual karena tidak bisa diukur '
              'akurat dari foto selfie.',
        ),
        const SizedBox(height: 14),
        const _Label('Jenis kelamin'),
        Row(
          children: [
            for (final g in Gender.values) ...[
              Expanded(
                child: _SelectTile(
                  selected: _gender == g,
                  onTap: () => setState(() => _gender = g),
                  child: Text(
                    g.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (g != Gender.values.last) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                controller: _heightCtrl,
                label: 'Tinggi (cm)',
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                controller: _weightCtrl,
                label: 'Berat (kg)',
                onChanged: () => setState(() {}),
              ),
            ),
          ],
        ),
        if (preview != null) ...[
          const SizedBox(height: 10),
          Text(
            'BMI ${preview.bmi.toStringAsFixed(1)} - tubuh '
            '${preview.bodyType.label.toLowerCase()}, tinggi '
            '${preview.heightClass.label.toLowerCase()}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_dataError != null) ...[
          const SizedBox(height: 10),
          Text(
            _dataError!,
            style: const TextStyle(
              color: AppColors.redDark,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
        const SizedBox(height: 20),
        const _Label('Kebutuhan berpakaian (boleh lebih dari satu)'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final goal in StyleGoal.values)
              FilterChip(
                label: Text(goal.label),
                selected: _goals.contains(goal),
                selectedColor: AppColors.redSoft,
                checkmarkColor: AppColors.red,
                onSelected: (value) => setState(() {
                  final next = {..._goals};
                  if (value) {
                    next.add(goal);
                  } else if (next.length > 1) {
                    next.remove(goal);
                  }
                  _goals = next;
                }),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const _Label('Batas harga per produk'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _kBudgets.length; i++)
              ChoiceChip(
                label: Text(_kBudgets[i].$2),
                selected: _budgetIndex == i,
                selectedColor: AppColors.redSoft,
                onSelected: (_) => setState(() => _budgetIndex = i),
              ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Langkah 2: foto
  // ---------------------------------------------------------------------------

  Widget _buildPhoto() {
    final analysis = _analysis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(
          title: 'Foto selfie',
          subtitle: 'Hadap lurus ke kamera, cahaya merata, rambut tidak '
              'menutupi dahi, tanpa masker atau kacamata gelap.',
        ),
        const SizedBox(height: 14),
        Center(
          child: Container(
            width: 190,
            height: 240,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(110),
              border: Border.all(color: AppColors.line, width: 2),
              boxShadow: AppShadows.soft,
            ),
            clipBehavior: Clip.antiAlias,
            child: _photo == null
                ? const Icon(Icons.face, size: 84, color: AppColors.line)
                : Image.memory(
                    _photo!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.broken_image_outlined, size: 48),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        if (_analyzing)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppColors.red),
                  SizedBox(height: 10),
                  Text('Menganalisis wajah dan warna kulit...'),
                ],
              ),
            ),
          )
        else if (analysis != null && analysis.ok)
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Terdeteksi: wajah ${_face.label.toLowerCase()}, '
                    'kulit ${_depth.label.toLowerCase()} '
                    'bernada ${_undertone.label.toLowerCase()}.'
                    '${analysis.message.isEmpty ? '' : '\n${analysis.message}'}',
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          )
        else if (analysis != null)
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: AppColors.redDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    analysis.message,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _analyzing ? null : _takePhoto,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.ink,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(_photo == null ? 'Ambil foto selfie' : 'Foto ulang'),
        ),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _analyzing ? null : _skipPhoto,
            child: const Text('Lewati foto, pilih manual'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Langkah 3: konfirmasi
  // ---------------------------------------------------------------------------

  Widget _buildConfirm() {
    final analysis = _analysis;
    final skin = Color(_skinColor ?? _defaultSkin(_depth));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Periksa hasilnya',
          subtitle: _fromPhoto
              ? 'Ini hasil bacaan foto. Koreksi bila kurang tepat, karena '
                  'cahaya dan sudut foto memengaruhi hasil.'
              : 'Pilih bentuk wajah dan nada kulit yang paling mirip denganmu.',
        ),
        if (_fromPhoto && analysis != null && analysis.ok) ...[
          const SizedBox(height: 12),
          SurfaceCard(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      _photo!,
                      width: 56,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox(width: 56, height: 70),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keyakinan analisis ${(analysis.confidence * 100).round()}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: analysis.confidence,
                          minHeight: 6,
                          backgroundColor: AppColors.line,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        const _Label('Bentuk wajah'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final shape in FaceShape.values)
              SizedBox(
                width: 96,
                child: _SelectTile(
                  selected: _face == shape,
                  onTap: () => setState(() => _face = shape),
                  child: Column(
                    children: [
                      FaceShapeIcon(
                        shape: shape,
                        color: _face == shape ? AppColors.red : Colors.black54,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        shape.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _face.description,
          style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: _Label('Nada kulit')),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: skin,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final tone in Undertone.values)
              ChoiceChip(
                label: Text(tone.label),
                selected: _undertone == tone,
                selectedColor: AppColors.redSoft,
                onSelected: (_) => setState(() => _undertone = tone),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${_undertone.description} Tip: lihat urat di pergelangan tangan. '
          'Kehijauan = hangat, kebiruan = dingin, campuran = netral.',
          style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
        ),
        const SizedBox(height: 16),
        const _Label('Kecerahan kulit'),
        Wrap(
          spacing: 8,
          children: [
            for (final depth in SkinDepth.values)
              ChoiceChip(
                label: Text(depth.label),
                selected: _depth == depth,
                selectedColor: AppColors.redSoft,
                onSelected: (_) => setState(() {
                  _depth = depth;
                  if (!_fromPhoto) _skinColor = null;
                }),
              ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Widget kecil
// -----------------------------------------------------------------------------

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
      ),
    );
  }
}

class _IntroStep extends StatelessWidget {
  const _IntroStep({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.redSoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.red : AppColors.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.line),
        ),
      ),
    );
  }
}
