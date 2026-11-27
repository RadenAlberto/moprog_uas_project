import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/style_model.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../PROVIDERS/style_provider.dart';
import '../SERVICES/product_attributes.dart';
import '../SERVICES/style_recommender.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/auth_gate.dart';
import '../UTILS/formatters.dart';
import '../UTILS/nav.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/face_shape_icon.dart';
import '../WIDGETS/product_image.dart';
import '../WIDGETS/section_header.dart';
import '../WIDGETS/server_status.dart';
import '../WIDGETS/ui_kit.dart';
import 'detailproduk_uniqlo.dart';
import 'style_advisor_page.dart';

/// Nama filter untuk tiap kelompok pakaian.
String _filterLabel(GarmentGroup group) {
  switch (group) {
    case GarmentGroup.top:
    case GarmentGroup.inner:
      return 'Atasan';
    case GarmentGroup.bottom:
      return 'Bawahan';
    case GarmentGroup.outer:
      return 'Luaran';
    case GarmentGroup.accessory:
      return 'Aksesori';
    case GarmentGroup.set:
      return 'Setelan';
  }
}

const int _kMaxTiles = 24;

/// Hasil UNIQLO PLUS Stylist: ringkasan profil, tips, warna, set pakaian, dan
/// daftar produk yang cocok beserta alasannya.
class StyleResultPage extends StatefulWidget {
  const StyleResultPage({super.key});

  @override
  State<StyleResultPage> createState() => _StyleResultPageState();
}

class _StyleResultPageState extends State<StyleResultPage> {
  String _filter = 'Semua';
  bool _showAll = false;

  void _redo() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const StyleAdvisorPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = context.watch<StyleProvider>();
    final profile = style.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('REKOMENDASI GAYA'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan server',
            onPressed: () => showServerSettings(context),
            icon: const Icon(Icons.cloud_outlined),
          ),
        ],
      ),
      body: profile == null
          ? EmptyState(
              icon: Icons.auto_awesome,
              title: 'Belum ada analisis gaya',
              message: 'Isi data dirimu dan foto selfie agar kami bisa '
                  'merekomendasikan pakaian yang cocok.',
              actionLabel: 'Mulai analisis',
              onAction: _redo,
            )
          : _buildContent(context, style, profile),
    );
  }

  Widget _buildContent(
    BuildContext context,
    StyleProvider style,
    BodyProfile profile,
  ) {
    final recs = style.recommendations;
    final outfits = style.outfits;
    final tips = style.tips;
    final colors = style.bestColors;
    final loggedIn = context.select<AuthProvider, bool>((a) => a.isLoggedIn);

    final labels = <String>[];
    for (final rec in recs) {
      final label = _filterLabel(ProductAttributes.of(rec.product).group);
      if (!labels.contains(label)) labels.add(label);
    }
    final filtered = _filter == 'Semua'
        ? recs
        : [
            for (final rec in recs)
              if (_filterLabel(ProductAttributes.of(rec.product).group) == _filter)
                rec,
          ];
    final visible = _showAll ? filtered : filtered.take(_kMaxTiles).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 32),
          children: [
            _ProfileCard(profile: profile, onRedo: _redo),
            if (!loggedIn) _GuestBanner(profile: profile),
            if (tips.isNotEmpty) ...[
              const SizedBox(height: 18),
              const SectionHeader(
                title: 'Tips gaya untukmu',
                subtitle: 'Berdasarkan wajah, tubuh, dan warna kulitmu',
              ),
              const SizedBox(height: 10),
              _TipsCard(tips: tips),
            ],
            if (colors.isNotEmpty) ...[
              const SizedBox(height: 18),
              const SectionHeader(title: 'Warna paling serasi'),
              const SizedBox(height: 10),
              _ColorRow(colors: colors),
            ],
            if (outfits.isNotEmpty) ...[
              const SizedBox(height: 18),
              const SectionHeader(
                title: 'Set pakaian siap pakai',
                subtitle: 'Padu padan lengkap, tinggal pilih',
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 280,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: outfits.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) =>
                      _OutfitCard(outfit: outfits[index]),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SectionHeader(
              title: 'Produk yang cocok untukmu',
              subtitle: '${recs.length} produk diurutkan dari yang paling pas',
            ),
            const SizedBox(height: 10),
            if (labels.length > 1)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final label in ['Semua', ...labels])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == label,
                          selectedColor: AppColors.redSoft,
                          onSelected: (_) => setState(() {
                            _filter = label;
                            _showAll = false;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Belum ada produk di kategori ini.')),
              ),
            for (final rec in visible)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _RecoTile(rec: rec),
              ),
            if (!_showAll && filtered.length > _kMaxTiles)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showAll = true),
                  child: Text('Tampilkan semua (${filtered.length})'),
                ),
              ),
            const SizedBox(height: 10),
            _LearningCard(style: style),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Rekomendasi bersifat saran berdasarkan perkiraan dari foto, '
                'tinggi, dan berat badan. Ukuran dan kenyamanan tetap perlu '
                'dicoba langsung.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Ringkasan profil
