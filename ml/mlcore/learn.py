"""Trainer tiap komponen model. Semuanya mengembalikan (komponen_json, metrik)."""
import math
from pathlib import Path

import numpy as np
import pandas as pd

from . import faceport
from .colors import (DEPTHS, FAMILIES, KAGGLE_COLOR_TO_FAMILY, MST_GROUP, UNDERTONES)
from .theory import theory_pair_matrix, theory_tone


def _auc(y, s):
    y = np.asarray(y)
    s = np.asarray(s, dtype=float)
    pos, neg = s[y == 1], s[y == 0]
    if len(pos) == 0 or len(neg) == 0:
        return float('nan')
    ranks = pd.Series(np.concatenate([pos, neg])).rank().to_numpy()
    return float((ranks[:len(pos)].sum() - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg)))


def _logloss(y, p):
    p = np.clip(np.asarray(p, dtype=float), 1e-6, 1 - 1e-6)
    y = np.asarray(y)
    return float(-(y * np.log(p) + (1 - y) * np.log(1 - p)).mean())


# ---------------------------------------------------------------------------
# 1. Kecocokan warna pakaian x warna kulit (undertone x kedalaman x keluarga warna)
# ---------------------------------------------------------------------------
def train_tone_color(synth, real=None, real_weight=3.0, seed=5):
    """Posterior Beta per sel (undertone, depth, family).

    * data sintetis = bootstrap; data nyata (feedback pengguna) berbobot lebih besar.
    * dievaluasi pada pengguna tersisih (held-out) dengan AUC dan log-loss, dibanding
      baseline: (a) satu angka rata-rata global, (b) tabel teori tanpa belajar."""
    rng = np.random.default_rng(seed)
    users = synth['user_id'].unique()
    test_users = set(rng.choice(users, size=max(1, len(users) // 5), replace=False))
    tr = synth[~synth['user_id'].isin(test_users)]
    te = synth[synth['user_id'].isin(test_users)]

    def counts(df, weight=1.0):
        pos, tot = {}, {}
        for (u, d, f), g in df.groupby(['undertone', 'depth', 'family']):
            pos[(u, d, f)] = float(g['label'].sum()) * weight
            tot[(u, d, f)] = float(len(g)) * weight
        return pos, tot

    pos, tot = counts(tr)
    n_real = 0
    if real is not None and len(real):
        n_real = len(real)
        rp, rt = counts(real, real_weight)
        for k in rt:
            pos[k] = pos.get(k, 0.0) + rp[k]
            tot[k] = tot.get(k, 0.0) + rt[k]

    rate = {}
    for u in UNDERTONES:
        for d in DEPTHS:
            for f in FAMILIES:
                p_, t_ = pos.get((u, d, f), 0.0), tot.get((u, d, f), 0.0)
                rate[(u, d, f)] = (p_ + 1.0) / (t_ + 2.0)            # Beta(1,1)
    lo, hi = min(rate.values()), max(rate.values())
    table = {u: {d: {f: round(0.35 + 0.65 * (rate[(u, d, f)] - lo) / (hi - lo), 4) for f in FAMILIES}
                 for d in DEPTHS} for u in UNDERTONES}

    y = te['label'].to_numpy()
    learned = np.array([rate[(u, d, f)] for u, d, f in zip(te['undertone'], te['depth'], te['family'])])
    theory = np.array([theory_tone(u, d, f) for u, d, f in zip(te['undertone'], te['depth'], te['family'])])
    base = np.full(len(te), tr['label'].mean())
    metrics = {
        'train_rows_synthetic': int(len(tr)), 'train_rows_real': int(n_real), 'test_rows': int(len(te)),
        'auc_learned': round(_auc(y, learned), 4), 'auc_theory_only': round(_auc(y, theory), 4),
        'auc_global_mean': 0.5,
        'logloss_learned': round(_logloss(y, learned), 4), 'logloss_global_mean': round(_logloss(y, base), 4),
    }
    return {'source': 'trained:synthetic' + ('+feedback' if n_real else ''), 'table': table}, metrics


# ---------------------------------------------------------------------------
# 2. Keserasian pasangan warna (matching baju)
# ---------------------------------------------------------------------------
def train_color_pair(pairs=None, prior_strength=20.0, seed=3):
    """pairs: DataFrame kolom family_a, family_b, label (1 = dipakai bersama dalam
    outfit nyata, 0 = pasangan acak). Tanpa data -> prior teori roda warna."""
    prior = theory_pair_matrix()
    if pairs is None or len(pairs) < 200:
        return ({'source': 'prior:theory', 'matrix': prior},
                {'rows': 0, 'note': 'Belum ada data outfit nyata; memakai aturan roda warna.'})
    rng = np.random.default_rng(seed)
    idx = rng.permutation(len(pairs))
    cut = int(len(pairs) * 0.8)
    tr, te = pairs.iloc[idx[:cut]], pairs.iloc[idx[cut:]]
    pos = {(a, b): 0.0 for a in FAMILIES for b in FAMILIES}
    tot = {(a, b): 0.0 for a in FAMILIES for b in FAMILIES}
    for a, b, l in zip(tr['family_a'], tr['family_b'], tr['label']):
        for k in ((a, b), (b, a)):
            pos[k] += l
            tot[k] += 1
    mat = {}
    for a in FAMILIES:
        mat[a] = {}
        for b in FAMILIES:
            p0 = prior[a][b]
            mat[a][b] = round((prior_strength * p0 + pos[(a, b)]) / (prior_strength + tot[(a, b)]), 4)
    y = te['label'].to_numpy()
    s_learn = np.array([mat[a][b] for a, b in zip(te['family_a'], te['family_b'])])
    s_theory = np.array([prior[a][b] for a, b in zip(te['family_a'], te['family_b'])])
    return ({'source': 'trained:real', 'matrix': mat},
            {'rows': int(len(pairs)), 'auc_learned': round(_auc(y, s_learn), 4),
             'auc_theory_only': round(_auc(y, s_theory), 4)})


# ---------------------------------------------------------------------------
# 3. Prior warna pasar dari katalog Kaggle "Fashion Product Images" (styles.csv)
# ---------------------------------------------------------------------------
def color_market_prior(styles_csv):
    df = pd.read_csv(styles_csv, on_bad_lines='skip')
    df = df[df['masterCategory'].isin(['Apparel', 'Accessories', 'Footwear'])]
    df['family'] = df['baseColour'].astype(str).str.lower().map(KAGGLE_COLOR_TO_FAMILY)
    df = df.dropna(subset=['family', 'gender'])
    out = {}
    for gender, key in (('Women', 'female'), ('Men', 'male')):
        sub = df[df['gender'] == gender]
        if len(sub) < 100:
            continue
        share = sub['family'].value_counts(normalize=True)
        mx = float(share.max())
        out[key] = {f: round(0.35 + 0.30 * float(share.get(f, 0.0)) / mx, 4) for f in FAMILIES}
    usage = {}
    for (u, f), n in df.groupby([df['usage'].astype(str).str.lower(), 'family']).size().items():
        usage.setdefault(u, {})[f] = int(n)
    return {'source': 'trained:real', 'affinity_by_gender': out, 'rows': int(len(df)), 'usage_counts': usage}, \
           {'rows': int(len(df)), 'genders': list(out)}


# ---------------------------------------------------------------------------
# 4. Bentuk wajah dari foto dataset (Kaggle Face Shape)
# ---------------------------------------------------------------------------
def extract_face_features(folder, limit_per_class=None):
    """Struktur: folder/<Kelas>/*.jpg (Heart, Oblong, Oval, Round, Square)."""
    rows, skipped = [], 0
    for cls_dir in sorted(Path(folder).iterdir()):
        if not cls_dir.is_dir() or cls_dir.name.lower() not in faceport.FACE_LABELS:
            continue
        files = sorted(p for p in cls_dir.iterdir() if p.suffix.lower() in ('.jpg', '.jpeg', '.png'))
        if limit_per_class:
            files = files[:limit_per_class]
        for p in files:
            try:
                f = faceport.analyze_rgb(faceport.load_rgb(p))
            except Exception:
                f = None
            if f is None:
                skipped += 1
                continue
            rows.append({'label': cls_dir.name.lower(), 'file': str(p), **f})
    return pd.DataFrame(rows), skipped


def train_face_shape(df, seed=1):
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import train_test_split
    X = df[faceport.FEATURES].to_numpy(dtype=float)
    y = df['label'].to_numpy()
    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=seed, stratify=y)
    mean, std = Xtr.mean(0), Xtr.std(0) + 1e-9
    clf = LogisticRegression(max_iter=2000, C=2.0)
    clf.fit((Xtr - mean) / std, ytr)
    pred = clf.predict((Xte - mean) / std)
    labels = list(clf.classes_)
    rule_pred = np.array([faceport.rule_classify(*r) for r in Xte])
    cm = pd.crosstab(pd.Series(yte, name='asli'), pd.Series(pred, name='prediksi')).to_dict()
    metrics = {'rows': int(len(df)), 'test_rows': int(len(yte)),
               'accuracy_learned': round(float((pred == yte).mean()), 4),
               'accuracy_rules_baseline': round(float((rule_pred == yte).mean()), 4),
               'per_class_count': {k: int(v) for k, v in pd.Series(y).value_counts().items()},
               'confusion': {k: {a: int(b) for a, b in v.items()} for k, v in cm.items()}}
    comp = {'source': 'trained:real', 'features': faceport.FEATURES, 'labels': labels,
            'mean': [round(float(v), 6) for v in mean], 'std': [round(float(v), 6) for v in std],
            'W': [[round(float(v), 6) for v in row] for row in clf.coef_],
            'b': [round(float(v), 6) for v in clf.intercept_]}
    return comp, metrics


# ---------------------------------------------------------------------------
# 5. Ambang kedalaman kulit (ITA) dari foto berlabel skala Monk (MST)
# ---------------------------------------------------------------------------
def extract_skin_features(csv_path, root=None):
    """CSV kolom: path,mst (1..10). Path relatif terhadap [root] atau folder CSV."""
    meta = pd.read_csv(csv_path)
    base = Path(root) if root else Path(csv_path).parent
    rows = []
    for p, m in zip(meta['path'], meta['mst']):
        try:
            f = faceport.analyze_rgb(faceport.load_rgb(base / p))
        except Exception:
            f = None
        if f is not None and int(m) in MST_GROUP:
            rows.append({'ita': f['ita'], 'mst': int(m), 'group': MST_GROUP[int(m)]})
    return pd.DataFrame(rows)


def train_skin_depth(df):
    """Cari dua ambang ITA (terang|sedang, sedang|gelap) yang memaksimalkan akurasi."""
    ita = df['ita'].to_numpy()
    grp = df['group'].map({'light': 0, 'medium': 1, 'deep': 2}).to_numpy()
    cands = np.quantile(ita, np.linspace(0.02, 0.98, 97))

    def acc(t_light, t_deep):
        pred = np.where(ita > t_light, 0, np.where(ita > t_deep, 1, 2))
        return float((pred == grp).mean())
    best = max(((acc(a, b), a, b) for a in cands for b in cands if a > b), key=lambda x: x[0])
    base_acc = acc(41.0, -5.0)
    return ({'source': 'trained:real', 'ita_light': round(float(best[1]), 3), 'ita_deep': round(float(best[2]), 3)},
            {'rows': int(len(df)), 'accuracy_learned': round(best[0], 4), 'accuracy_default_thresholds': round(base_acc, 4)})
