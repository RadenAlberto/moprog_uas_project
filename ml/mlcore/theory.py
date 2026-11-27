"""Pengetahuan awal (PRIOR) dari teori analisis warna personal dan roda warna.

Ini BUKAN hasil pelatihan. Dipakai sebagai (1) generator data simulasi untuk
bootstrap dan (2) prior Bayes yang dikoreksi oleh data nyata. Setiap komponen di
model.json mencatat sumbernya, jadi terlihat mana yang dari teori dan mana yang
dari data."""
from .colors import FAMILIES

# Kecocokan warna pakaian dengan undertone kulit (0..1). Sama dengan tabel awal
# aplikasi (_warmTone/_coolTone/_neutralTone) agar perilaku awal tidak berubah.
TONE = {
    'warm': dict(black=.75, white=.85, grey=.65, blue=.6, teal=.55, purple=.45, pink=.5, red=.85, green=.9, earth=1.0),
    'cool': dict(black=.95, white=1.0, grey=.9, blue=1.0, teal=.85, purple=.95, pink=.85, red=.7, green=.6, earth=.45),
    'neutral': dict(black=.9, white=.9, grey=.9, blue=.9, teal=.85, purple=.8, pink=.8, red=.85, green=.85, earth=.9),
}
# Koreksi kedalaman kulit (kontras): kulit gelap cocok warna terang/jenuh, dst.
DEPTH_ADJ = {
    'deep': dict(white=.10, red=.06, pink=.06, blue=.06, teal=.06),
    'light': dict(grey=.05, blue=.05, pink=.05),
    'medium': {},
}


def theory_tone(undertone, depth, family):
    v = TONE[undertone][family] + DEPTH_ADJ[depth].get(family, 0.0)
    return max(0.0, min(1.0, v))


_NEUTRAL = {'black', 'white', 'grey', 'earth'}
_HUE = dict(red=0, earth=35, green=120, teal=185, blue=230, purple=290, pink=340)


def theory_pair(a, b):
    """Keserasian dua keluarga warna (0..1) dari aturan roda warna."""
    if a in _NEUTRAL and b in _NEUTRAL:
        return 0.8 if a != b else 0.72
    if a in _NEUTRAL or b in _NEUTRAL:
        return 0.88
    d = abs(_HUE[a] - _HUE[b])
    d = min(d, 360 - d)
    if d < 15:
        return 0.7
    if d <= 40:
        return 0.78
    if d >= 150:
        return 0.74
    if d >= 100:
        return 0.6
    return 0.3


def theory_pair_matrix():
    return {a: {b: round(theory_pair(a, b), 4) for b in FAMILIES} for a in FAMILIES}