// -----------------------------------------------------------------------------

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onRedo});

  final BodyProfile profile;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final skin = profile.skinColor ?? const Color(0xFFC99B76);
    final face = profile.faceShape;
    return SurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (face != null)
                Container(
                  width: 62,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: skin.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: FaceShapeIcon(shape: face, color: AppColors.ink),
                ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profil gayamu',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${profile.gender.label}, ${profile.heightCm.round()} cm, '
                      '${profile.weightKg.round()} kg (BMI ${profile.bmi.toStringAsFixed(1)})',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (face != null)
                _InfoPill(icon: Icons.face, text: 'Wajah ${face.label}'),
              if (profile.undertone != null)
                _InfoPill(
                  icon: Icons.palette_outlined,
                  text: 'Kulit ${profile.depth?.label.toLowerCase() ?? ''} '
                      '${profile.undertone!.label.toLowerCase()}',
                  dot: skin,
                ),
              _InfoPill(
                icon: Icons.accessibility_new,
                text: 'Tubuh ${profile.bodyType.label.toLowerCase()}',
              ),
              _InfoPill(
                icon: Icons.height,
                text: 'Tinggi ${profile.heightClass.label.toLowerCase()}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRedo,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Ubah data / foto ulang'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text, this.dot});

  final IconData icon;
  final String text;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null)
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
            )
          else ...[
            Icon(icon, size: 15, color: AppColors.muted),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _GuestBanner extends StatelessWidget {
  const _GuestBanner({required this.profile});

  final BodyProfile profile;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const IconBadge(icon: Icons.cloud_sync_outlined, size: 40),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Masuk sebagai member agar hasil analisis dan pembelajaran '
                'modelmu tersimpan di server dan ikut ke perangkat lain.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => requireMember(
                context,
                message: 'Masuk atau gabung member untuk menyimpan profil '
                    'gaya ke akunmu.',
              ),
              child: const Text('Masuk'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard({required this.tips});

  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tips.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == tips.length - 1 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.lightbulb_outline, size: 17, color: AppColors.star),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tips[i],
                      style: const TextStyle(fontSize: 13, height: 1.45),
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

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.colors});

  final List<ColorFamily> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final family = colors[index];
          return Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: swatchOf(family),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line, width: 1.5),
                  boxShadow: AppShadows.soft,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                family.label,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Set pakaian
// -----------------------------------------------------------------------------

class _OutfitCard extends StatelessWidget {
  const _OutfitCard({required this.outfit});

  final OutfitSuggestion outfit;

