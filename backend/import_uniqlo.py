#!/usr/bin/env python3
"""Mengonversi data Uniqlo (raw_products.json + variants.csv) menjadi katalog
UNIQLO PLUS.

    python3 import_uniqlo.py <folder uniqlo_output> [--variants variants.csv]

Hasil (satu sumber data untuk aplikasi DAN server):
  * backend/products_seed.json  -> di-seed ke SQLite oleh server.py
  * assets/data/products.json   -> dibaca aplikasi Flutter saat offline

Aturan pemetaan:
  * id        = productId Uniqlo (mis. E495975-000)
  * price     = harga promo bila ada, selain itu harga normal
  * original_price = harga normal bila sedang promo
  * colors / color_names / color_images : sejajar (indeks sama). Foto produk
    diambil dari images.main[kode warna] sehingga foto cocok dengan warnanya
  * sizes     = nama ukuran persis seperti di Uniqlo
  * category / audience dipetakan ke taksonomi yang sudah dipakai aplikasi
    (T-Shirts, Pants, Outerwear, ... dan Men/Women/Kids/Baby/Unisex)
"""
import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
OUT_SEED = HERE / 'products_seed.json'
OUT_ASSET = ROOT / 'assets' / 'data' / 'products.json'

# Nama warna Uniqlo -> (label Indonesia, ARGB). Setiap nama punya ARGB unik
# karena aplikasi mengenali warna terpilih lewat nilai ARGB-nya.
PALETTE = {
    'BLACK': ('Hitam', 0xFF111111),
    'WHITE': ('Putih', 0xFFFFFFFF),
    'OFF WHITE': ('Putih Gading', 0xFFF4F2EF),
    'GRAY': ('Abu-abu', 0xFF9E9E9E),
    'DARK GRAY': ('Abu-abu Tua', 0xFF4D4D4D),
    'LIGHT GRAY': ('Abu-abu Muda', 0xFFD0D0D0),
    'BLUE': ('Biru', 0xFF2F6FDB),
    'NAVY': ('Biru Navy', 0xFF1F2A5C),
    'LIGHT BLUE': ('Biru Muda', 0xFF9CC7F0),
    'PINK': ('Merah Muda', 0xFFF48FB1),
    'RED': ('Merah', 0xFFD32F2F),
    'WINE': ('Merah Anggur', 0xFF722F37),
    'BEIGE': ('Beige', 0xFFD9C3A5),
    'NATURAL': ('Natural', 0xFFE8DCC4),
    'CREAM': ('Krem', 0xFFFFF3C4),
    'KHAKI': ('Khaki', 0xFFC3B091),
    'BROWN': ('Cokelat', 0xFF7B4B2A),
    'DARK BROWN': ('Cokelat Tua', 0xFF4A2C1A),
    'OLIVE': ('Olive', 0xFF6B7233),
    'GREEN': ('Hijau', 0xFF2E9E4F),
    'DARK GREEN': ('Hijau Tua', 0xFF1E5B34),
    'LIGHT GREEN': ('Hijau Muda', 0xFFA5D6A7),
    'YELLOW': ('Kuning', 0xFFFFD54F),
    'MUSTARD': ('Mustard', 0xFFD4A017),
    'ORANGE': ('Oranye', 0xFFFB8C00),
    'DARK ORANGE': ('Oranye Tua', 0xFFD84315),
    'LIGHT ORANGE': ('Oranye Muda', 0xFFFFCC80),
    'PURPLE': ('Ungu', 0xFF8E44AD),
    'LIGHT PURPLE': ('Ungu Muda', 0xFFCE93D8),
    'DARK PURPLE': ('Ungu Tua', 0xFF4A2A6B),
}
OTHER = ('Warna Lain', 0xFF8D8D9A)

AUDIENCE = {
    'MEN': 'Men', 'WOMEN': 'Women', 'KIDS': 'Kids',
    'BABY': 'Baby', 'UNISEX': 'Unisex',
}
AUDIENCE_ID = {
    'Men': 'pria', 'Women': 'wanita', 'Kids': 'anak-anak',
    'Baby': 'bayi', 'Unisex': 'pria dan wanita (uniseks)',
}

