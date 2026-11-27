import 'package:flutter/material.dart';

import '../MODELS/product_model.dart';

/// Kelompok pakaian.
enum GarmentGroup {
  top('Atasan'),
  inner('Dalaman'),
  bottom('Bawahan'),
  outer('Luaran'),
  set('Setelan'),
  accessory('Aksesori');

  const GarmentGroup(this.label);

  final String label;
}

/// Model kerah/leher pada atasan dan luaran.
enum Neckline {
  crew('bulat'),
  collar('kerah'),
  turtle('turtleneck'),
  hood('hoodie'),
  open('terbuka'),
  scoop('tanpa lengan'),
  none('');

  const Neckline(this.label);

  final String label;
}

/// Potongan pakaian.
enum GarmentFit {
  slim('slim'),
  regular('regular'),
  relaxed('longgar'),
  oversized('oversized');

  const GarmentFit(this.label);

  final String label;
}

/// Keluarga warna (disederhanakan) untuk mencocokkan dengan nada kulit.
enum ColorFamily {
  black('Hitam'),
  white('Putih'),
  grey('Abu-abu'),
  blue('Biru'),
  teal('Tosca'),
  purple('Ungu'),
  pink('Pink'),
  red('Merah'),
  green('Hijau'),
  earth('Cokelat/Krem');

  const ColorFamily(this.label);

  final String label;
}

/// Mengelompokkan [color] ke dalam [ColorFamily] berdasarkan HSL.
ColorFamily colorFamilyOf(Color color) {
  final hsl = HSLColor.fromColor(color);
  final l = hsl.lightness;
  final s = hsl.saturation;
  final h = hsl.hue;
  if (l < 0.14) return ColorFamily.black;
  if (l > 0.92 && s < 0.25) return ColorFamily.white;
  if (s < 0.12) return ColorFamily.grey;
  if (h < 12 || h >= 345) return ColorFamily.red;
  if (h < 70) return ColorFamily.earth;
  if (h < 170) return ColorFamily.green;
  if (h < 200) return ColorFamily.teal;
  if (h < 262) return ColorFamily.blue;
  if (h < 330) return ColorFamily.purple;
  return ColorFamily.pink;
}

/// Atribut turunan sebuah produk (dihitung dari nama, kategori, fitur, warna).
class ProductAttributes {
  const ProductAttributes({
    required this.group,
    required this.neckline,
    required this.fit,
    required this.colorFamilies,
    required this.goals,
    required this.isScarf,
    required this.isHeadwear,
    required this.isLong,
    required this.isAnkle,
  });

  final GarmentGroup group;
  final Neckline neckline;
  final GarmentFit fit;
  final List<ColorFamily> colorFamilies;

  /// Tag kebutuhan: `casual`, `work`, `sport`, `warm`.
  final Set<String> goals;
  final bool isScarf;
  final bool isHeadwear;

  /// Panjang (parka, midi) yang kurang cocok untuk tubuh pendek.
  final bool isLong;

  /// Celana cropped/ankle: memanjangkan kesan kaki tubuh pendek.
  final bool isAnkle;

  static final Map<String, ProductAttributes> _cache = {};

  /// Atribut dihitung sekali per produk lalu disimpan.
  factory ProductAttributes.of(Product product) {
    final key = '${product.id}|${product.name}|${product.category}';
    return _cache.putIfAbsent(key, () => _derive(product));
  }

