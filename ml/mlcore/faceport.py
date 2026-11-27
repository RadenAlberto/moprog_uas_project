"""Port Python dari lib/SERVICES/face_analyzer.dart (analyzeRgba).

Dipakai untuk mengekstrak fitur dari foto dataset (Kaggle) dengan ALGORITMA YANG
SAMA seperti di aplikasi, sehingga model yang dilatih di sini bekerja pada angka
yang sama dengan yang dihitung HP pengguna (tidak ada pergeseran distribusi)."""
import math

import numpy as np

from .colors import hue_degrees, ita_degrees, rgb_to_lab

FACE_LABELS = ['oval', 'round', 'square', 'heart', 'oblong']
FEATURES = ['lengthRatio', 'foreheadRatio', 'jawRatio', 'chinRatio', 'taperRatio']


def rule_classify(length, forehead, jaw, chin, taper):
    """Aturan bawaan aplikasi (classifyFaceShape) - dipakai sebagai pembanding."""
    if length >= 1.33:
        return 'oblong'
    if forehead >= 0.84 and taper <= 0.78:
        return 'heart'
    if jaw >= 0.93 and chin >= 0.70:
        return 'square'
    if length < 1.05:
        return 'round'
    return 'oval'


def _skin_mask(rgb):
    r = rgb[..., 0].astype(np.float64)
    g = rgb[..., 1].astype(np.float64)
    b = rgb[..., 2].astype(np.float64)
    y = 0.299 * r + 0.587 * g + 0.114 * b
    cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
    cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
    return (cb >= 77) & (cb <= 127) & (cr >= 133) & (cr <= 173) & (y >= 40) & (r > g) & (r > b * 0.9)


def load_rgb(path_or_image, target_width=240):
    from PIL import Image
    img = path_or_image if hasattr(path_or_image, 'convert') else Image.open(path_or_image)
    img = img.convert('RGB')
    w, h = img.size
    if w != target_width:
        img = img.resize((target_width, max(1, round(h * target_width / w))), Image.BILINEAR)
    return np.asarray(img)


def analyze_rgb(rgb):
    """Mengembalikan dict fitur, atau None bila wajah tidak terdeteksi."""
    height, width = rgb.shape[:2]
    if width < 40 or height < 40:
        return None
    x0, x1 = round(width * 0.15), round(width * 0.85)
    y0, y1 = round(height * 0.10), round(height * 0.84)

    full = _skin_mask(rgb)
    mask = np.zeros((height, width), dtype=bool)
    mask[y0:y1, x0:x1] = full[y0:y1, x0:x1]
    skin_count = int(mask.sum())
    window_area = (x1 - x0) * (y1 - y0)
    if skin_count < window_area * 0.06:
        return None
    xs = np.nonzero(mask)[1]
    cx = float(xs.sum()) / skin_count

    widths = np.zeros(height)
    for y in range(y0, y1):
        idx = np.nonzero(mask[y])[0]
        if idx.size == 0:
            continue
        # segmen kulit dengan celah <= 2 piksel digabung (sama dengan Dart)
        breaks = np.nonzero(np.diff(idx) > 3)[0]
        starts = np.concatenate(([idx[0]], idx[breaks + 1]))
        ends = np.concatenate((idx[breaks], [idx[-1]]))
        best_w, best_d = 0, math.inf
        for s, e in zip(starts, ends):
            d = 0.0 if s <= cx <= e else min(abs(cx - s), abs(cx - e))
            rw = int(e - s + 1)
            if d < best_d or (d == best_d and rw > best_w):
                best_d, best_w = d, rw
        widths[y] = best_w

    sm = np.zeros(height)
    for y in range(y0, y1):
        lo, hi = max(y0, y - 2), min(y1 - 1, y + 2)
        sm[y] = widths[lo:hi + 1].mean()

    max_all = sm[y0:y1].max()
    if max_all < width * 0.12:
        return None
    top = y0
    for y in range(y0, y1):
        if sm[y] >= 0.40 * max_all:
            top = y
            break
    limit = min(y1, top + int(math.floor((y1 - top) * 0.7)))
    cheek = top
    for y in range(top, limit):
        if sm[y] > sm[cheek]:
            cheek = y
    max_w = sm[cheek]
    if max_w <= 0:
        return None

    stop, run_min = y1, sm[cheek]
    for y in range(cheek, y1):
        if sm[y] < 0.45 * max_w or sm[y] > run_min * 1.5 + 3:
            stop = y
            break
        run_min = min(run_min, sm[y])
    neck_w = max_w
    if stop - cheek >= 4:
        tail = sorted(sm[cheek + int(math.floor((stop - cheek) * 0.7)):stop])
        neck_w = tail[len(tail) // 2]
    bottom = stop - 1
    for y in range(cheek, stop):
        if sm[y] <= neck_w * 1.08 + 1.0:
            bottom = y
            break
    face_h = bottom - top
    if face_h < height * 0.18:
        return None

    def width_at_fraction(t):
        yy = round(top + t * face_h)
        lo, hi = max(y0, yy - 1), min(y1 - 1, yy + 1)
        return sm[lo:hi + 1].mean()

    def width_below_cheek(d):
        yy = min(y1 - 1, cheek + round(d * max_w))
        lo, hi = max(y0, yy - 1), min(y1 - 1, yy + 1)
        return sm[lo:hi + 1].mean()

    feats = {
        'lengthRatio': face_h / max_w,
        'foreheadRatio': width_at_fraction(0.22) / max_w,
        'jawRatio': width_at_fraction(0.78) / max_w,
        'chinRatio': width_at_fraction(0.92) / max_w,
        'taperRatio': width_below_cheek(0.35) / max_w,
    }

    row_a = round(top + 0.35 * face_h)
    row_b = round(top + 0.65 * face_h)
    half = round(0.28 * max_w)
    xa, xb = max(x0, round(cx - half)), min(x1 - 1, round(cx + half))
    px = []
    for y in range(row_a, min(row_b, y1 - 1) + 1):
        sel = np.nonzero(mask[y, xa:xb + 1])[0] + xa
        if sel.size:
            px.append(rgb[y, sel])
    if not px:
        return None
    px = np.concatenate(px)
    if len(px) < 30:
        return None
    r, g, b = (int(sorted(px[:, c].tolist())[len(px) // 2]) for c in range(3))
    lab = rgb_to_lab(r, g, b)
    feats.update({'skin_r': r, 'skin_g': g, 'skin_b': b, 'L': lab[0], 'ita': ita_degrees(lab),
                  'hue': hue_degrees(lab)})
    return feats