# Aturan kategori: kata kunci (huruf kecil) -> kategori. Kata kunci yang
# MUNCUL PALING AWAL di nama menentukan jenis pakaian ("Celana Lebar Sweat"
# = celana, bukan sweatshirt); bila sama posisinya, yang lebih panjang menang
# ("celana pendek" mengalahkan "celana").
CATEGORY_KEYWORDS = {
    'Accessories': ['kaos kaki', 'sarung tangan', 'tas', 'ikat pinggang',
                    'kacamata', 'topi', 'syal', 'beanie', 'charm', 'hijab',
                    'payung', 'sepatu', 'penghangat', 'dompet', 'ikat rambut'],
    'Innerwear': ['pakaian dalam', 'kamisol', 'bra', 'atasan bra',
                  'celana dalam', 'celana boxer', 'boxer', 'singlet', 'dalaman'],
    'Loungewear': ['piyama', 'pakaian santai', 'baju tidur'],
    'Dresses': ['gaun', 'baju terusan', 'jumpsuit'],
    'Skirts': ['rok'],
    'Outerwear': ['jaket', 'mantel', 'parka', 'blazer', 'rompi'],
    'Sweatshirts': ['hoodie', 'sweatshirt', 'pullover sweat'],
    'Knitwear': ['sweater', 'cardigan', 'pullover'],
    'Shirts': ['kemeja', 'blus'],
    'Jeans': ['jeans'],
    'Shorts': ['celana pendek'],
    'Pants': ['celana', 'kulot', 'legging', 'leging'],
    'T-Shirts': ['kaos', 't-shirt', 'polo', 'tank', 'atasan', 'ut'],
}
_KEYWORD_RES = [
    (re.compile(r'(?<![a-z0-9])' + re.escape(k) + r'(?![a-z0-9])'), k, cat)
    for cat, keys in CATEGORY_KEYWORDS.items() for k in keys
]

TECH_LABELS = [
    ('HEATTECH', 'HEATTECH'), ('AIRism', 'AIRism'), ('PUFFTECH', 'PUFFTECH'),
    ('BLOCKTECH', 'BLOCKTECH'), ('ULTRA LIGHT DOWN', 'Ultra Light Down'),
    ('ULTRA STRETCH', 'Ultra Stretch'), ('DRY-EX', 'DRY-EX'),
    ('FLEECE', 'Fleece'), ('FLANEL', 'Flanel'), ('WOL', 'Wol'),
    ('MERINO', 'Merino'), ('KASMIR', 'Kasmir'), ('LINEN', 'Linen'),
    ('DENIM', 'Denim'), ('OVERSIZED', 'Oversized'), ('BOXY', 'Boxy'),
    ('RAJUT', 'Rajut'), ('UV PROTECTION', 'Anti-UV'), ('KATUN', 'Katun'),
    ('SWEAT', 'Sweat'), ('STRETCH', 'Stretch'), ('JOGGER', 'Jogger'),
]


def category_of(name, gender=None):
    low = name.lower()
    best = None  # (posisi, -panjang, kategori)
    for regex, key, cat in _KEYWORD_RES:
        m = regex.search(low)
        if m:
            cand = (m.start(), -len(key), cat)
            if best is None or cand < best:
                best = cand
    cat = best[2] if best else 'T-Shirts'
    if cat == 'Pants' and 'denim' in low and 'legging' not in low:
        cat = 'Jeans'
    # HEATTECH / AIRism berupa atasan = pakaian dalam (lapisan dasar).
    if cat == 'T-Shirts' and ('heattech' in low or 'airism' in low):
        cat = 'Innerwear'
    return cat


def features_of(name, flags):
    up = name.upper()
    out = []
    for key, label in TECH_LABELS:
        if re.search(r'(?<![A-Z])' + re.escape(key) + r'(?![A-Z])', up):
            if label not in out:
                out.append(label)
    if re.search(r'(?<![A-Z])UT(?![A-Z])', up) or 'MANGA' in up:
        out.append('UT')
    if any(f.get('name') == 'Dibuat dari Bahan Daur Ulang' for f in flags):
        out.append('Bahan Daur Ulang')
    return out


def build_colors(colors, main_images):
    """Mengembalikan (argb[], label[], foto[]) sejajar urutan warna Uniqlo."""
    argb, labels, images, used = [], [], [], set()
    for c in colors:
        code = c['displayCode']
        label, value = PALETTE.get(c['name'].upper(), OTHER)
        while value in used:  # ARGB harus unik dalam satu produk
            value += 1
        used.add(value)
        argb.append(value)
        labels.append(label if c['name'].upper() in PALETTE
                      else 'Warna Lain %s' % code)
        main = main_images.get(code) or {}
        images.append(main.get('image', ''))
    return argb, labels, images


