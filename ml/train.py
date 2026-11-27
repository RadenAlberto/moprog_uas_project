#!/usr/bin/env python3
"""Melatih model UNIQLO PLUS.

Contoh:
  python train.py                                   # bootstrap (data sintetis)
  python train.py --db ../backend/uniqlo_plus.sqlite3   # + umpan balik pengguna nyata
  python train.py --styles data/raw/styles.csv --faces data/raw/faceshape/training_set \\
                  --skin-csv data/raw/mst/labels.csv --pairs data/raw/outfit_color_pairs.csv --export-assets
Keluaran: artifacts/model.json, artifacts/REPORT.md (+ ../assets/data/ml_model.json bila --export-assets)."""
import argparse
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from mlcore import pipeline  # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--out', default=str(HERE / 'artifacts'))
    ap.add_argument('--db', help='SQLite server (feedback + profil gaya pengguna nyata)')
    ap.add_argument('--styles', help='styles.csv dari Kaggle Fashion Product Images')
    ap.add_argument('--faces', help='folder foto bentuk wajah: <folder>/<Heart|Oblong|Oval|Round|Square>/*.jpg')
    ap.add_argument('--skin-csv', help='CSV path,mst untuk foto berlabel Monk Skin Tone')
    ap.add_argument('--pairs', help='CSV family_a,family_b,label hasil scripts/extract_polyvore_pairs.py')
    ap.add_argument('--users', type=int, default=4000, help='jumlah pengguna sintetis')
    ap.add_argument('--export-assets', action='store_true', help='salin model.json ke assets/data/ml_model.json')
    a = ap.parse_args(argv)
    model = pipeline.run(a.out, db=a.db, styles=a.styles, faces=a.faces, skin_csv=a.skin_csv,
                         pairs=a.pairs, n_users=a.users)
    if a.export_assets:
        dst = HERE.parent / 'assets' / 'data' / 'ml_model.json'
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(Path(a.out) / 'model.json', dst)
        print('Diekspor ke', dst)
    print('Model', model['version'], '->', Path(a.out) / 'model.json')
    for k, v in model['components'].items():
        print(f'  {k:14s} {v["source"]}')
    return model


if __name__ == '__main__':
    main()
