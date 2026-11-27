#!/usr/bin/env python3
"""Uji panel admin:  ADMIN_USER/ADMIN_PASSWORD diset di sini.  python3 test_admin.py"""
import json, os, tempfile, threading, unittest
from pathlib import Path
os.environ['ADMIN_USER'] = 'boss'
os.environ['ADMIN_PASSWORD'] = 'passwordkuat123'
import server
from test_server import call


class AdminTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.httpd = server.make_server('127.0.0.1', 0, Path(cls.tmp.name) / 'a.sqlite3')
        cls.base = 'http://127.0.0.1:%d' % cls.httpd.server_address[1]
        threading.Thread(target=cls.httpd.serve_forever, daemon=True).start()
        s, j = call(cls.base, 'POST', '/admin/api/login', {'username': 'boss', 'password': 'passwordkuat123'})
        assert s == 200, j
        cls.tok = j['token']

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()

    def a(self, m, p, b=None, t=None):
        return call(self.base, m, '/admin/api' + p, b, t or self.tok)

    def test_01_html_and_auth(self):
        import urllib.request
        r = urllib.request.urlopen(self.base + '/admin')
        self.assertIn('Control Panel', r.read().decode())
        self.assertEqual(self.a('GET', '/dashboard', t='bad')[0], 401)
        self.assertEqual(self.a('GET', '/dashboard')[0], 200)

    def test_02_product_crud(self):
        p = {'id': 'T-1', 'name': 'Kaos Uji', 'price': 99000, 'category': 'T-shirt', 'audience': 'Men',
             'sizes': 'S, M', 'colors': [0xff112233], 'color_names': ['Biru'], 'color_codes': ['01'], 'color_images': ['']}
        s, j = self.a('POST', '/products', p); self.assertEqual(s, 200, j)
        s, j = self.a('PUT', '/products/T-1', {**p, 'price': 89000}); self.assertEqual(s, 200, j)
        s, j = self.a('GET', '/products?q=Kaos+Uji'); self.assertEqual(j['total'], 1)
        self.assertEqual(j['items'][0]['price'], 89000)
        s, j = call(self.base, 'GET', '/api/products'); self.assertIn('T-1', json.dumps(j))
        self.assertEqual(self.a('DELETE', '/products/T-1')[0], 200)
        self.assertEqual(self.a('GET', '/products?q=Kaos+Uji')[1]['total'], 0)

    def test_03_content_crud(self):
        v = {'code': 'HEMAT10', 'title': 'Hemat', 'type': 'percent', 'value': 10, 'min_spend': 0,
             'expires_at': '2030-01-01T00:00:00', 'active': True}
        self.assertEqual(self.a('POST', '/vouchers', v)[0], 200)
        self.assertIn('HEMAT10', json.dumps(call(self.base, 'GET', '/api/vouchers')[1]))
        self.assertEqual(self.a('DELETE', '/vouchers/HEMAT10')[0], 200)
        n = {'id': 'test-news-1', 'title': 'Promo', 'category': 'promo', 'date': '2026-11-01T00:00:00', 'published': True}
        self.assertEqual(self.a('POST', '/news', n)[0], 200)
        self.assertEqual(self.a('POST', '/stores/import-seed')[0], 200)
        self.assertGreater(len(self.a('GET', '/stores')[1]['items']), 10)
        # Halaman data operasional tersedia dan hanya baca untuk panel.
        self.assertEqual(self.a('GET', '/data/variants')[0], 200)
        self.assertEqual(self.a('GET', '/data/orders')[0], 200)
        self.assertEqual(self.a('GET', '/data/addresses')[0], 200)
        self.assertEqual(self.a('GET', '/data/reviews')[0], 200)

    def test_03b_customer_data_tables(self):
        products = call(self.base, 'GET', '/api/products')[1]['products']
        pid = products[0]['id']
        user = {'name': 'Pelanggan Uji', 'email': 'customer@example.com', 'phone': '0812345678',
                'address': 'Jl. Integrasi 1', 'member_code': 'UNQTEST001', 'bonus_points': 200,
                'password': 'secret123'}
        status, auth = call(self.base, 'POST', '/api/auth/register', user)
        self.assertEqual(status, 201, auth)
        token = auth['token']
        snapshot = {
            'member': {'name': user['name'], 'phone': user['phone'], 'address': user['address'],
                       'member_code': user['member_code'], 'bonus_points': 200},
            'cart': [{'product_id': pid, 'size': 'M', 'quantity': 1}],
            'wishlist': [pid],
            'orders': [{'id': 'ORDER-ADMIN-1', 'createdAt': '2026-11-22T10:00:00',
                        'subtotal': 100000, 'paymentMethod': 'Transfer', 'recipient': user['name'],
                        'phone': user['phone'], 'address': user['address'], 'status': 'diproses',
                        'items': [{'productId': pid, 'name': products[0]['name'], 'price': 100000,
                                   'quantity': 1, 'size': 'M', 'colorValue': 123}]}],
            'activities': [{'id': 'ACT-ADMIN-1', 'type': 'register', 'title': 'Daftar member',
                            'points': 200, 'at': '2026-11-22T10:00:00'}],
            'reviews': [{'id': 'REV-ADMIN-1', 'productId': pid, 'author': user['name'],
                         'rating': 5, 'text': 'Bagus', 'at': '2026-11-22T10:00:00'}],
            'bonus_points': 200,
        }
        self.assertEqual(call(self.base, 'POST', '/api/member/sync', snapshot, token)[0], 200)
        self.assertEqual(call(self.base, 'PUT', '/api/profile',
                              {'profile': {'gender': 'male', 'heightCm': 170, 'weightKg': 60},
                               'model': {'v': 1}}, token)[0], 200)
        for table in ('orders','order-items','addresses','cart','wishlist','activities','points','reviews','profiles'):
            status, data = self.a('GET', '/data/' + table)
            self.assertEqual(status, 200, (table, data))
            self.assertGreater(data['total'], 0, table)
        self.assertEqual(self.a('GET', '/data/orders?q=customer@example.com')[1]['total'], 1)

    def test_04_roles_and_lockout(self):
        s, j = self.a('POST', '/admins', {'username': 'admin1', 'password': 'adminpass123', 'role': 'admin'}); self.assertEqual(s, 200, j)
        vt = call(self.base, 'POST', '/admin/api/login', {'username': 'admin1', 'password': 'adminpass123'})[1]['token']
        self.assertEqual(self.a('GET', '/products', t=vt)[0], 200)
        self.assertEqual(self.a('POST', '/news', {'id': 'x', 'title': 'x', 'date': '2026-11-23'}, t=vt)[0], 200)
        self.assertEqual(self.a('GET', '/admins', t=vt)[0], 403)
        for _ in range(6):
            s, _ = call(self.base, 'POST', '/admin/api/login', {'username': 'ghost', 'password': 'salahsalah'})
        self.assertEqual(s, 429)
        self.assertEqual(self.a('GET', '/audit')[0], 200)

    def test_05_model_upload_activate(self):
        model = json.loads((Path(__file__).parent.parent / 'assets/data/ml_model.json').read_text())
        s, j = self.a('POST', '/ml/models', {'model': {'schema': 99}}); self.assertGreaterEqual(s, 400)
        s, j = self.a('POST', '/ml/models', {'model': model, 'activate': True}); self.assertEqual(s, 200, j)
        s, j = call(self.base, 'GET', '/api/ml/model'); self.assertEqual(s, 200)
        self.assertEqual(j['model']['version'], model['version'])
        s, j = self.a('GET', '/ml/status'); self.assertEqual(s, 200, j)
        self.assertEqual(self.a('GET', '/ml/models')[1]['items'][0]['active'], True)

    def test_06_popularity_segment(self):
        s, j = call(self.base, 'GET', '/api/popularity?undertone=warm&depth=medium&gender=Men')
        self.assertEqual(s, 200, j)


if __name__ == '__main__':
    unittest.main(verbosity=1)
