#!/usr/bin/env python3
"""Server UNIQLO PLUS (Python murni, tanpa library tambahan).

Menyediakan database SQLite untuk:
  * produk            -> katalog yang diambil aplikasi lewat internet
  * users + tokens    -> akun member (password di-hash PBKDF2-SHA256 + salt)
  * style_profiles    -> hasil analisis gaya (tinggi, berat, bentuk wajah, nada kulit)
                         dan bobot model ML personal milik tiap member
  * feedback          -> suka / tidak cocok / keranjang / lihat produk dari semua
                         pengguna; dipakai menghitung popularitas produk

Jalankan:   python3 server.py                (port 8000)
            python3 server.py --port 9000 --db data.sqlite3

Endpoint (JSON):
  GET  /api/health
  GET  /api/products
  POST /api/auth/register   {name,email,phone,password}
  POST /api/auth/login      {email,password}
  GET  /api/me                              (Authorization: Bearer <token>)
  GET  /api/profile                         (Bearer)
  PUT  /api/profile         {profile,model} (Bearer)
  POST /api/feedback        {product_id,action} (Bearer)
  GET  /api/popularity[?undertone=&depth=&gender=]   (per segmen pengguna mirip)
  GET  /api/ml/model        model ML aktif (kontrol panel) atau bawaan
  GET  /api/vouchers, /api/news, /api/stores   konten yang dikelola di panel admin
  /admin                    CONTROL PANEL (web)  -> lihat backend/README.md
"""
import argparse
from contextlib import contextmanager
import hashlib
import hmac
import json
import os
import queue
import re
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import admin as admin_panel
import feature_extensions

_SSE_SUBSCRIBERS = set()

def broadcast_admin_event(event_type, payload):
    """Broadcast an SSE event to all connected admin clients in real-time."""
    msg = f"event: {event_type}\ndata: {json.dumps(payload, ensure_ascii=False)}\n\n".encode('utf-8')
    dead = set()
    for q in list(_SSE_SUBSCRIBERS):
        try:
            q.put_nowait(msg)
        except Exception:
            dead.add(q)
    for q in dead:
        _SSE_SUBSCRIBERS.discard(q)

HERE = Path(__file__).resolve().parent
SEED = HERE / 'products_seed.json'
MAX_BODY = 1_000_000
# Naikkan bila skema/seed produk berubah: tabel produk dibuat ulang otomatis.
CATALOG_VERSION = 2
TOKEN_TTL = 60 * 60 * 24 * 30  # 30 hari
ACTIONS = {'like': 1.0, 'dislike': -1.0, 'cart': 2.0, 'view': 0.2}
EMAIL_RE = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')

SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  price REAL NOT NULL,
  original_price REAL,
  image TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL,
  audience TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  features TEXT NOT NULL DEFAULT '[]',
  is_new INTEGER NOT NULL DEFAULT 0,
  sizes TEXT NOT NULL DEFAULT '[]',
  colors TEXT NOT NULL DEFAULT '[]',
  color_names TEXT NOT NULL DEFAULT '[]',
  color_codes TEXT NOT NULL DEFAULT '[]',
  color_images TEXT NOT NULL DEFAULT '[]',
  gallery TEXT NOT NULL DEFAULT '[]',
  rating_average REAL NOT NULL DEFAULT 0,
  rating_count INTEGER NOT NULL DEFAULT 0,
  url TEXT NOT NULL DEFAULT ''
);
-- Satu baris per kombinasi warna x ukuran (sama dengan variants.csv Uniqlo).
CREATE TABLE IF NOT EXISTS product_variants (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  color_code TEXT NOT NULL,
  color_name TEXT NOT NULL,
  color_argb INTEGER NOT NULL,
  size TEXT NOT NULL,
  price REAL NOT NULL,
  original_price REAL,
  image TEXT NOT NULL DEFAULT '',
  UNIQUE(product_id, color_code, size)
);
CREATE INDEX IF NOT EXISTS idx_variants_product ON product_variants(product_id);
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  member_code TEXT NOT NULL DEFAULT '',
  bonus_points INTEGER NOT NULL DEFAULT 0,
  last_check_in_day TEXT,
  check_in_streak INTEGER NOT NULL DEFAULT 0,
  password_hash TEXT NOT NULL,
  salt TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS style_profiles (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  profile_json TEXT NOT NULL DEFAULT '{}',
  model_json TEXT NOT NULL DEFAULT '{}',
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_feedback_product ON feedback(product_id);
CREATE TABLE IF NOT EXISTS addresses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recipient_name TEXT NOT NULL,
  phone TEXT NOT NULL,
  address TEXT NOT NULL,
  city TEXT NOT NULL DEFAULT '',
  postal_code TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS wishlist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  UNIQUE(user_id, product_id)
);
CREATE TABLE IF NOT EXISTS cart_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  color_code TEXT NOT NULL DEFAULT '',
  size TEXT NOT NULL DEFAULT '',
  quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0),
  is_selected INTEGER NOT NULL DEFAULT 1,
  updated_at INTEGER NOT NULL,
  UNIQUE(user_id, product_id, color_code, size)
);
CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  address_id INTEGER REFERENCES addresses(id) ON DELETE SET NULL,
  order_date TEXT NOT NULL,
  subtotal REAL NOT NULL DEFAULT 0,
  total_price REAL NOT NULL,
  payment_method TEXT NOT NULL DEFAULT '',
  payment_status TEXT NOT NULL DEFAULT 'Pending',
  order_status TEXT NOT NULL DEFAULT 'Processing',
  order_json TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS order_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id TEXT REFERENCES products(id) ON DELETE SET NULL,
  product_name TEXT NOT NULL,
  image TEXT NOT NULL DEFAULT '',
  size TEXT NOT NULL DEFAULT '',
  color_value INTEGER,
  price REAL NOT NULL,
  quantity INTEGER NOT NULL,
  subtotal REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS member_activities (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL,
  title TEXT NOT NULL,
  detail TEXT NOT NULL DEFAULT '',
  points INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS member_points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  order_id TEXT REFERENCES orders(id) ON DELETE SET NULL,
  points_delta INTEGER NOT NULL,
  reason TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS reviews (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  author TEXT NOT NULL DEFAULT '',
  rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5),
  review_text TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_reviews_product ON reviews(product_id);
CREATE TABLE IF NOT EXISTS vouchers (
  code TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL, value REAL NOT NULL DEFAULT 0, max_discount REAL,
  min_spend REAL NOT NULL DEFAULT 0, member_only INTEGER NOT NULL DEFAULT 0,
  min_tier TEXT, expires_at TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS news (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '', image TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'info', date TEXT NOT NULL,
  is_pinned INTEGER NOT NULL DEFAULT 0, action TEXT NOT NULL DEFAULT 'none',
  action_label TEXT NOT NULL DEFAULT '', published INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS stores (
  id TEXT PRIMARY KEY, name TEXT NOT NULL, mall TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '', province TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '', lat REAL, lng REAL,
  open_hour INTEGER NOT NULL DEFAULT 10, close_hour INTEGER NOT NULL DEFAULT 22,
  services TEXT NOT NULL DEFAULT '[]'
);
"""


class Store:
    """Akses database. Satu koneksi per permintaan, ditulis serial dengan lock."""

    def __init__(self, path):
        self.path = str(path)
        self.lock = threading.Lock()
        with self.connect() as db:
            self._migrate(db)
            db.executescript(SCHEMA)
            self._ensure_user_columns(db)
            self._seed(db)
            self._seed_public_content(db)
            feature_extensions.migrate(db)
            feature_extensions.seed_sample_reviews(db)

    @staticmethod
    def _ensure_user_columns(db):
        """Migrasi additive agar database lama tidak kehilangan akun member."""
        existing = {row[1] for row in db.execute('PRAGMA table_info(users)')}
        additions = {
            'address': "TEXT NOT NULL DEFAULT ''",
            'member_code': "TEXT NOT NULL DEFAULT ''",
            'bonus_points': 'INTEGER NOT NULL DEFAULT 0',
            'last_check_in_day': 'TEXT',
            'check_in_streak': 'INTEGER NOT NULL DEFAULT 0',
        }
        for name, declaration in additions.items():
            if name not in existing:
                db.execute(f'ALTER TABLE users ADD COLUMN {name} {declaration}')

    @staticmethod
    def _migrate(db):
        """Katalog lama (50 produk contoh) diganti katalog Uniqlo.

        Tabel produk dibuat ulang; feedback lama ikut dibuang karena merujuk
        produk contoh yang sudah tidak ada. Akun & profil gaya tetap aman.
        """
        if db.execute('PRAGMA user_version').fetchone()[0] >= CATALOG_VERSION:
            return
        db.execute('PRAGMA foreign_keys = OFF')
        for table in ('feedback', 'product_variants', 'products'):
            db.execute('DROP TABLE IF EXISTS ' + table)
        db.execute('PRAGMA user_version = %d' % CATALOG_VERSION)
        db.commit()
        db.execute('PRAGMA foreign_keys = ON')

    @contextmanager
    def connect(self):
        """Buka koneksi SQLite dan selalu tutup setelah blok selesai.

        sqlite3.Connection sebagai context manager hanya menangani commit/
        rollback; ia tidak otomatis menutup koneksi. Karena koneksi dipakai
        pada banyak request, penutupan eksplisit mencegah kebocoran resource.
        """
        db = sqlite3.connect(self.path, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys = ON')
        try:
            with db:
                yield db
        finally:
            db.close()

    @staticmethod
    def _seed_public_content(db):
        """Importa conteúdo inicial somente quando cada tabela está vazia.

        Os registros são conteúdo demonstrativo editável pelo painel; nunca
        sobrescrevem conteúdo que o administrador já cadastrou.
        """
        seed_dir = HERE
        if db.execute('SELECT COUNT(*) FROM stores').fetchone()[0] == 0:
            path = seed_dir / 'stores_seed.json'
            if path.exists():
                try:
                    stores = json.loads(path.read_text(encoding='utf8')).get('stores', [])
                    for item in stores:
                        db.execute(
                            'INSERT OR IGNORE INTO stores '
                            '(id,name,mall,city,province,address,phone,lat,lng,open_hour,close_hour,services) '
                            'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
                            (item.get('id'), item.get('name'), item.get('mall',''), item.get('city',''),
                             item.get('province',''), item.get('address',''), item.get('phone',''),
                             item.get('lat'), item.get('lng'), item.get('open_hour',10),
                             item.get('close_hour',22), json.dumps(item.get('services', []), ensure_ascii=False)))
                except (ValueError, TypeError, sqlite3.Error) as exc:
                    print('[SEED] Gagal mengimpor toko:', exc)
        for table, filename, key in (('vouchers','vouchers_seed.json','vouchers'), ('news','news_seed.json','news')):
            if db.execute(f'SELECT COUNT(*) FROM {table}').fetchone()[0] != 0:
                continue
            path = seed_dir / filename
            if not path.exists():
                continue
            try:
                records = json.loads(path.read_text(encoding='utf8')).get(key, [])
                for item in records:
                    if table == 'vouchers':
                        db.execute('''INSERT OR IGNORE INTO vouchers
                            (code,title,description,type,value,max_discount,min_spend,member_only,min_tier,expires_at,active)
                            VALUES (?,?,?,?,?,?,?,?,?,?,?)''',
                            (item['code'],item['title'],item.get('description',''),item['type'],item.get('value',0),
                             item.get('max_discount'),item.get('min_spend',0),int(bool(item.get('member_only'))),
                             item.get('min_tier'),item['expires_at'],int(bool(item.get('active',True)))))
                    else:
                        db.execute('''INSERT OR IGNORE INTO news
                            (id,title,summary,content,image,category,date,is_pinned,action,action_label,published)
                            VALUES (?,?,?,?,?,?,?,?,?,?,?)''',
                            (item['id'],item['title'],item.get('summary',''),item.get('content',''),item.get('image',''),
                             item.get('category','info'),item['date'],int(bool(item.get('is_pinned'))),
                             item.get('action','none'),item.get('action_label',''),int(bool(item.get('published',True)))))
            except (ValueError, TypeError, KeyError, sqlite3.Error) as exc:
                print(f'[SEED] Gagal mengimpor {table}:', exc)
        db.commit()

    @staticmethod
    def _seed(db):
        if db.execute('SELECT COUNT(*) FROM products').fetchone()[0] > 0:
            return
        if not SEED.exists():
            return
        for p in json.loads(SEED.read_text(encoding='utf8')):
            dump = lambda key: json.dumps(p.get(key, []), ensure_ascii=False)
            db.execute(
                'INSERT OR IGNORE INTO products (id, name, price, original_price,'
                ' image, category, audience, description, features, is_new, sizes,'
                ' colors, color_names, color_codes, color_images, gallery,'
                ' rating_average, rating_count, url)'
                ' VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (
                    p['id'], p['name'], p['price'], p.get('original_price'),
                    p.get('image', ''), p['category'], p['audience'],
                    p.get('description', ''), dump('features'),
                    1 if p.get('is_new') else 0, dump('sizes'), dump('colors'),
                    dump('color_names'), dump('color_codes'),
                    dump('color_images'), dump('gallery'),
                    p.get('rating_average', 0), p.get('rating_count', 0),
                    p.get('url', ''),
                ),
            )
            variants = [
                (p['id'], code, p['color_names'][i], p['colors'][i], size,
                 p['price'], p.get('original_price'), p['color_images'][i])
                for i, code in enumerate(p.get('color_codes', []))
                for size in p.get('sizes', [])
            ]
            db.executemany(
                'INSERT OR IGNORE INTO product_variants (product_id, color_code,'
                ' color_name, color_argb, size, price, original_price, image)'
                ' VALUES (?,?,?,?,?,?,?,?)',
                variants,
            )
        db.commit()

    # -- produk & popularitas -------------------------------------------------

    def products(self):
        with self.connect() as db:
            rows = db.execute('SELECT * FROM products ORDER BY rowid').fetchall()
            popularity = self._popularity(db)
        out = []
        for r in rows:
            out.append({
                'id': r['id'], 'name': r['name'], 'price': r['price'],
                'original_price': r['original_price'], 'image': r['image'],
                'category': r['category'], 'audience': r['audience'],
                'description': r['description'],
                'features': json.loads(r['features']),
                'is_new': bool(r['is_new']),
                'sizes': json.loads(r['sizes']),
                'colors': json.loads(r['colors']),
                'color_names': json.loads(r['color_names']),
                'color_codes': json.loads(r['color_codes']),
                'color_images': json.loads(r['color_images']),
                'gallery': json.loads(r['gallery']),
                'rating_average': r['rating_average'],
                'rating_count': r['rating_count'],
                'url': r['url'],
                'popularity': popularity.get(r['id'], 0.0),
            })
        return out

    @staticmethod
    def _popularity(db):
        """Skor 0..1 per produk dari seluruh feedback pengguna."""
        scores = {}
        for r in db.execute('SELECT product_id, action, COUNT(*) AS n FROM feedback GROUP BY product_id, action'):
            scores[r['product_id']] = scores.get(r['product_id'], 0.0) + ACTIONS.get(r['action'], 0.0) * r['n']
        if not scores:
            return {}
        top = max(scores.values())
        if top <= 0:
            return {k: 0.0 for k in scores}
        return {k: round(max(0.0, v) / top, 4) for k, v in scores.items()}

    def popularity(self):
        with self.connect() as db:
            return self._popularity(db)

    def popularity_segment(self, undertone, depth, gender, min_rows=30):
        """Popularitas dari pengguna yang MIRIP (undertone + kedalaman kulit [+ gender]).

        Dipakai agar tiap pengguna mendapat tren yang berbeda sesuai segmennya.
        Bila data segmen belum cukup (< min_rows), kembali ke popularitas global."""
        with self.connect() as db:
            rows = db.execute(
                'SELECT f.product_id, f.action, s.profile_json FROM feedback f '
                'JOIN style_profiles s ON s.user_id=f.user_id').fetchall()
            scores, n = {}, 0
            for r in rows:
                try:
                    p = json.loads(r['profile_json'])
                except ValueError:
                    continue
                if undertone and p.get('undertone') != undertone:
                    continue
                if depth and p.get('depth') != depth:
                    continue
                if gender and p.get('gender') != gender:
                    continue
                n += 1
                scores[r['product_id']] = scores.get(r['product_id'], 0.0) + ACTIONS.get(r['action'], 0.0)
            if n < min_rows:
                return {'segment': None, 'rows': n, 'popularity': self._popularity(db)}
        top = max(scores.values()) if scores else 0
        pop = {k: round(max(0.0, v) / top, 4) for k, v in scores.items()} if top > 0 else {}
        return {'segment': {'undertone': undertone, 'depth': depth, 'gender': gender}, 'rows': n, 'popularity': pop}

    def public_content(self, table):
        """Konten yang dikelola admin (voucher/berita/toko) untuk aplikasi."""
        with self.connect() as db:
            if table == 'vouchers':
                rows = db.execute('SELECT * FROM vouchers WHERE active=1 ORDER BY code').fetchall()
                return [dict(r, member_only=bool(r['member_only']), active=True) for r in rows]
            if table == 'news':
                rows = db.execute('SELECT * FROM news WHERE published=1 ORDER BY is_pinned DESC, date DESC').fetchall()
                return [dict(r, is_pinned=bool(r['is_pinned']), published=True) for r in rows]
            rows = db.execute('SELECT * FROM stores ORDER BY province, city, name').fetchall()
            return [dict(r, services=json.loads(r['services'])) for r in rows]

    # -- akun -----------------------------------------------------------------

    @staticmethod
    def _hash(password, salt):
        return hashlib.pbkdf2_hmac('sha256', password.encode('utf8'), bytes.fromhex(salt), 120_000).hex()

    def _issue_token(self, db, user_id):
        token = secrets.token_urlsafe(32)
        db.execute('INSERT INTO tokens VALUES (?,?,?)', (token, user_id, int(time.time()) + TOKEN_TTL))
        db.execute('DELETE FROM tokens WHERE expires_at < ?', (int(time.time()),))
        return token

    @staticmethod
    def _user(row):
        return {
            'id': row['id'], 'member_code': row['member_code'],
            'name': row['name'], 'email': row['email'], 'phone': row['phone'],
            'address': row['address'], 'bonus_points': row['bonus_points'],
            'last_check_in_day': row['last_check_in_day'],
            'check_in_streak': row['check_in_streak'],
            'created_at': row['created_at'],
        }

    @staticmethod
    def _ensure_member_address(db, user_id, name, phone, address):
        address = str(address or '').strip()
        if not address:
            return None
        row = db.execute('SELECT id FROM addresses WHERE user_id=? AND recipient_name=? AND phone=? AND address=? ORDER BY id LIMIT 1',
                         (user_id, str(name or 'Member'), str(phone or ''), address)).fetchone()
        db.execute('UPDATE addresses SET is_default=0 WHERE user_id=?',(user_id,))
        if row:
            db.execute('UPDATE addresses SET is_default=1 WHERE id=?',(row['id'],))
            return row['id']
        cur = db.execute('INSERT INTO addresses (user_id,recipient_name,phone,address,city,postal_code,created_at,label,is_default) VALUES (?,?,?,?,?,?,?,?,1)',
                         (user_id, str(name or 'Member'), str(phone or ''), address, '', '', int(time.time()), 'Rumah'))
        return cur.lastrowid

    def register(self, name, email, phone, password, address='', member_code='', bonus_points=0):
        salt = secrets.token_hex(16)
        with self.lock, self.connect() as db:
            try:
                cur = db.execute(
                    'INSERT INTO users (name,email,phone,address,member_code,bonus_points,password_hash,salt,created_at) '
                    'VALUES (?,?,?,?,?,?,?,?,?)',
                    (name, email, phone, address, member_code, int(bonus_points),
                     self._hash(password, salt), salt, int(time.time())),
                )
            except sqlite3.IntegrityError:
                return None, 'Email sudah terdaftar.'
            row = db.execute('SELECT * FROM users WHERE id=?', (cur.lastrowid,)).fetchone()
            token = self._issue_token(db, row['id'])
            self._ensure_member_address(db, row['id'], name, phone, address)
            if int(bonus_points or 0) > 0:
                db.execute('INSERT INTO member_points (user_id,points_delta,reason,created_at) VALUES (?,?,?,?)',
                           (row['id'], int(bonus_points), 'Bonus pendaftaran', int(time.time())))
            db.commit()
        return {'token': token, 'user': self._user(row)}, None

    def login(self, email, password):
        with self.lock, self.connect() as db:
            row = db.execute('SELECT * FROM users WHERE email=?', (email,)).fetchone()
            if row is None:
                return None, 'Email belum terdaftar.'
            if not row['is_active']:
                return None, 'Akun member sedang dinonaktifkan. Hubungi admin.'
            if not hmac.compare_digest(self._hash(password, row['salt']), row['password_hash']):
                return None, 'Password salah.'
            token = self._issue_token(db, row['id'])
            db.commit()
        return {'token': token, 'user': self._user(row)}, None

    def update_member(self, user_id, data):
        allowed = ('name', 'phone', 'address')
        values = {key: data[key] for key in allowed if key in data}
        if not values:
            return self.get_member(user_id)
        if 'name' in values and len(str(values['name']).strip()) < 2:
            raise ValueError('Nama minimal 2 karakter.')
        if 'bonus_points' in values:
            values['bonus_points'] = max(0, int(values['bonus_points']))
        if 'check_in_streak' in values:
            values['check_in_streak'] = max(0, int(values['check_in_streak']))
        assignments = ','.join(f'{key}=?' for key in values)
        with self.lock, self.connect() as db:
            before = db.execute('SELECT address FROM users WHERE id=?',(user_id,)).fetchone()
            address_changed = 'address' in values and before and str(values['address'] or '').strip() != str(before['address'] or '').strip()
            db.execute(f'UPDATE users SET {assignments} WHERE id=?', (*values.values(), user_id))
            if address_changed and str(values['address'] or '').strip():
                # Perubahan alamat profil mengubah alamat utama yang sudah ada,
                # bukan membuat baris baru di buku alamat. Pembuatan alamat baru
                # hanya melalui POST /api/addresses.
                current = db.execute('SELECT name,phone FROM users WHERE id=?', (user_id,)).fetchone()
                primary = db.execute('SELECT id FROM addresses WHERE user_id=? AND is_default=1 ORDER BY id LIMIT 1', (user_id,)).fetchone()
                if current and primary:
                    db.execute('UPDATE addresses SET recipient_name=?,phone=?,address=? WHERE id=? AND user_id=?',
                               (current['name'], current['phone'], str(values['address']).strip(), primary['id'], user_id))
            row = db.execute('SELECT * FROM users WHERE id=?', (user_id,)).fetchone()
        return self._user(row) if row else None

    def get_member(self, user_id):
        with self.connect() as db:
            row = db.execute('SELECT * FROM users WHERE id=?', (user_id,)).fetchone()
        return self._user(row) if row else None

    def user_for_token(self, token):
        if not token:
            return None
        with self.connect() as db:
            return db.execute(
                'SELECT u.* FROM tokens t JOIN users u ON u.id=t.user_id WHERE t.token=? AND t.expires_at>? AND u.is_active=1',
                (token, int(time.time())),
            ).fetchone()

    # -- profil gaya & feedback ----------------------------------------------

    def sync_member_data(self, user_id, payload):
        # Compatibility wrapper; all validation and idempotent rules live in
        # feature_extensions.safe_sync_member_data.
        return feature_extensions.safe_sync_member_data(self, user_id, payload)

    def get_profile(self, user_id):
        with self.connect() as db:
            row = db.execute('SELECT * FROM style_profiles WHERE user_id=?', (user_id,)).fetchone()
        if row is None:
            return {'profile': None, 'model': None, 'updated_at': None}
        return {
            'profile': json.loads(row['profile_json']),
            'model': json.loads(row['model_json']),
            'updated_at': row['updated_at'],
        }

    def put_profile(self, user_id, profile, model):
        with self.lock, self.connect() as db:
            db.execute(
                'INSERT INTO style_profiles (user_id,profile_json,model_json,updated_at) VALUES (?,?,?,?) '
                'ON CONFLICT(user_id) DO UPDATE SET profile_json=excluded.profile_json, '
                'model_json=excluded.model_json, updated_at=excluded.updated_at',
                (user_id, json.dumps(profile, ensure_ascii=False), json.dumps(model), int(time.time())),
            )
            db.commit()

    def add_feedback(self, user_id, product_id, action):
        with self.lock, self.connect() as db:
            if db.execute('SELECT 1 FROM products WHERE id=?', (product_id,)).fetchone() is None:
                return False
            db.execute(
                'INSERT INTO feedback (user_id,product_id,action,created_at) VALUES (?,?,?,?)',
                (user_id, product_id, action, int(time.time())),
            )
            db.commit()
        return True


class Handler(BaseHTTPRequestHandler):
    store = None  # diisi saat server dibuat
    admin = None
    server_version = 'UniqloPlus/1.0'

    # -- util -----------------------------------------------------------------

    def log_message(self, fmt, *args):  # log ringkas
        print('%s - %s' % (self.address_string(), fmt % args))

    def _send(self, status, payload):
        body = b'' if status == 204 else json.dumps(payload, ensure_ascii=False).encode('utf8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.end_headers()
        self.wfile.write(body)

    def _error(self, status, message):
        self._send(status, {'error': message})

    def _json(self):
        try:
            length = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            return None
        try:
            data = json.loads(self.rfile.read(length).decode('utf8'))
        except (ValueError, UnicodeDecodeError):
            return None
        return data if isinstance(data, dict) else None

    def _auth(self):
        header = self.headers.get('Authorization', '')
        token = header[7:].strip() if header.startswith('Bearer ') else ''
        return self.store.user_for_token(token)

    # -- routing ----------------------------------------------------------------

    def do_OPTIONS(self):
        self._send(204, {})

    def do_GET(self):
        path = urlparse(self.path).path.rstrip('/') or '/'
        if path in ('/admin/events', '/admin/api/events'):
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            q = queue.Queue()
            _SSE_SUBSCRIBERS.add(q)
            try:
                self.wfile.write(b"event: connected\ndata: {\"status\":\"ok\"}\n\n")
                self.wfile.flush()
                while True:
                    msg = q.get()
                    self.wfile.write(msg)
                    self.wfile.flush()
            except (ConnectionResetError, BrokenPipeError, Exception):
                pass
            finally:
                _SSE_SUBSCRIBERS.discard(q)
            return

        if path.startswith('/admin'):
            return admin_panel.handle(self.admin, self, 'GET')
        if path.startswith(('/api/member', '/api/addresses', '/api/reviews', '/api/orders')) or path == '/api/points':
            handled, status, payload = feature_extensions.handle_member(self, 'GET', path, self._auth())
            if handled: return self._send(status, payload)
        if path == '/api/health':
            return self._send(200, {'status': 'ok', 'time': int(time.time())})
        if path == '/api/products':
            return self._send(200, {'products': self.store.products()})
        if path == '/api/popularity':
            qs = parse_qs(urlparse(self.path).query)
            ut, dp, gd = (qs.get(k, [''])[0] for k in ('undertone', 'depth', 'gender'))
            if ut or dp or gd:
                return self._send(200, self.store.popularity_segment(ut, dp, gd))
            return self._send(200, {'popularity': self.store.popularity()})
        if path == '/api/ml/model':
            model = self.admin.active_model()
            if model is None:
                return self._error(404, 'Belum ada model ML.')
            return self._send(200, {'model': model})
        if path in ('/api/vouchers', '/api/news', '/api/stores'):
            name = path.rsplit('/', 1)[1]
            return self._send(200, {name: self.store.public_content(name)})
        if path in ('/api/me', '/api/profile'):
            user = self._auth()
            if user is None:
                return self._error(401, 'Sesi tidak valid. Silakan masuk lagi.')
            if path == '/api/me':
                return self._send(200, {'user': Store._user(user)})
            return self._send(200, self.store.get_profile(user['id']))

        # -- Serve Flutter Web static files --
        web_dir = HERE / 'web'
        if web_dir.is_dir():
            rel_path = path.lstrip('/')
            file_path = web_dir / rel_path
            if rel_path == '' or not file_path.exists() or file_path.is_dir():
                file_path = web_dir / 'index.html'
            if file_path.exists() and file_path.is_file():
                ext = file_path.suffix.lower()
                content_types = {
                    '.html': 'text/html; charset=utf-8',
                    '.js': 'application/javascript',
                    '.css': 'text/css',
                    '.json': 'application/json',
                    '.png': 'image/png',
                    '.jpg': 'image/jpeg',
                    '.jpeg': 'image/jpeg',
                    '.svg': 'image/svg+xml',
                    '.ico': 'image/x-icon',
                    '.ttf': 'font/ttf',
                    '.woff': 'font/woff',
                    '.woff2': 'font/woff2',
                    '.wasm': 'application/wasm',
                }
                ct = content_types.get(ext, 'application/octet-stream')
                try:
                    data = file_path.read_bytes()
                    self.send_response(200)
                    self.send_header('Content-Type', ct)
                    self.send_header('Content-Length', str(len(data)))
                    self.send_header('Access-Control-Allow-Origin', '*')
                    self.end_headers()
                    self.wfile.write(data)
                    return
                except Exception:
                    pass

        self._error(404, 'Endpoint tidak ditemukan.')

    def do_POST(self):
        path = urlparse(self.path).path.rstrip('/')
        if path.startswith('/admin'):
            return admin_panel.handle(self.admin, self, 'POST')
        data = self._json()
        if data is None:
            return self._error(400, 'Body JSON tidak valid.')

        if path == '/api/member/sync':
            user = self._auth()
            if user is None: return self._error(401, 'Sesi tidak valid. Silakan masuk lagi.')
            try:
                result = feature_extensions.safe_sync_member_data(self.store, user['id'], data)
            except (TypeError, ValueError, sqlite3.IntegrityError, KeyError):
                return self._error(400, 'Data sinkronisasi member tidak valid.')
            return self._send(200, result)
        if path.startswith(('/api/member', '/api/addresses', '/api/reviews', '/api/orders')) or path.startswith('/api/points'):
            handled, status, payload = feature_extensions.handle_member(self, 'POST', path, self._auth(), data)
            if handled: return self._send(status, payload)

        if path == '/api/auth/register':
            name = str(data.get('name', '')).strip()
            email = str(data.get('email', '')).strip().lower()
            phone = str(data.get('phone', '')).strip()
            address = str(data.get('address', '')).strip()
            member_code = str(data.get('member_code', '')).strip()
            bonus_points = 200  # bonus pendaftaran ditetapkan server, bukan nilai dari klien
            password = str(data.get('password', ''))
            if len(name) < 2:
                return self._error(400, 'Nama minimal 2 karakter.')
            if not EMAIL_RE.match(email):
                return self._error(400, 'Format email tidak valid.')
            if len(password) < 6:
                return self._error(400, 'Password minimal 6 karakter.')
            try:
                result, error = self.store.register(name, email, phone, password,
                                                    address, member_code, bonus_points)
            except (TypeError, ValueError):
                return self._error(400, 'Data member tidak valid.')
            if error:
                return self._error(409, error)
            user_data = result.get('user', {}) if isinstance(result, dict) else {}
            broadcast_admin_event('new_user', {
                'id': user_data.get('id'),
                'name': name,
                'email': email,
                'time': int(time.time())
            })
            return self._send(201, result)

        if path == '/api/auth/login':
            email = str(data.get('email', '')).strip().lower()
            password = str(data.get('password', ''))
            result, error = self.store.login(email, password)
            if error:
                return self._error(401, error)
            return self._send(200, result)

        if path == '/api/feedback':
            user = self._auth()
            if user is None:
                return self._error(401, 'Sesi tidak valid. Silakan masuk lagi.')
            product_id = str(data.get('product_id', ''))
            action = str(data.get('action', ''))
            if action not in ACTIONS:
                return self._error(400, 'Aksi tidak dikenal.')
            if not self.store.add_feedback(user['id'], product_id, action):
                return self._error(404, 'Produk tidak ditemukan.')
            return self._send(201, {'ok': True})

        self._error(404, 'Endpoint tidak ditemukan.')

    def do_DELETE(self):
        path = urlparse(self.path).path.rstrip('/')
        if path.startswith('/admin'):
            return admin_panel.handle(self.admin, self, 'DELETE')
        if path.startswith(('/api/member', '/api/addresses', '/api/reviews', '/api/orders')) or path == '/api/points':
            handled, status, payload = feature_extensions.handle_member(self, 'DELETE', path, self._auth())
            if handled: return self._send(status, payload)
        self._error(404, 'Endpoint tidak ditemukan.')

    def do_PUT(self):
        path = urlparse(self.path).path.rstrip('/')
        if path.startswith('/admin'):
            return admin_panel.handle(self.admin, self, 'PUT')
        if path.startswith(('/api/member', '/api/addresses', '/api/reviews', '/api/orders')) or path == '/api/points':
            data = self._json()
            if data is None: return self._error(400, 'Body JSON tidak valid.')
            handled, status, payload = feature_extensions.handle_member(self, 'PUT', path, self._auth(), data)
            if handled: return self._send(status, payload)
        if path not in ('/api/profile', '/api/me'):
            return self._error(404, 'Endpoint tidak ditemukan.')
        user = self._auth()
        if user is None:
            return self._error(401, 'Sesi tidak valid. Silakan masuk lagi.')
        data = self._json()
        if data is None:
            return self._error(400, 'Body JSON tidak valid.')
        if path == '/api/me':
            try:
                updated = self.store.update_member(user['id'], data)
            except (TypeError, ValueError):
                return self._error(400, 'Data member tidak valid.')
            return self._send(200, {'user': updated})
        profile = data.get('profile')
        model = data.get('model')
        if not isinstance(profile, dict) or not isinstance(model, dict):
            return self._error(400, 'Field profile dan model wajib berupa objek.')
        self.store.put_profile(user['id'], profile, model)
        self._send(200, {'ok': True})


def make_server(host, port, db_path):
    Handler.store = Store(db_path)
    Handler.admin = admin_panel.Admin(Handler.store)
    feature_extensions.broadcast_admin_event = broadcast_admin_event
    with Handler.store.connect() as db:
        feature_extensions.migrate(db)
        feature_extensions.seed_sample_reviews(db)
    if Handler.admin.bootstrap_message:
        print('[ADMIN]', Handler.admin.bootstrap_message)
    return ThreadingHTTPServer((host, port), Handler)


def main():
    parser = argparse.ArgumentParser(description='Server UNIQLO PLUS')
    parser.add_argument('--host', default='0.0.0.0')
    default_port = int(os.environ.get('PORT', 8000))
    parser.add_argument('--port', type=int, default=default_port)
    parser.add_argument('--db', default=str(HERE / 'uniqlo_plus.sqlite3'))
    args = parser.parse_args()
    server = make_server(args.host, args.port, args.db)
    print(f'UNIQLO PLUS server berjalan di http://{args.host}:{args.port}  (db: {args.db})')
    print(f'Control panel: http://localhost:{args.port}/admin')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nServer dihentikan.')
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