def convert(raw):
    p = raw
    audience = AUDIENCE.get(p['genderCategory'], 'Unisex')
    name = p['name'].strip()
    base = p['prices']['base']['value']
    promo = (p['prices'].get('promo') or {}).get('value')
    price = promo if promo else base
    original = base if promo and promo < base else None

    colors = p['colors']
    main = p['images']['main']
    argb, labels, color_imgs = build_colors(colors, main)
    rep = p.get('representativeColorDisplayCode')
    rep_img = (main.get(rep) or {}).get('image') or next(
        (i for i in color_imgs if i), '')

    # Galeri: foto "sub", tiap foto boleh terikat ke satu warna.
    gallery, seen = [], set()
    for sub in p['images'].get('sub', []):
        url = sub.get('image')
        if url and url not in seen:
            seen.add(url)
            gallery.append({'url': url, 'color': sub.get('colorCode') or ''})

    flags = (p.get('representative', {}).get('flags', {}).get('productFlags', [])
             + p.get('representative', {}).get('flags', {}).get('priceFlags', []))
    flag_names = [f.get('name', '') for f in flags]
    is_new = any(f.get('code') in ('salesStart', 'newSKU') for f in flags)

    sizes = [s['name'] for s in p['sizes']]
    notes = []
    for f in flags:
        if f.get('code') == 'comingSoon':
            notes.append(f['name'] + '.')
        elif f.get('code') == 'onlineOnly':
            notes.append('Hanya tersedia online.')
        elif f.get('name') == 'Dibuat dari Bahan Daur Ulang':
            notes.append('Dibuat dari bahan daur ulang.')
    description = (
        '%s untuk %s. Tersedia dalam %d warna (%s) dan ukuran %s.' % (
            name, AUDIENCE_ID[audience], len(labels), ', '.join(labels),
            sizes[0] if len(sizes) == 1 else '%s sampai %s' % (sizes[0], sizes[-1]))
    )
    if notes:
        description += ' ' + ' '.join(dict.fromkeys(notes))

    rating = p.get('rating') or {}
    return {
        'id': p['productId'],
        'name': name,
        'price': price,
        'original_price': original,
        'image': rep_img,
        'category': category_of(name, audience),
        'audience': audience,
        'description': description,
        'features': features_of(name, flags),
        'is_new': is_new,
        'sizes': sizes,
        'colors': argb,
        'color_names': labels,
        'color_codes': [c['displayCode'] for c in colors],
        'color_images': color_imgs,
        'gallery': gallery,
        'rating_average': rating.get('average') or 0,
        'rating_count': rating.get('count') or 0,
        # Sama dengan kolom url di products.csv (grup harga "00").
        'url': 'https://www.uniqlo.com/id/id/products/%s/00' % p['productId'],
    }


def check_against_csv(products, variants_csv):
    """Memastikan tiap produk x warna x ukuran sama persis dengan variants.csv."""
    expected = defaultdict(set)
    prices = {}
    with open(variants_csv, encoding='utf-8-sig', newline='') as f:
        for r in csv.DictReader(f):
            expected[r['product_id']].add((r['color_code'], r['size_name']))
            prices[r['product_id']] = (
                int(float(r['price_promo'] or r['price_base'])))
    problems = []
    for p in products:
        grid = {(c, s) for c in p['color_codes'] for s in p['sizes']}
        if grid != expected.get(p['id']):
            problems.append('%s: kombinasi warna/ukuran berbeda' % p['id'])
        if prices.get(p['id']) != int(p['price']):
            problems.append('%s: harga %s != CSV %s' % (
                p['id'], p['price'], prices.get(p['id'])))
    extra = set(expected) - {p['id'] for p in products}
    if extra:
        problems.append('%d produk ada di CSV tapi tidak di JSON' % len(extra))
    return problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('folder', type=Path)
    ap.add_argument('--variants', type=Path)
    args = ap.parse_args()

    raw = json.loads((args.folder / 'raw_products.json').read_text(encoding='utf8'))
    products = [convert(r) for r in raw]
    ids = [p['id'] for p in products]
    assert len(ids) == len(set(ids)), 'ID produk dobel'

    variants = args.variants or args.folder / 'variants.csv'
    if variants.exists():
        problems = check_against_csv(products, variants)
        for line in problems[:20]:
            print('PERINGATAN', line, file=sys.stderr)
        print('Validasi terhadap variants.csv: %s' % (
            'OK' if not problems else '%d masalah' % len(problems)))

    text = json.dumps(products, ensure_ascii=False, separators=(',', ':'))
    OUT_SEED.write_text(text, encoding='utf8')
    OUT_ASSET.parent.mkdir(parents=True, exist_ok=True)
    OUT_ASSET.write_text(text, encoding='utf8')
    n_var = sum(len(p['colors']) * len(p['sizes']) for p in products)
    print('%d produk, %d varian -> %s, %s' % (
        len(products), n_var, OUT_SEED, OUT_ASSET))


if __name__ == '__main__':
    main()