  @override
  Widget build(BuildContext context) {
    var total = 0.0;
    for (final item in outfit.items) {
      total += item.product.price;
    }
    return SizedBox(
      width: 272,
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              outfit.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Column(
                children: [
                  for (final item in outfit.items)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => pushPage(
                          context,
                          ProductDetailPage(product: item.product),
                        ),
                        child: Row(
                          children: [
                            ProductImage(
                              item.product,
                              width: 36,
                              height: 48,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Ukuran ${item.suggestedSize} - ${item.product.formattedPrice}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatRupiah(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: AppColors.red,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _addAll(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Beli set',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addAll(BuildContext context) {
    final app = context.read<AppState>();
    final style = context.read<StyleProvider>();
    for (final item in outfit.items) {
      app.addToCart(item.product, item.suggestedSize, item.bestColor, context);
      style.giveFeedback(item, StyleFeedback.cart);
    }
    showAppToast(
      context,
      '${outfit.items.length} item ditambahkan ke keranjang',
      icon: Icons.shopping_bag,
    );
  }
}

// -----------------------------------------------------------------------------
// Kartu produk rekomendasi
// -----------------------------------------------------------------------------

class _RecoTile extends StatelessWidget {
  const _RecoTile({required this.rec});

  final StyleRecommendation rec;

  @override
  Widget build(BuildContext context) {
    final product = rec.product;
    final vote = context.select<StyleProvider, int>(
      (s) => s.voteFor(product.id),
    );
    final dimmed = vote < 0;

    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: SurfaceCard(
        padding: const EdgeInsets.all(10),
        onTap: () => pushPage(context, ProductDetailPage(product: product)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ProductImage(
                  product,
                  width: 93,
                  height: 124,
                  borderRadius: BorderRadius.circular(12),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: rec.percent >= 80 ? AppColors.success : AppColors.ink,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${rec.percent}% cocok',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    product.formattedPrice,
                    style: const TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: rec.bestColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Warna terbaik - ukuran ${rec.suggestedSize}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final reason in rec.reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.check, size: 13, color: AppColors.success),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              reason,
                              style: const TextStyle(fontSize: 11.5, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _VoteButton(
                        icon: vote > 0 ? Icons.thumb_up : Icons.thumb_up_outlined,
                        color: AppColors.success,
                        tooltip: 'Cocok',
                        onTap: () => context
                            .read<StyleProvider>()
                            .giveFeedback(rec, StyleFeedback.like),
                      ),
                      _VoteButton(
                        icon: vote < 0 ? Icons.thumb_down : Icons.thumb_down_outlined,
                        color: AppColors.redDark,
                        tooltip: 'Kurang cocok',
                        onTap: () => context
                            .read<StyleProvider>()
                            .giveFeedback(rec, StyleFeedback.dislike),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          context.read<AppState>().addToCart(
                                product,
                                rec.suggestedSize,
                                rec.bestColor,
                                context,
                              );
                          context
                              .read<StyleProvider>()
                              .giveFeedback(rec, StyleFeedback.cart);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.red,
                          side: const BorderSide(color: AppColors.red),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.add_shopping_cart, size: 15),
                        label: const Text(
                          'Keranjang',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 32,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Pembelajaran model
// -----------------------------------------------------------------------------

class _LearningCard extends StatelessWidget {
  const _LearningCard({required this.style});

  final StyleProvider style;

  @override
  Widget build(BuildContext context) {
    final model = style.model;

    final shifts = <MapEntry<String, double>>[
      for (var i = 1; i < StyleModel.featureLabels.length; i++)
        MapEntry(StyleModel.featureLabels[i], model.shift(i)),
    ]..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final notable = shifts.where((e) => e.value.abs() >= 0.05).take(3).toList();

    final favorites = model.categoryAffinity.entries
        .where((e) => e.value >= 0.6)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final colorNames = ColorFamily.values.asNameMap();
    final favoriteColors = model.colorAffinity.entries
        .where((e) => e.value >= 0.58 && colorNames.containsKey(e.key))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SurfaceCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology_outlined, color: AppColors.red),
              SizedBox(width: 8),
              Text(
                'Model ML-mu',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            style.learnedSamples == 0
                ? 'Tekan jempol "Cocok" atau "Kurang cocok" pada produk agar '
                    'rekomendasi makin sesuai seleramu. Model belajar langsung '
                    'di perangkatmu.'
                : 'Model sudah belajar dari ${style.learnedSamples} penilaianmu.',
            style: const TextStyle(fontSize: 12.5, height: 1.45),
          ),
          if (notable.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final entry in notable)
              Text(
                '${entry.value > 0 ? '▲' : '▼'} ${entry.key}: '
                '${entry.value > 0 ? 'makin diprioritaskan' : 'makin dikurangi'}',
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
          ],
          if (favorites.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Jenis favoritmu: ${favorites.take(3).map((e) => e.key).join(', ')}',
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ),
          if (favoriteColors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Warna favoritmu: ${favoriteColors.take(3).map((e) => colorNames[e.key]?.label ?? e.key).join(', ')}',
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Skor "% cocok" juga memperhitungkan tren dari semua pengguna '
            'yang tersimpan di server.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
