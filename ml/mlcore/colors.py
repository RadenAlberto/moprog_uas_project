"""Utilitas warna. Logikanya SAMA dengan lib/SERVICES/product_attributes.dart
(colorFamilyOf) dan lib/SERVICES/face_analyzer.dart (rgbToLab) supaya fitur yang
dilatih di Python identik dengan yang dihitung aplikasi."""
import colorsys
import math

FAMILIES = ['black', 'white', 'grey', 'blue', 'teal', 'purple', 'pink', 'red', 'green', 'earth']
UNDERTONES = ['warm', 'cool', 'neutral']
DEPTHS = ['light', 'medium', 'deep']

# Skala Monk Skin Tone (10 tingkat) dan pengelompokannya (sumber: skintone.google).
# Kelompok: terang 1-3, sedang 4-6, gelap 7-10.
MST_GROUP = {1: 'light', 2: 'light', 3: 'light', 4: 'medium', 5: 'medium', 6: 'medium',
             7: 'deep', 8: 'deep', 9: 'deep', 10: 'deep'}


def family_of_rgb(r, g, b):
    """Sama dengan colorFamilyOf() di Dart (HSL)."""
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    h *= 360.0
    if l < 0.14:
        return 'black'
    if l > 0.92 and s < 0.25:
        return 'white'
    if s < 0.12:
        return 'grey'
    if h < 12 or h >= 345:
        return 'red'
    if h < 70:
        return 'earth'
    if h < 170:
        return 'green'
    if h < 200:
        return 'teal'
    if h < 262:
        return 'blue'
    if h < 330:
        return 'purple'
    return 'pink'


def family_of_argb(argb):
    return family_of_rgb((argb >> 16) & 255, (argb >> 8) & 255, argb & 255)


def rgb_to_lab(r, g, b):
    """sRGB (0..255) -> CIE Lab D65. Sama dengan rgbToLab() di Dart."""
    def lin(v):
        c = v / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    rl, gl, bl = lin(r), lin(g), lin(b)
    x = (0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl) / 0.95047
    y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl
    z = (0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def ita_degrees(lab):
    return math.degrees(math.atan2(lab[0] - 50, lab[2]))


def hue_degrees(lab):
    return math.degrees(math.atan2(lab[2], lab[1]))


# Nama warna dataset Kaggle "Fashion Product Images" -> keluarga warna aplikasi.
KAGGLE_COLOR_TO_FAMILY = {
    'black': 'black', 'charcoal': 'black', 'white': 'white', 'off white': 'white', 'cream': 'earth',
    'grey': 'grey', 'grey melange': 'grey', 'silver': 'grey', 'steel': 'grey',
    'blue': 'blue', 'navy blue': 'blue', 'turquoise blue': 'teal', 'teal': 'teal', 'sea green': 'teal',
    'purple': 'purple', 'lavender': 'purple', 'mauve': 'purple', 'violet': 'purple',
    'pink': 'pink', 'magenta': 'pink', 'rose': 'pink', 'peach': 'pink',
    'red': 'red', 'maroon': 'red', 'burgundy': 'red', 'rust': 'red', 'coral': 'red',
    'green': 'green', 'olive': 'green', 'lime green': 'green', 'fluorescent green': 'green',
    'khaki': 'earth', 'beige': 'earth', 'brown': 'earth', 'tan': 'earth', 'coffee brown': 'earth',
    'mustard': 'earth', 'yellow': 'earth', 'orange': 'earth', 'gold': 'earth', 'bronze': 'earth',
    'copper': 'earth', 'nude': 'earth', 'taupe': 'earth', 'skin': 'earth', 'mushroom brown': 'earth',
}