  static ProductAttributes _derive(Product product) {
    final name = product.name.toLowerCase();
    final category = product.category.toLowerCase();
    final features = product.features.map((f) => f.toLowerCase()).toList();
    final text = '$name ${features.join(' ')}';

    final group = _groupOf(category);

    final isScarf = name.contains('scarf') || name.contains('syal');
    final isHeadwear = name.contains('beanie') ||
        name.contains('cap') ||
        name.contains('topi');

    Neckline neckline = Neckline.none;
    if (group == GarmentGroup.top ||
        group == GarmentGroup.inner ||
        group == GarmentGroup.outer ||
        group == GarmentGroup.set) {
      if (name.contains('turtleneck') || name.contains('kerah tinggi')) {
        neckline = Neckline.turtle;
      } else if (name.contains('hoodie') || name.contains('hooded')) {
        neckline = Neckline.hood;
      } else if (name.contains('tank') || name.contains('tanpa lengan')) {
        neckline = Neckline.scoop;
      } else if (name.contains('polo') ||
          category == 'shirts' ||
          (name.contains('shirt') && !name.contains('t-shirt'))) {
        neckline = Neckline.collar;
      } else if (name.contains('cardigan') ||
          name.contains('zip') ||
          group == GarmentGroup.outer) {
        neckline = Neckline.open;
      } else {
        neckline = Neckline.crew;
      }
    }

    GarmentFit fit = GarmentFit.regular;
    if (name.contains('oversized')) {
      fit = GarmentFit.oversized;
    } else if (name.contains('slim') ||
        name.contains('skinny') ||
        name.contains('ultra stretch') ||
        name.contains('ankle') ||
        name.contains('legging')) {
      fit = GarmentFit.slim;
    } else if (name.contains('wide') ||
        name.contains('relax') ||
        name.contains('cargo') ||
        name.contains('jogger') ||
        name.contains('easy') ||
        name.contains('sweat') ||
        name.contains('flannel') ||
        name.contains('souffle') ||
        name.contains('pleated') ||
        name.contains('down') ||
        name.contains('fleece') ||
        name.contains('rileks') ||
        name.contains('lebar') ||
        name.contains('longgar') ||
        name.contains('baggy') ||
        name.contains('barel') ||
        name.contains('boxy')) {
      fit = GarmentFit.relaxed;
    }

    final goals = <String>{};
    final isWork = category == 'shirts' ||
        name.contains('chino') ||
        name.contains('smart') ||
        name.contains('oxford') ||
        name.contains('blouse') ||
        name.contains('polo') ||
        name.contains('pleated') ||
        name.contains('kerja') ||
        name.contains('tailored') ||
        name.contains('slim fit');
    final isSport = text.contains('quick dry') ||
        text.contains('sweat') ||
        text.contains('jogger') ||
        text.contains('airism') ||
        text.contains('dry-ex') ||
        name.contains('aktif') ||
        category == 'shorts' ||
        text.contains('stretch');
    final isWarm = text.contains('heattech') ||
        text.contains('down') ||
        text.contains('fleece') ||
        text.contains('wool') ||
        text.contains('merino') ||
        text.contains('hangat') ||
        text.contains('wol') ||
        text.contains('kasmir') ||
        text.contains('flanel') ||
        text.contains('pufftech') ||
        text.contains('blocktech') ||
        category == 'knitwear' ||
        category == 'outerwear' ||
        isScarf ||
        name.contains('beanie') ||
        name.contains('topi');
    if (isWork) goals.add('work');
    if (isSport) goals.add('sport');
    if (isWarm) goals.add('warm');
    if (!isWork || category == 'jeans' || category == 't-shirts') {
      goals.add('casual');
    }

    final families = <ColorFamily>[];
    for (final color in product.availableColors) {
      final family = colorFamilyOf(color);
      if (!families.contains(family)) families.add(family);
    }

    return ProductAttributes(
      group: group,
      neckline: neckline,
      fit: fit,
      colorFamilies: families,
      goals: goals,
      isScarf: isScarf,
      isHeadwear: isHeadwear,
      isLong: name.contains('parka') ||
          name.contains('midi') ||
          name.contains('maxi') ||
          name.contains('mantel'),
      isAnkle: name.contains('ankle'),
    );
  }

  static GarmentGroup _groupOf(String category) {
    switch (category) {
      case 'pants':
      case 'jeans':
      case 'shorts':
      case 'skirts':
        return GarmentGroup.bottom;
      case 'outerwear':
        return GarmentGroup.outer;
      case 'innerwear':
        return GarmentGroup.inner;
      case 'accessories':
        return GarmentGroup.accessory;
      case 'loungewear':
      case 'dresses':
        return GarmentGroup.set;
      default:
        return GarmentGroup.top;
    }
  }
}
