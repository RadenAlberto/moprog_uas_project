"""Uji pipeline ML: python -m unittest discover -s ml/tests  (atau jalankan berkas ini)."""
import json
import random
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from mlcore import colors, faceport, learn, pipeline, synth, synthfaces  # noqa: E402


class ColorTests(unittest.TestCase):
    def test_family_matches_dart_rules(self):
        self.assertEqual(colors.family_of_rgb(0, 0, 0), 'black')
        self.assertEqual(colors.family_of_rgb(255, 255, 255), 'white')
        self.assertEqual(colors.family_of_rgb(128, 128, 128), 'grey')
        self.assertEqual(colors.family_of_rgb(200, 30, 30), 'red')
        self.assertEqual(colors.family_of_rgb(30, 60, 200), 'blue')

    def test_lab_white_black(self):
        self.assertAlmostEqual(colors.rgb_to_lab(255, 255, 255)[0], 100, delta=0.1)
        self.assertAlmostEqual(colors.rgb_to_lab(0, 0, 0)[0], 0, delta=0.1)


class ToneColorTests(unittest.TestCase):
    def test_learning_is_better_than_global_mean_and_table_complete(self):
        df = synth.simulate_interactions(n_users=1500, seed=2)
        comp, met = learn.train_tone_color(df)
        self.assertGreater(met['auc_learned'], 0.6)
        self.assertLess(met['logloss_learned'], met['logloss_global_mean'])
        t = comp['table']
        self.assertEqual(set(t), {'warm', 'cool', 'neutral'})
        self.assertEqual(len(t['warm']['light']), 10)
        vals = [v for u in t.values() for d in u.values() for v in d.values()]
        self.assertTrue(all(0.35 <= v <= 1.0 for v in vals))

    def test_real_feedback_shifts_table(self):
        import pandas as pd
        df = synth.simulate_interactions(n_users=800, seed=3)
        base, _ = learn.train_tone_color(df)
        # pengguna nyata: warm+medium selalu menyukai 'purple'
        rows = [(i, 'female', 'warm', 'medium', 'purple', 1, 'real') for i in range(3000)]
        real = pd.DataFrame(rows, columns=['user_id', 'gender', 'undertone', 'depth', 'family', 'label', 'source'])
        shifted, met = learn.train_tone_color(df, real)
        self.assertEqual(met['train_rows_real'], 3000)
        self.assertGreater(shifted['table']['warm']['medium']['purple'], base['table']['warm']['medium']['purple'])
        self.assertTrue(shifted['source'].endswith('+feedback'))


class ColorPairTests(unittest.TestCase):
    def test_no_data_uses_theory_and_is_labelled(self):
        comp, _ = learn.train_color_pair(None)
        self.assertEqual(comp['source'], 'prior:theory')

    def test_learns_from_pairs(self):
        import pandas as pd
        rng = random.Random(0)
        rows = []
        for _ in range(1500):                       # dunia nyata: biru+putih sering, merah+hijau tidak
            rows.append(('blue', 'white', 1))
            rows.append(('red', 'green', 0))
        rows += [(rng.choice(colors.FAMILIES), rng.choice(colors.FAMILIES), rng.randint(0, 1)) for _ in range(500)]
        comp, met = learn.train_color_pair(pd.DataFrame(rows, columns=['family_a', 'family_b', 'label']))
        self.assertEqual(comp['source'], 'trained:real')
        m = comp['matrix']
        self.assertGreater(m['blue']['white'], m['red']['green'])


class FacePipelineTests(unittest.TestCase):
    """Jalur foto -> fitur -> pelatihan, diuji dengan siluet sintetis (BUKAN data model)."""

    def test_extract_train_and_export(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            for shape, img in synthfaces.make_dataset(per_class=30, seed=4):
                d = tmp / 'faces' / shape.capitalize()
                d.mkdir(parents=True, exist_ok=True)
                img.save(d / f'{random.random()}.png')
            model = pipeline.run(tmp / 'out', faces=tmp / 'faces', n_users=300)
            self.assertIn('face_shape', model['components'])
            fs = model['components']['face_shape']
            self.assertEqual(sorted(fs['labels']), sorted(faceport.FACE_LABELS))
            self.assertEqual(len(fs['W']), 5)
            self.assertEqual(len(fs['W'][0]), 5)
            self.assertGreater(model['metrics']['face_shape']['accuracy_learned'], 0.5)
            self.assertTrue((tmp / 'out' / 'model.json').exists())
            self.assertIn('face-shape', {d['id'] for d in model['datasets']})
            json.loads((tmp / 'out' / 'model.json').read_text(encoding='utf8'))


class MarketPriorTests(unittest.TestCase):
    def test_styles_csv(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'styles.csv'
            lines = ['id,gender,masterCategory,subCategory,articleType,baseColour,season,year,usage,productDisplayName']
            for i in range(300):
                lines.append(f'{i},Men,Apparel,Topwear,Shirts,{"Navy Blue" if i % 3 else "Black"},Fall,2011,Casual,x')
                lines.append(f'{i+1000},Women,Apparel,Topwear,Tops,{"Pink" if i % 2 else "White"},Summer,2012,Casual,y')
            p.write_text('\n'.join(lines), encoding='utf8')
            comp, met = learn.color_market_prior(p)
            self.assertEqual(set(comp['affinity_by_gender']), {'male', 'female'})
            self.assertEqual(comp['affinity_by_gender']['male']['blue'], 0.65)


class SkinDepthTests(unittest.TestCase):
    def test_thresholds(self):
        import pandas as pd
        rng = random.Random(1)
        rows = []
        for _ in range(300):
            rows.append((rng.uniform(45, 70), 'light'))
            rows.append((rng.uniform(0, 35), 'medium'))
            rows.append((rng.uniform(-40, -12), 'deep'))
        comp, met = learn.train_skin_depth(pd.DataFrame(rows, columns=['ita', 'group']))
        self.assertGreater(comp['ita_light'], comp['ita_deep'])
        self.assertGreater(met['accuracy_learned'], 0.95)


if __name__ == '__main__':
    unittest.main()
