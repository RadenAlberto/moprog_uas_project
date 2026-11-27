#!/usr/bin/env python3
"""Uji otomatis server UNIQLO PLUS:  python3 test_server.py"""
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

import server


def call(base, method, path, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(base + path, data=data, method=method)
    if body is not None:
        request.add_header('Content-Type', 'application/json')
    if token:
        request.add_header('Authorization', 'Bearer ' + token)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, json.loads(response.read() or b'{}')
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read() or b'{}')


PID_A, PID_B = 'E495975-000', 'E494895-000'


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.httpd = server.make_server('127.0.0.1', 0, Path(cls.tmp.name) / 't.sqlite3')
        cls.base = 'http://127.0.0.1:%d' % cls.httpd.server_address[1]
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.tmp.cleanup()

    def test_01_health_and_products(self):
        self.assertEqual(call(self.base, 'GET', '/api/health')[1]['status'], 'ok')
        status, body = call(self.base, 'GET', '/api/products')
        self.assertEqual(status, 200)
        self.assertEqual(len(body['products']), 1376)
        first = body['products'][0]
        for key in ('id', 'name', 'price', 'sizes', 'colors', 'category',
                    'audience', 'color_names', 'color_images', 'gallery', 'url'):
            self.assertIn(key, first)
        # Setiap warna punya nama dan foto sendiri.
        for p in body['products']:
            self.assertEqual(len(p['colors']), len(p['color_names']))
            self.assertEqual(len(p['colors']), len(p['color_images']))
            self.assertTrue(all(i.startswith('https://') for i in p['color_images']))
            self.assertTrue(p['sizes'])
        # Contoh nyata dari data Uniqlo: celana capri denim, 2 warna x 8 ukuran.
        capri = next(p for p in body['products'] if p['id'] == 'E495975-000')
        self.assertEqual(capri['price'], 599000)
        self.assertEqual(capri['color_names'], ['Biru Navy', 'Hitam'])
        self.assertIn('idgoods_69_495975', capri['color_images'][0])
        self.assertIn('idgoods_09_495975', capri['color_images'][1])
        self.assertEqual(len(capri['sizes']), 8)

    def test_01b_variants_table(self):
        import sqlite3
        with sqlite3.connect(str(Path(self.tmp.name) / 't.sqlite3')) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM product_variants').fetchone()[0], 16775)
            row = db.execute(
                "SELECT color_name, size, price, image FROM product_variants"
                " WHERE product_id='E495975-000' AND color_code='09' AND size='26inch'"
            ).fetchone()
            self.assertEqual(row[:3], ('Hitam', '26inch', 599000))
            self.assertIn('idgoods_09_495975', row[3])
            sale = db.execute(
                'SELECT price, original_price FROM products WHERE original_price IS NOT NULL LIMIT 1'
            ).fetchone()
            self.assertLess(sale[0], sale[1])

    def test_02_register_login_profile_feedback(self):
        user = {'name': 'Tester', 'email': 'T@Example.com', 'phone': '08', 'address': 'Jl. Contoh 1', 'member_code': 'UNQ12345678', 'bonus_points': 25, 'password': 'secret1'}
        status, body = call(self.base, 'POST', '/api/auth/register', user)
        self.assertEqual(status, 201)
        token = body['token']
        self.assertEqual(body['user']['email'], 't@example.com')
        self.assertEqual(body['user']['address'], 'Jl. Contoh 1')
        self.assertEqual(body['user']['member_code'], 'UNQ12345678')
        self.assertEqual(body['user']['bonus_points'], 200)  # bonus ditentukan server

        self.assertEqual(call(self.base, 'POST', '/api/auth/register', user)[0], 409)
        self.assertEqual(call(self.base, 'POST', '/api/auth/register',
                              {'name': 'x', 'email': 'bad', 'password': '1'})[0], 400)
        self.assertEqual(call(self.base, 'POST', '/api/auth/login',
                              {'email': 't@example.com', 'password': 'salah'})[0], 401)
        status, body = call(self.base, 'POST', '/api/auth/login',
                            {'email': 't@example.com', 'password': 'secret1'})
        self.assertEqual(status, 200)
        token = body['token']

        self.assertEqual(call(self.base, 'GET', '/api/me')[0], 401)
        self.assertEqual(call(self.base, 'GET', '/api/me', token=token)[1]['user']['name'], 'Tester')
        status, updated = call(self.base, 'PUT', '/api/me',
                               {'phone': '081234', 'address': 'Alamat Baru', 'bonus_points': 30,
                                'last_check_in_day': '2026-11-22', 'check_in_streak': 2}, token)
        self.assertEqual(status, 200)
        self.assertEqual(updated['user']['phone'], '081234')
        self.assertEqual(updated['user']['address'], 'Alamat Baru')
        self.assertEqual(updated['user']['bonus_points'], 200)  # tidak dapat dimanipulasi melalui PUT /api/me
        self.assertEqual(updated['user']['check_in_streak'], 0)

        checkin_status, checkin = call(self.base, 'POST', '/api/points/checkin', {}, token)
        self.assertEqual(checkin_status, 200, checkin)
        self.assertGreaterEqual(checkin['reward'], 5)
        self.assertEqual(call(self.base, 'POST', '/api/points/checkin', {}, token)[0], 409)
        self.assertIsNone(call(self.base, 'GET', '/api/profile', token=token)[1]['profile'])
        profile = {'gender': 'male', 'heightCm': 170, 'weightKg': 60}
        model = {'v': 1, 'w': [1.0] * 11}
        self.assertEqual(call(self.base, 'PUT', '/api/profile',
                              {'profile': profile, 'model': model}, token)[0], 200)
        saved = call(self.base, 'GET', '/api/profile', token=token)[1]
        self.assertEqual(saved['profile'], profile)
        self.assertEqual(saved['model'], model)
        self.assertEqual(call(self.base, 'PUT', '/api/profile', {'profile': 1}, token)[0], 400)

        self.assertEqual(call(self.base, 'POST', '/api/feedback',
                              {'product_id': PID_A, 'action': 'like'}, token)[0], 201)
        self.assertEqual(call(self.base, 'POST', '/api/feedback',
                              {'product_id': PID_A, 'action': 'cart'}, token)[0], 201)
        self.assertEqual(call(self.base, 'POST', '/api/feedback',
                              {'product_id': PID_B, 'action': 'dislike'}, token)[0], 201)
        self.assertEqual(call(self.base, 'POST', '/api/feedback',
                              {'product_id': '999', 'action': 'like'}, token)[0], 404)
        self.assertEqual(call(self.base, 'POST', '/api/feedback',
                              {'product_id': PID_A, 'action': 'x'}, token)[0], 400)
        self.assertEqual(call(self.base, 'POST', '/api/feedback',
                              {'product_id': PID_A, 'action': 'like'})[0], 401)

        snapshot = {
            'cart': [{'product_id': PID_A, 'color_code': '4278190080', 'size': 'M', 'quantity': 2, 'is_selected': True}],
            'wishlist': [PID_A],
            'orders': [{'id': 'ORDER-1', 'createdAt': '2026-11-22T10:00:00', 'subtotal': 100000,
                        'paymentMethod': 'Transfer', 'recipient': 'Tester', 'phone': '0812',
                        'address': 'Jl. Contoh', 'items': [{'productId': PID_A, 'name': 'Produk Uji',
                        'image': '', 'price': 100000, 'size': 'M', 'colorValue': 123, 'quantity': 1}]}],
            'activities': [{'id': 'ACT-1', 'type': 'order', 'title': 'Pesanan dibuat',
                            'detail': 'Uji', 'points': 10, 'at': '2026-11-22T10:00:00'}],
            'bonus_points': 30,
            'member': {'name': 'Tester Updated', 'phone': '0812', 'address': 'Jl. Baru', 'member_code': 'UNQ12345678', 'bonus_points': 30},
            'reviews': [{'id': 'REV-1', 'productId': PID_A, 'author': 'Tester', 'rating': 5, 'text': 'Bagus', 'at': '2026-11-22T10:00:00'}],
        }
        self.assertEqual(call(self.base, 'POST', '/api/member/sync', snapshot, token)[0], 200)
        import sqlite3
        with sqlite3.connect(str(Path(self.tmp.name) / 't.sqlite3')) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM cart_items').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM wishlist').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM orders').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM order_items').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM addresses').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM member_activities').fetchone()[0], 2)
            self.assertEqual(db.execute('SELECT bonus_points FROM users').fetchone()[0], 200)
            self.assertEqual(db.execute('SELECT name FROM users').fetchone()[0], 'Tester Updated')
            self.assertEqual(db.execute('SELECT address FROM addresses WHERE user_id=(SELECT id FROM users LIMIT 1) AND is_default=1').fetchone()[0], 'Jl. Baru')
            self.assertEqual(db.execute('SELECT COUNT(*) FROM reviews').fetchone()[0], 1)

        # Mengirim snapshot yang sama berulang kali tidak menggandakan alamat,
        # pesanan, item pesanan, aktivitas, poin, atau ulasan.
        self.assertEqual(call(self.base, 'POST', '/api/member/sync', snapshot, token)[0], 200)
        with sqlite3.connect(str(Path(self.tmp.name) / 't.sqlite3')) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM addresses').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM orders').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM order_items').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM member_activities').fetchone()[0], 2)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM reviews').fetchone()[0], 1)

        popularity = call(self.base, 'GET', '/api/popularity')[1]['popularity']
        self.assertEqual(popularity[PID_A], 1.0)
        self.assertEqual(popularity[PID_B], 0.0)
        products = call(self.base, 'GET', '/api/products')[1]['products']
        self.assertEqual(next(p for p in products if p['id'] == PID_A)['popularity'], 1.0)

    def test_02b_seeded_public_content(self):
        vouchers = call(self.base, 'GET', '/api/vouchers')[1]['vouchers']
        news = call(self.base, 'GET', '/api/news')[1]['news']
        stores = call(self.base, 'GET', '/api/stores')[1]['stores']
        self.assertEqual(len(vouchers), 4)
        self.assertEqual(len(news), 9)
        self.assertEqual(len(stores), 82)

    def test_03_unknown_route(self):
        self.assertEqual(call(self.base, 'GET', '/api/nope')[0], 404)


if __name__ == '__main__':
    unittest.main(verbosity=2)
