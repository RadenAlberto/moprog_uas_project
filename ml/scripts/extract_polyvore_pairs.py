#!/usr/bin/env python3
"""Membuat outfit_color_pairs.csv dari dataset Polyvore Outfits.

Kebutuhan: folder dataset yang berisi JSON outfit (format xthan/polyvore-dataset:
train_no_dup.json, dst.) dan folder gambar item (dari halaman Kaggle tidak resmi
yang ditautkan di repo tersebut). Skrip mengambil warna dominan tiap item
(piksel buram, bukan latar putih), memetakannya ke keluarga warna aplikasi, lalu
membuat:
  label=1 : dua item dalam outfit yang SAMA
  label=0 : dua item dari outfit yang BERBEDA (pasangan acak, jumlah sama)

  python scripts/extract_polyvore_pairs.py --json train_no_dup.json --images images/ --out data/raw/outfit_color_pairs.csv
Format JSON yang didukung: daftar outfit; tiap outfit punya 'items' dan tiap item
punya 'image' (nama berkas) atau 'index' (dipakai sebagai <index>.jpg)."""
import argparse
import itertools
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from mlcore.colors import family_of_rgb  # noqa: E402


def dominant_family(path):
    from PIL import Image
    im = Image.open(path).convert('RGB').resize((48, 48))
    counts = {}
    for r, g, b in im.getdata():
        if r > 235 and g > 235 and b > 235:      # latar putih
            continue
        key = family_of_rgb(r, g, b)
        counts[key] = counts.get(key, 0) + 1
    return max(counts, key=counts.get) if counts else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--json', required=True)
    ap.add_argument('--images', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--max-outfits', type=int, default=20000)
    a = ap.parse_args()
    outfits = json.loads(Path(a.json).read_text(encoding='utf8'))[:a.max_outfits]
    root = Path(a.images)
    cache, fam_by_outfit = {}, []
    for o in outfits:
        fams = []
        for it in o.get('items', []):
            name = it.get('image') or f"{it.get('index')}.jpg"
            if name not in cache:
                p = root / name
                cache[name] = dominant_family(p) if p.exists() else None
            if cache[name]:
                fams.append(cache[name])
        if len(fams) >= 2:
            fam_by_outfit.append(fams)
    rows = []
    for fams in fam_by_outfit:
        for x, y in itertools.combinations(fams, 2):
            rows.append((x, y, 1))
    rng = random.Random(1)
    allf = [f for fams in fam_by_outfit for f in fams]
    for _ in range(len(rows)):
        rows.append((rng.choice(allf), rng.choice(allf), 0))
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    with open(a.out, 'w', encoding='utf8') as f:
        f.write('family_a,family_b,label\n')
        for r in rows:
            f.write('%s,%s,%d\n' % r)
    print(f'{len(fam_by_outfit)} outfit, {len(rows)} baris -> {a.out}')


if __name__ == '__main__':
    main()
