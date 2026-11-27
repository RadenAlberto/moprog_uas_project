"""Pembuat siluet wajah SINTETIS - HANYA untuk uji asap (smoke test) jalur
ekstraksi foto -> fitur -> pelatihan. Bukan data pelatihan model yang dipakai
aplikasi (itu harus dari dataset foto asli, lihat DATASETS.md)."""
import random

from PIL import Image, ImageDraw

# profil lebar relatif terhadap lebar pipi pada t = 0, .22, .5, .78, .92, 1.0 (atas -> dagu)
PROFILES = {
    'oval':   [0.45, 0.80, 1.00, 0.82, 0.55, 0.0],
    'round':  [0.55, 0.92, 1.00, 0.93, 0.70, 0.0],
    'square': [0.70, 0.95, 1.00, 0.97, 0.80, 0.35],
    'heart':  [0.60, 1.00, 0.97, 0.62, 0.34, 0.0],
    'oblong': [0.55, 0.85, 1.00, 0.88, 0.62, 0.0],
}
ASPECT = {'oval': 1.25, 'round': 1.0, 'square': 1.12, 'heart': 1.22, 'oblong': 1.45}


def make_face(shape, rng, size=(300, 400)):
    w, h = size
    img = Image.new('RGB', size, (170, 200, 235))  # latar kebiruan (bukan kulit)
    d = ImageDraw.Draw(img)
    skin = (rng.randint(190, 235), rng.randint(140, 180), rng.randint(110, 150))
    cheek_w = rng.uniform(0.30, 0.38) * w
    face_h = 2 * cheek_w * ASPECT[shape] * rng.uniform(0.95, 1.05)
    top = h * 0.16
    cx = w / 2
    prof = PROFILES[shape]
    ts = [0, 0.22, 0.5, 0.78, 0.92, 1.0]
    left, right = [], []
    for t, p in zip(ts, prof):
        y = top + t * face_h
        hw = max(2.0, p * cheek_w * rng.uniform(0.97, 1.03))
        left.append((cx - hw, y))
        right.append((cx + hw, y))
    d.polygon(left + right[::-1], fill=skin)
    neck_w = cheek_w * 0.55
    d.rectangle([cx - neck_w, top + face_h * 0.95, cx + neck_w, h], fill=tuple(int(c * 0.95) for c in skin))
    return img


def make_dataset(per_class=40, seed=7):
    rng = random.Random(seed)
    for shape in PROFILES:
        for _ in range(per_class):
            yield shape, make_face(shape, rng)
