"""Menjalankan seluruh pelatihan dan menulis model.json + laporan bukti data."""
import hashlib
import json
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from . import learn, synth
from .colors import family_of_argb

SCHEMA = 1


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def sha256_folder(folder):
    h = hashlib.sha256()
    n = 0
    for p in sorted(Path(folder).rglob('*')):
        if p.is_file():
            h.update(str(p.relative_to(folder)).encode())
            h.update(str(p.stat().st_size).encode())
            n += 1
    return h.hexdigest(), n


def real_feedback_from_db(db_path):
    """Feedback nyata pengguna aplikasi digabung dengan profil kulit mereka."""
    con = sqlite3.connect(db_path)
    con.row_factory = sqlite3.Row
    rows = con.execute(
        'SELECT f.user_id, f.action, p.colors, s.profile_json FROM feedback f '
        'JOIN products p ON p.id=f.product_id JOIN style_profiles s ON s.user_id=f.user_id '
        "WHERE f.action IN ('like','dislike','cart')").fetchall()
    con.close()
    out = []
    for r in rows:
        try:
            prof = json.loads(r['profile_json'])
            u, d = prof.get('undertone'), prof.get('depth')
            if u not in ('warm', 'cool', 'neutral') or d not in ('light', 'medium', 'deep'):
                continue
            fams = {family_of_argb(int(c)) for c in json.loads(r['colors'])}
        except Exception:
            continue
        label = 0 if r['action'] == 'dislike' else 1
        for fam in fams:
            out.append((r['user_id'], prof.get('gender', ''), u, d, fam, label, 'real'))
    return pd.DataFrame(out, columns=['user_id', 'gender', 'undertone', 'depth', 'family', 'label', 'source'])


def run(out_dir, db=None, styles=None, faces=None, skin_csv=None, pairs=None, n_users=4000, seed=11):
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    datasets, components, metrics = [], {}, {}

    # --- data sintetis (bootstrap) ---
    sdf = synth.simulate_interactions(n_users=n_users, seed=seed)
    datasets.append({'id': 'synthetic-personas', 'name': 'Simulasi pengguna (teori analisis warna personal)',
                     'kind': 'synthetic', 'rows': int(len(sdf)), 'sha256': hashlib.sha256(sdf.to_csv().encode()).hexdigest(),
                     'license': 'dibuat sendiri', 'url': '', 'used_for': ['tone_color']})

    # --- data nyata dari server ---
    real = None
    if db and Path(db).exists():
        real = real_feedback_from_db(db)
        datasets.append({'id': 'app-feedback', 'name': 'Umpan balik pengguna aplikasi (like/dislike/keranjang)',
                         'kind': 'real', 'rows': int(len(real)), 'sha256': '', 'license': 'data milik pengguna aplikasi',
                         'url': '', 'used_for': ['tone_color']})
    comp, met = learn.train_tone_color(sdf, real)
    components['tone_color'], metrics['tone_color'] = comp, met

    # --- pasangan warna outfit ---
    pdf = pd.read_csv(pairs) if pairs and Path(pairs).exists() else None
    if pdf is not None:
        datasets.append({'id': 'outfit-color-pairs', 'name': 'Pasangan warna outfit (Polyvore Outfits)', 'kind': 'real',
                         'rows': int(len(pdf)), 'sha256': sha256_file(pairs), 'license': 'lihat ml/DATASETS.md',
                         'url': 'https://github.com/xthan/polyvore-dataset', 'used_for': ['color_pair']})
    comp, met = learn.train_color_pair(pdf)
    components['color_pair'], metrics['color_pair'] = comp, met

    # --- prior pasar dari styles.csv ---
    if styles and Path(styles).exists():
        comp, met = learn.color_market_prior(styles)
        components['color_market'] = comp
        metrics['color_market'] = met
        datasets.append({'id': 'kaggle-fashion-product-images', 'name': 'Fashion Product Images Dataset (styles.csv)',
                         'kind': 'real', 'rows': met['rows'], 'sha256': sha256_file(styles),
                         'license': 'lihat halaman dataset di Kaggle',
                         'url': 'https://www.kaggle.com/datasets/paramaggarwal/fashion-product-images-dataset',
                         'used_for': ['color_market']})

    # --- bentuk wajah ---
    if faces and Path(faces).exists():
        df, skipped = learn.extract_face_features(faces)
        if len(df) >= 100:
            comp, met = learn.train_face_shape(df)
            met['skipped_no_face_detected'] = skipped
            components['face_shape'], metrics['face_shape'] = comp, met
            digest, n = sha256_folder(faces)
            datasets.append({'id': 'face-shape', 'name': 'Face Shape Dataset (foto 5 kelas)', 'kind': 'real',
                             'rows': int(len(df)), 'sha256': digest, 'license': 'lihat halaman dataset di Kaggle',
                             'url': 'https://www.kaggle.com/datasets/lucifierx/face-shape-classification',
                             'used_for': ['face_shape']})
        else:
            metrics['face_shape'] = {'error': f'Hanya {len(df)} foto terbaca (butuh >= 100). Periksa struktur folder.'}

    # --- kedalaman kulit ---
    if skin_csv and Path(skin_csv).exists():
        df = learn.extract_skin_features(skin_csv)
        if len(df) >= 100:
            comp, met = learn.train_skin_depth(df)
            components['skin_depth'], metrics['skin_depth'] = comp, met
            datasets.append({'id': 'skin-mst', 'name': 'Foto berlabel Monk Skin Tone', 'kind': 'real',
                             'rows': int(len(df)), 'sha256': sha256_file(skin_csv), 'license': 'lihat ml/DATASETS.md',
                             'url': 'https://skintone.google', 'used_for': ['skin_depth']})

    now = datetime.now(timezone.utc)
    model = {'schema': SCHEMA, 'version': now.strftime('%Y.%m.%d-%H%M%S'), 'trained_at': now.isoformat(),
             'components': components, 'datasets': datasets, 'metrics': metrics}
    body = json.dumps(model, ensure_ascii=False, indent=1)
    (out / 'model.json').write_text(body, encoding='utf8')
    (out / 'REPORT.md').write_text(render_report(model), encoding='utf8')
    return model


def render_report(m):
    L = [f"# Laporan pelatihan model UNIQLO PLUS", '', f"Versi: `{m['version']}`  |  Dilatih: {m['trained_at']}", '',
         '## 1. Data yang dipakai (bukti)', '',
         '| ID | Nama | Jenis | Baris | SHA-256 | Dipakai untuk |', '|---|---|---|---|---|---|']
    for d in m['datasets']:
        L.append(f"| {d['id']} | {d['name']} | **{d['kind']}** | {d['rows']} | `{d['sha256'][:16] or '-'}` | {', '.join(d['used_for'])} |")
    L += ['', '## 2. Komponen model dan sumbernya', '', '| Komponen | Sumber |', '|---|---|']
    for k, v in m['components'].items():
        L.append(f"| {k} | {v.get('source')} |")
    L += ['', 'Keterangan sumber: `prior:theory` = aturan teori (BELUM dilatih), `trained:synthetic` = dilatih dari '
          'simulasi (bootstrap), `+feedback` = juga memakai umpan balik pengguna nyata, `trained:real` = dilatih '
          'dari dataset nyata.', '', '## 3. Metrik', '']
    for k, v in m['metrics'].items():
        L.append(f'### {k}')
        for kk, vv in v.items():
            if isinstance(vv, dict) and len(json.dumps(vv)) > 160:
                continue
            L.append(f'- {kk}: {vv}')
        L.append('')
    return '\n'.join(L)
