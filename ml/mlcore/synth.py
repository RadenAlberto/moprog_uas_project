"""Simulator pengguna SINTETIS untuk bootstrap (cold start).

Dipakai hanya agar model punya titik awal yang masuk akal sebelum ada data nyata.
Perilaku disimulasikan dari teori analisis warna (theory.py) ditambah selera
individu acak, sehingga tiap pengguna virtual berbeda. Semua baris ditandai
source='synthetic' dan DIPISAHKAN dari data nyata di laporan."""
import math

import numpy as np
import pandas as pd

from .colors import DEPTHS, FAMILIES, UNDERTONES
from .theory import theory_tone


def simulate_interactions(n_users=4000, per_user=30, seed=11, sharpness=5.0):
    rng = np.random.default_rng(seed)
    rows = []
    for uid in range(n_users):
        u = UNDERTONES[rng.integers(3)]
        d = DEPTHS[rng.integers(3)]
        gender = 'female' if rng.random() < 0.5 else 'male'
        taste = rng.normal(0, 0.55, len(FAMILIES))   # selera pribadi tiap pengguna
        bias = rng.normal(0, 0.4)
        for f_i in rng.integers(0, len(FAMILIES), per_user):
            fam = FAMILIES[f_i]
            z = sharpness * (theory_tone(u, d, fam) - 0.62) + taste[f_i] + bias
            p = 1 / (1 + math.exp(-z))
            rows.append((uid, gender, u, d, fam, int(rng.random() < p)))
    df = pd.DataFrame(rows, columns=['user_id', 'gender', 'undertone', 'depth', 'family', 'label'])
    df['source'] = 'synthetic'
    return df
