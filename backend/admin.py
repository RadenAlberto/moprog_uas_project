"""Control panel (admin) UNIQLO PLUS: API JSON + penyajian antarmuka web.

Dipanggil dari server.py untuk semua path /admin dan /admin/api/*.
Python murni (tanpa library tambahan), memakai database SQLite yang sama.

Keamanan:
  * Akun admin terpisah dari akun member; password PBKDF2-SHA256 + salt.
  * Sesi token acak (12 jam), disimpan sebagai hash SHA-256.
  * Batas percobaan login: 5 gagal / 10 menit per username dan per IP.
  * Peran: Admin (operasional/konten) dan Owner (semua, termasuk akun admin
    dan role, serta pelatihan/aktivasi model).
  * Semua perubahan dicatat di audit_log.
  * Respons admin tidak memakai CORS terbuka; hanya halaman /admin sendiri
    yang bisa memanggilnya.
"""
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
UI_FILE = HERE / 'admin_ui.html'
ML_DIR = ROOT / 'ml'
ML_RAW = ML_DIR / 'data' / 'raw'
BUNDLED_MODEL = ROOT / 'assets' / 'data' / 'ml_model.json'

SESSION_TTL = 12 * 3600
LOGIN_WINDOW = 600
LOGIN_MAX_FAILS = 5
ROLES = {'admin': 1, 'owner': 2}
TIERS = ('regular', 'silver', 'gold', 'platinum')
VOUCHER_TYPES = ('percent', 'fixed', 'freeShipping')
NEWS_CATEGORIES = ('promo', 'info', 'koleksi', 'event', 'member')
NEWS_ACTIONS = ('none', 'catalog', 'membership', 'vouchers')

ADMIN_SCHEMA = """
CREATE TABLE IF NOT EXISTS admins (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  password_hash TEXT NOT NULL,
  salt TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin',
  active INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  last_login INTEGER
);
CREATE TABLE IF NOT EXISTS admin_sessions (
  token_hash TEXT PRIMARY KEY,
  admin_id INTEGER NOT NULL REFERENCES admins(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS login_attempts (
  key TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_login_attempts ON login_attempts(key, at);
CREATE TABLE IF NOT EXISTS audit_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER NOT NULL,
  admin TEXT NOT NULL,
  action TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL DEFAULT '',
  detail TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS vouchers (
  code TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  type TEXT NOT NULL,
  value REAL NOT NULL DEFAULT 0,
  max_discount REAL,
  min_spend REAL NOT NULL DEFAULT 0,
  member_only INTEGER NOT NULL DEFAULT 0,
  min_tier TEXT,
  expires_at TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS news (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  summary TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  image TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'info',
  date TEXT NOT NULL,
  is_pinned INTEGER NOT NULL DEFAULT 0,
  action TEXT NOT NULL DEFAULT 'none',
  action_label TEXT NOT NULL DEFAULT '',
  published INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS stores (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  mall TEXT NOT NULL DEFAULT '',
  city TEXT NOT NULL DEFAULT '',
  province TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  lat REAL,
  lng REAL,
  open_hour INTEGER NOT NULL DEFAULT 10,
  close_hour INTEGER NOT NULL DEFAULT 22,
  services TEXT NOT NULL DEFAULT '[]'
);
CREATE TABLE IF NOT EXISTS ml_models (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  version TEXT NOT NULL,
  origin TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  model_json TEXT NOT NULL,
  report_md TEXT NOT NULL DEFAULT '',
  active INTEGER NOT NULL DEFAULT 0
);
"""


class ApiError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def _now():
    return int(time.time())


def _hash(password, salt):
    return hashlib.pbkdf2_hmac('sha256', password.encode('utf8'), bytes.fromhex(salt), 150_000).hex()


def _tok_hash(token):
    return hashlib.sha256(token.encode('utf8')).hexdigest()


def _bool(v):
    return 1 if v in (True, 1, '1', 'true', 'on') else 0


def _num(v, name, minimum=None, allow_none=False):
    if v in (None, ''):
        if allow_none:
            return None
        raise ApiError(400, f'{name} wajib diisi.')
    try:
        n = float(v)
    except (TypeError, ValueError):
        raise ApiError(400, f'{name} harus berupa angka.')
    if minimum is not None and n < minimum:
        raise ApiError(400, f'{name} minimal {minimum}.')
    return n


def _text(v, name, required=True, maxlen=2000):
    s = '' if v is None else str(v).strip()
    if required and not s:
        raise ApiError(400, f'{name} wajib diisi.')
    if len(s) > maxlen:
        raise ApiError(400, f'{name} terlalu panjang (maks {maxlen} karakter).')
    return s


def _list(v, name):
    if v in (None, ''):
        return []
    if isinstance(v, str):
        v = [x.strip() for x in v.replace('\n', ',').split(',') if x.strip()]
    if not isinstance(v, list):
        raise ApiError(400, f'{name} harus berupa daftar.')
    return v


def _iso(v, name):
    s = _text(v, name)
    try:
        datetime.fromisoformat(s.replace('Z', '+00:00'))
    except ValueError:
        raise ApiError(400, f'{name} harus berformat tanggal ISO, contoh 2027-12-31T23:59:00.')
    return s


class Admin:
    def __init__(self, store):
        self.store = store
        self.train_lock = threading.Lock()
        with store.connect() as db:
            db.executescript(ADMIN_SCHEMA)
            db.execute("UPDATE admins SET role='admin' WHERE role IN ('editor','viewer')")
            db.commit()
        self.bootstrap_message = self._ensure_owner()

    # ------------------------------------------------------------------ akun
    def _ensure_owner(self):
        """Provision akun awal hanya bila kredensial eksplisit disediakan.

        Tidak ada lagi akun default/random yang dibuat saat server dijalankan.
        Untuk instalasi baru gunakan buat_admin.py atau set kedua environment
        variable ADMIN_USER dan ADMIN_PASSWORD.
        """
        with self.store.lock, self.store.connect() as db:
            if db.execute('SELECT COUNT(*) FROM admins').fetchone()[0] > 0:
                return None
            username = os.environ.get('ADMIN_USER', '').strip()
            password = os.environ.get('ADMIN_PASSWORD', '')
            if not username or not password:
                return ('Belum ada akun admin. Buat akun secara eksplisit dengan '
                        'python buat_admin.py USERNAME (password diminta secara aman).')
            if len(password) < 8:
                return 'ADMIN_PASSWORD minimal 8 karakter; akun admin tidak dibuat.'
            salt = secrets.token_hex(16)
            db.execute(
                'INSERT INTO admins (username,name,password_hash,salt,role,created_at) VALUES (?,?,?,?,?,?)',
                (username, username, _hash(password, salt), salt, 'owner', _now()))
            db.commit()
        return f'Akun admin pertama dibuat dari environment variable (username: {username}).'

    def _too_many_fails(self, db, keys):
        cutoff = _now() - LOGIN_WINDOW
        for k in keys:
            n = db.execute('SELECT COUNT(*) FROM login_attempts WHERE key=? AND at>?', (k, cutoff)).fetchone()[0]
            if n >= LOGIN_MAX_FAILS:
                return True
        return False

    def login(self, username, password, ip):
        username = (username or '').strip().lower()
        keys = ['u:' + username, 'ip:' + ip]
        with self.store.lock, self.store.connect() as db:
            db.execute('DELETE FROM login_attempts WHERE at<?', (_now() - LOGIN_WINDOW,))
            if self._too_many_fails(db, keys):
                db.commit()
                raise ApiError(429, 'Terlalu banyak percobaan gagal. Coba lagi dalam 10 menit.')
            row = db.execute('SELECT * FROM admins WHERE lower(username)=? AND active=1', (username,)).fetchone()
            ok = row is not None and hmac.compare_digest(_hash(password or '', row['salt']), row['password_hash'])
            if not ok:
                for k in keys:
                    db.execute('INSERT INTO login_attempts (key,at) VALUES (?,?)', (k, _now()))
                db.commit()
                raise ApiError(401, 'Username atau password salah.')
            token = secrets.token_urlsafe(32)
            db.execute('INSERT INTO admin_sessions VALUES (?,?,?)', (_tok_hash(token), row['id'], _now() + SESSION_TTL))
            db.execute('DELETE FROM admin_sessions WHERE expires_at<?', (_now(),))
            db.execute('UPDATE admins SET last_login=? WHERE id=?', (_now(), row['id']))
            db.commit()
        return {'token': token, 'admin': self._admin_dict(row)}

    @staticmethod
    def _admin_dict(r):
        return {'id': r['id'], 'username': r['username'], 'name': r['name'], 'role': r['role'],
                'active': bool(r['active']), 'created_at': r['created_at'], 'last_login': r['last_login']}

    def admin_for(self, header):
        token = header[7:].strip() if header.startswith('Bearer ') else ''
        if not token:
            return None
        with self.store.connect() as db:
            return db.execute(
                'SELECT a.* FROM admin_sessions s JOIN admins a ON a.id=s.admin_id '
                'WHERE s.token_hash=? AND s.expires_at>? AND a.active=1', (_tok_hash(token), _now())).fetchone()

    def logout(self, header):
        token = header[7:].strip() if header.startswith('Bearer ') else ''
        with self.store.lock, self.store.connect() as db:
            db.execute('DELETE FROM admin_sessions WHERE token_hash=?', (_tok_hash(token),))
            db.commit()

    def audit(self, db, admin, action, entity, entity_id='', detail=''):
        db.execute('INSERT INTO audit_log (at,admin,action,entity,entity_id,detail) VALUES (?,?,?,?,?,?)',
                   (_now(), admin['username'], action, entity, str(entity_id), str(detail)[:500]))

    @staticmethod
    def need(admin, role):
        if ROLES[admin['role']] < ROLES[role]:
            raise ApiError(403, 'Peran Anda tidak diizinkan melakukan aksi ini.')

    # ---------------------------------------------------------------- umum
    @staticmethod
    def _page(q):
        try:
            page = max(1, int(q.get('page', ['1'])[0]))
            per = min(100, max(1, int(q.get('per_page', ['20'])[0])))
        except ValueError:
            page, per = 1, 20
        return page, per, (page - 1) * per

    # ------------------------------------------------------------- dashboard
    def dashboard(self):
        day = 86400
        now = _now()
        with self.store.connect() as db:
            one = lambda sql, *a: db.execute(sql, a).fetchone()[0]
            counts = {
                'products': one('SELECT COUNT(*) FROM products'),
                'users': one('SELECT COUNT(*) FROM users'),
                'feedback': one('SELECT COUNT(*) FROM feedback'),
                'profiles': one('SELECT COUNT(*) FROM style_profiles'),
                'vouchers': one('SELECT COUNT(*) FROM vouchers WHERE active=1'),
                'news': one('SELECT COUNT(*) FROM news WHERE published=1'),
                'stores': one('SELECT COUNT(*) FROM stores'),
                'orders': one('SELECT COUNT(*) FROM orders'),
                'order_items': one('SELECT COUNT(*) FROM order_items'),
                'addresses': one('SELECT COUNT(*) FROM addresses'),
                'cart_items': one('SELECT COUNT(*) FROM cart_items'),
                'wishlist': one('SELECT COUNT(*) FROM wishlist'),
                'activities': one('SELECT COUNT(*) FROM member_activities'),
                'points': one('SELECT COUNT(*) FROM member_points'),
                'reviews': one('SELECT COUNT(*) FROM reviews'),
                'variants': one('SELECT COUNT(*) FROM product_variants'),
                'users_7d': one('SELECT COUNT(*) FROM users WHERE created_at>?', now - 7 * day),
            }
            start = (now // day - 13) * day
            fb = {r[0]: r[1] for r in db.execute(
                "SELECT created_at/86400 AS d, COUNT(*) FROM feedback WHERE created_at>=? GROUP BY d", (start,))}
            us = {r[0]: r[1] for r in db.execute(
                "SELECT created_at/86400 AS d, COUNT(*) FROM users WHERE created_at>=? GROUP BY d", (start,))}
            days = [start // day + i for i in range(14)]
            series = [{'date': datetime.fromtimestamp(d * day, timezone.utc).strftime('%d/%m'),
                       'feedback': fb.get(d, 0), 'users': us.get(d, 0)} for d in days]
            actions = {r[0]: r[1] for r in db.execute('SELECT action, COUNT(*) FROM feedback GROUP BY action')}
            top = [dict(r) for r in db.execute(
                "SELECT p.id, p.name, p.category, SUM(CASE f.action WHEN 'cart' THEN 2.0 WHEN 'like' THEN 1.0 "
                "WHEN 'dislike' THEN -1.0 ELSE 0.2 END) AS score, COUNT(*) AS n "
                "FROM feedback f JOIN products p ON p.id=f.product_id GROUP BY p.id ORDER BY score DESC LIMIT 8")]
            cats = [dict(r) for r in db.execute(
                'SELECT category AS label, COUNT(*) AS n FROM products GROUP BY category ORDER BY n DESC LIMIT 10')]
            model = db.execute('SELECT id,version,origin,created_at,model_json FROM ml_models WHERE active=1').fetchone()
            tone = {}
            for r in db.execute('SELECT profile_json FROM style_profiles'):
                try:
                    p = json.loads(r[0])
                    k = f"{p.get('undertone', '?')}/{p.get('depth', '?')}"
                    tone[k] = tone.get(k, 0) + 1
                except ValueError:
                    pass
        ml = None
        if model:
            m = json.loads(model['model_json'])
            ml = {'id': model['id'], 'version': model['version'], 'origin': model['origin'],
                  'sources': {k: v.get('source') for k, v in m.get('components', {}).items()}}
        return {'counts': counts, 'series': series, 'actions': actions, 'top_products': top,
                'categories': cats, 'model': ml, 'profiles_by_skin': tone}

    # -------------------------------------------------------------- produk
    PRODUCT_COLS = ('id', 'name', 'price', 'original_price', 'image', 'category', 'audience', 'description',
                    'features', 'is_new', 'sizes', 'colors', 'color_names', 'color_codes', 'color_images',
                    'gallery', 'rating_average', 'rating_count', 'url')
    PRODUCT_JSON = ('features', 'sizes', 'colors', 'color_names', 'color_codes', 'color_images', 'gallery')

    @classmethod
    def _product_out(cls, r):
        d = {k: r[k] for k in cls.PRODUCT_COLS}
        for k in cls.PRODUCT_JSON:
            d[k] = json.loads(d[k])
        d['is_new'] = bool(d['is_new'])
        return d

    def _product_clean(self, data, creating):
        pid = _text(data.get('id'), 'ID produk', maxlen=64)
        out = {
            'id': pid,
            'name': _text(data.get('name'), 'Nama'),
            'price': _num(data.get('price'), 'Harga', 0),
            'original_price': _num(data.get('original_price'), 'Harga normal', 0, allow_none=True),
            'image': _text(data.get('image'), 'Foto utama', required=False, maxlen=1000),
            'category': _text(data.get('category'), 'Kategori', maxlen=80),
            'audience': _text(data.get('audience'), 'Target pengguna', maxlen=40),
            'description': _text(data.get('description'), 'Deskripsi', required=False, maxlen=5000),
            'is_new': _bool(data.get('is_new')),
            'rating_average': _num(data.get('rating_average') or 0, 'Rating', 0),
            'rating_count': int(_num(data.get('rating_count') or 0, 'Jumlah ulasan', 0)),
            'url': _text(data.get('url'), 'URL', required=False, maxlen=1000),
        }
        if out['original_price'] is not None and out['original_price'] < out['price']:
            out['original_price'] = None
        for k in self.PRODUCT_JSON:
            out[k] = _list(data.get(k), k)
        colors = []
        for c in out['colors']:
            try:
                colors.append(int(c))
            except (TypeError, ValueError):
                raise ApiError(400, 'colors harus daftar angka ARGB (mis. 4280232540).')
        out['colors'] = colors
        n = len(colors)
        for k in ('color_names', 'color_codes', 'color_images'):
            if out[k] and len(out[k]) != n:
                raise ApiError(400, f'{k} harus sama panjang dengan colors ({n}).')
            if not out[k]:
                out[k] = [''] * n if k != 'color_codes' else [str(i) for i in range(n)]
        return out

    def _save_product(self, db, p):
        db.execute(
            'INSERT INTO products (id,name,price,original_price,image,category,audience,description,features,'
            'is_new,sizes,colors,color_names,color_codes,color_images,gallery,rating_average,rating_count,url) '
            'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET '
            'name=excluded.name, price=excluded.price, original_price=excluded.original_price, '
            'image=excluded.image, category=excluded.category, audience=excluded.audience, '
            'description=excluded.description, features=excluded.features, is_new=excluded.is_new, '
            'sizes=excluded.sizes, colors=excluded.colors, color_names=excluded.color_names, '
            'color_codes=excluded.color_codes, color_images=excluded.color_images, gallery=excluded.gallery, '
            'rating_average=excluded.rating_average, rating_count=excluded.rating_count, url=excluded.url',
            (p['id'], p['name'], p['price'], p['original_price'], p['image'], p['category'], p['audience'],
             p['description'], json.dumps(p['features'], ensure_ascii=False), p['is_new'],
             json.dumps(p['sizes'], ensure_ascii=False), json.dumps(p['colors']),
             json.dumps(p['color_names'], ensure_ascii=False), json.dumps(p['color_codes']),
             json.dumps(p['color_images']), json.dumps(p['gallery'], ensure_ascii=False),
             p['rating_average'], p['rating_count'], p['url']))
        # varian (warna x ukuran) disamakan dengan data produk
        db.execute('DELETE FROM product_variants WHERE product_id=?', (p['id'],))
        for i, code in enumerate(p['color_codes']):
            for size in p['sizes']:
                db.execute(
                    'INSERT OR IGNORE INTO product_variants (product_id,color_code,color_name,color_argb,size,'
                    'price,original_price,image) VALUES (?,?,?,?,?,?,?,?)',
                    (p['id'], str(code), p['color_names'][i], p['colors'][i], str(size), p['price'],
                     p['original_price'], p['color_images'][i]))

    def products_list(self, q):
        page, per, off = self._page(q)
        where, args = [], []
        text = (q.get('q', [''])[0] or '').strip()
        if text:
            where.append('(name LIKE ? OR id LIKE ?)')
            args += [f'%{text}%', f'%{text}%']
        for key in ('category', 'audience'):
            v = (q.get(key, [''])[0] or '').strip()
            if v:
                where.append(f'{key}=?')
                args.append(v)
        if (q.get('sale', [''])[0]) == '1':
            where.append('original_price IS NOT NULL AND original_price>price')
        sql_where = ('WHERE ' + ' AND '.join(where)) if where else ''
        sort = {'name': 'name', 'price': 'price', 'price_desc': 'price DESC', 'new': 'rowid DESC'}.get(
            q.get('sort', [''])[0], 'rowid')
        with self.store.connect() as db:
            total = db.execute(f'SELECT COUNT(*) FROM products {sql_where}', args).fetchone()[0]
            rows = db.execute(f'SELECT * FROM products {sql_where} ORDER BY {sort} LIMIT ? OFFSET ?',
                              args + [per, off]).fetchall()
            cats = [r[0] for r in db.execute('SELECT DISTINCT category FROM products ORDER BY 1')]
            auds = [r[0] for r in db.execute('SELECT DISTINCT audience FROM products ORDER BY 1')]
        return {'items': [self._product_out(r) for r in rows], 'total': total, 'page': page, 'per_page': per,
                'categories': cats, 'audiences': auds}

    def product_create(self, admin, data):
        p = self._product_clean(data, True)
        with self.store.lock, self.store.connect() as db:
            if db.execute('SELECT 1 FROM products WHERE id=?', (p['id'],)).fetchone():
                raise ApiError(409, 'ID produk sudah dipakai.')
            self._save_product(db, p)
            self.audit(db, admin, 'create', 'product', p['id'], p['name'])
            db.commit()
        return p

    def product_update(self, admin, pid, data):
        data = dict(data)
        data['id'] = pid
        p = self._product_clean(data, False)
        with self.store.lock, self.store.connect() as db:
            if not db.execute('SELECT 1 FROM products WHERE id=?', (pid,)).fetchone():
                raise ApiError(404, 'Produk tidak ditemukan.')
            self._save_product(db, p)
            self.audit(db, admin, 'update', 'product', pid, p['name'])
            db.commit()
        return p

    def product_delete(self, admin, pid):
        with self.store.lock, self.store.connect() as db:
            cur = db.execute('DELETE FROM products WHERE id=?', (pid,))
            if cur.rowcount == 0:
                raise ApiError(404, 'Produk tidak ditemukan.')
            self.audit(db, admin, 'delete', 'product', pid)
            db.commit()
        return {'ok': True}

    def product_bulk(self, admin, data):
        items = data.get('products')
        if not isinstance(items, list) or not items:
            raise ApiError(400, 'Field products wajib berupa daftar produk.')
        if len(items) > 5000:
            raise ApiError(400, 'Maksimal 5000 produk per impor.')
        ok, errors = 0, []
        with self.store.lock, self.store.connect() as db:
            for i, raw in enumerate(items):
                try:
                    self._save_product(db, self._product_clean(raw if isinstance(raw, dict) else {}, True))
                    ok += 1
                except ApiError as e:
                    errors.append({'index': i, 'id': raw.get('id') if isinstance(raw, dict) else None,
                                   'error': e.message})
            self.audit(db, admin, 'import', 'product', '', f'{ok} berhasil, {len(errors)} gagal')
            db.commit()
        return {'imported': ok, 'errors': errors[:50], 'error_count': len(errors)}

    def product_export(self):
        with self.store.connect() as db:
            return [self._product_out(r) for r in db.execute('SELECT * FROM products ORDER BY rowid')]

    # ---------------------------------------------------------------- user
    def users_list(self, q):
        page, per, off = self._page(q)
        text = (q.get('q', [''])[0] or '').strip()
        where, args = '', []
        if text:
            where = 'WHERE u.name LIKE ? OR u.email LIKE ? OR u.phone LIKE ?'
            args = [f'%{text}%'] * 3
        with self.store.connect() as db:
            total = db.execute(f'SELECT COUNT(*) FROM users u {where}', args).fetchone()[0]
            rows = db.execute(
                f'SELECT u.id,u.name,u.email,u.phone,u.address,u.member_code,u.bonus_points,u.is_active,u.created_at,'
                f'(SELECT COALESCE(SUM(mp.points_delta),0) FROM member_points mp WHERE mp.user_id=u.id) AS points_balance,'
                f'(SELECT COALESCE(SUM(o.net_eligible_amount),0) FROM orders o WHERE o.user_id=u.id AND lower(o.order_status)=\'selesai\' AND lower(o.payment_status) NOT IN (\'refunded\',\'refund\')) AS total_spend,'
                f'(SELECT COUNT(*) FROM feedback f WHERE f.user_id=u.id) AS feedback_count,'
                f'(SELECT COUNT(*) FROM style_profiles s WHERE s.user_id=u.id) AS has_profile '
                f'FROM users u {where} ORDER BY u.id DESC LIMIT ? OFFSET ?', args + [per, off]).fetchall()
        items=[]
        for row in rows:
            item=dict(row); spend=float(item['total_spend'] or 0)
            item['tier']='platinum' if spend>=7500000 else 'gold' if spend>=3000000 else 'silver' if spend>=1000000 else 'regular'
            items.append(item)
        return {'items': items, 'total': total, 'page': page, 'per_page': per}

    def user_get(self, uid):
        with self.store.connect() as db:
            u = db.execute('''SELECT u.id,u.name,u.email,u.phone,u.address,u.member_code,u.bonus_points,u.is_active,u.last_check_in_day,u.check_in_streak,u.created_at,
                (SELECT COALESCE(SUM(points_delta),0) FROM member_points mp WHERE mp.user_id=u.id) AS points_balance,
                (SELECT COALESCE(SUM(net_eligible_amount),0) FROM orders o WHERE o.user_id=u.id AND lower(o.order_status)='selesai' AND lower(o.payment_status) NOT IN ('refunded','refund')) AS total_spend
                FROM users u WHERE u.id=?''', (uid,)).fetchone()
            if not u:
                raise ApiError(404, 'User tidak ditemukan.')
            prof = db.execute('SELECT profile_json,updated_at FROM style_profiles WHERE user_id=?', (uid,)).fetchone()
            fb = [dict(r) for r in db.execute(
                'SELECT f.action,f.created_at,p.id AS product_id,p.name FROM feedback f '
                'JOIN products p ON p.id=f.product_id WHERE f.user_id=? ORDER BY f.id DESC LIMIT 30', (uid,))]
        user=dict(u); spend=float(user['total_spend'] or 0)
        user['tier']='platinum' if spend>=7500000 else 'gold' if spend>=3000000 else 'silver' if spend>=1000000 else 'regular'
        return {'user': user, 'profile': json.loads(prof['profile_json']) if prof else None,
                'profile_updated_at': prof['updated_at'] if prof else None, 'feedback': fb}

    def user_update(self, admin, uid, data):
        name = _text(data.get('name'), 'Nama', maxlen=120)
        email = _text(data.get('email'), 'Email', maxlen=200).lower()
        if '@' not in email:
            raise ApiError(400, 'Format email tidak valid.')
        phone = _text(data.get('phone'), 'Telepon', required=False, maxlen=40)
        active = _bool(data.get('is_active', 1))
        with self.store.lock, self.store.connect() as db:
            try:
                cur = db.execute('UPDATE users SET name=?, email=?, phone=?, is_active=? WHERE id=?', (name, email, phone, active, uid))
                if not active: db.execute('DELETE FROM tokens WHERE user_id=?', (uid,))
            except sqlite3.IntegrityError:
                raise ApiError(409, 'Email sudah dipakai user lain.')
            if cur.rowcount == 0:
                raise ApiError(404, 'User tidak ditemukan.')
            self.audit(db, admin, 'update', 'user', uid, f'{email}; status={"aktif" if active else "nonaktif"}')
            db.commit()
        return {'ok': True}

    def user_reset_password(self, admin, uid):
        temp = secrets.token_urlsafe(8)
        salt = secrets.token_hex(16)
        with self.store.lock, self.store.connect() as db:
            cur = db.execute('UPDATE users SET password_hash=?, salt=? WHERE id=?', (_hash_user(temp, salt), salt, uid))
            if cur.rowcount == 0:
                raise ApiError(404, 'User tidak ditemukan.')
            db.execute('DELETE FROM tokens WHERE user_id=?', (uid,))
            self.audit(db, admin, 'reset_password', 'user', uid)
            db.commit()
        return {'temporary_password': temp}

    def user_delete(self, admin, uid):
        with self.store.lock, self.store.connect() as db:
            cur = db.execute('DELETE FROM users WHERE id=?', (uid,))
            if cur.rowcount == 0:
                raise ApiError(404, 'User tidak ditemukan.')
            self.audit(db, admin, 'delete', 'user', uid)
            db.commit()
        return {'ok': True}

    # ------------------------------------------------- voucher/berita/toko
    def _simple_list(self, table, order):
        with self.store.connect() as db:
            return [dict(r) for r in db.execute(f'SELECT * FROM {table} ORDER BY {order}')]

    def vouchers_list(self):
        rows = self._simple_list('vouchers', 'code')
        for r in rows:
            r['member_only'] = bool(r['member_only'])
            r['active'] = bool(r['active'])
        return {'items': rows}

    def _voucher_clean(self, data, code=None):
        code = (code or _text(data.get('code'), 'Kode', maxlen=40)).upper().replace(' ', '')
        vtype = _text(data.get('type'), 'Jenis')
        if vtype not in VOUCHER_TYPES:
            raise ApiError(400, 'Jenis voucher: percent, fixed, atau freeShipping.')
        value = _num(data.get('value') or 0, 'Nilai', 0)
        if vtype == 'percent' and value > 100:
            raise ApiError(400, 'Persentase maksimal 100.')
        tier = (data.get('min_tier') or None)
        if tier not in (None,) + TIERS:
            raise ApiError(400, 'Level minimal: regular, silver, gold, platinum.')
        return {
            'code': code, 'title': _text(data.get('title'), 'Judul', maxlen=150),
            'description': _text(data.get('description'), 'Deskripsi', required=False, maxlen=500),
            'type': vtype, 'value': value,
            'max_discount': _num(data.get('max_discount'), 'Maks. potongan', 0, allow_none=True),
            'min_spend': _num(data.get('min_spend') or 0, 'Minimal belanja', 0),
            'member_only': _bool(data.get('member_only')), 'min_tier': tier,
            'expires_at': _iso(data.get('expires_at'), 'Kedaluwarsa'), 'active': _bool(data.get('active', 1)),
        }

    def voucher_save(self, admin, data, code=None):
        v = self._voucher_clean(data, code)
        with self.store.lock, self.store.connect() as db:
            exists = db.execute('SELECT 1 FROM vouchers WHERE code=?', (v['code'],)).fetchone()
            if code is None and exists:
                raise ApiError(409, 'Kode voucher sudah ada.')
            if code is not None and not exists:
                raise ApiError(404, 'Voucher tidak ditemukan.')
            db.execute(
                'INSERT INTO vouchers VALUES (:code,:title,:description,:type,:value,:max_discount,:min_spend,'
                ':member_only,:min_tier,:expires_at,:active) ON CONFLICT(code) DO UPDATE SET title=:title,'
                'description=:description,type=:type,value=:value,max_discount=:max_discount,min_spend=:min_spend,'
                'member_only=:member_only,min_tier=:min_tier,expires_at=:expires_at,active=:active', v)
            self.audit(db, admin, 'update' if code else 'create', 'voucher', v['code'], v['title'])
            db.commit()
        return v

    def news_list(self):
        rows = self._simple_list('news', 'is_pinned DESC, date DESC')
        for r in rows:
            r['is_pinned'] = bool(r['is_pinned'])
            r['published'] = bool(r['published'])
        return {'items': rows}

    def news_save(self, admin, data, nid=None):
        cat = _text(data.get('category') or 'info', 'Kategori')
        act = _text(data.get('action') or 'none', 'Aksi')
        if cat not in NEWS_CATEGORIES:
            raise ApiError(400, 'Kategori: ' + ', '.join(NEWS_CATEGORIES))
        if act not in NEWS_ACTIONS:
            raise ApiError(400, 'Aksi: ' + ', '.join(NEWS_ACTIONS))
        n = {
            'id': nid or _text(data.get('id'), 'ID berita', maxlen=64),
            'title': _text(data.get('title'), 'Judul', maxlen=200),
            'summary': _text(data.get('summary'), 'Ringkasan', required=False, maxlen=500),
            'content': _text(data.get('content'), 'Isi', required=False, maxlen=20000),
            'image': _text(data.get('image'), 'Gambar', required=False, maxlen=1000),
            'category': cat, 'date': _iso(data.get('date'), 'Tanggal'),
            'is_pinned': _bool(data.get('is_pinned')), 'action': act,
            'action_label': _text(data.get('action_label'), 'Label tombol', required=False, maxlen=60),
            'published': _bool(data.get('published', 1)),
        }
        with self.store.lock, self.store.connect() as db:
            exists = db.execute('SELECT 1 FROM news WHERE id=?', (n['id'],)).fetchone()
            if nid is None and exists:
                raise ApiError(409, 'ID berita sudah ada.')
            if nid is not None and not exists:
                raise ApiError(404, 'Berita tidak ditemukan.')
            db.execute(
                'INSERT INTO news VALUES (:id,:title,:summary,:content,:image,:category,:date,:is_pinned,:action,'
                ':action_label,:published) ON CONFLICT(id) DO UPDATE SET title=:title,summary=:summary,'
                'content=:content,image=:image,category=:category,date=:date,is_pinned=:is_pinned,action=:action,'
                'action_label=:action_label,published=:published', n)
            self.audit(db, admin, 'update' if nid else 'create', 'news', n['id'], n['title'])
            db.commit()
        return n

    def stores_list(self):
        rows = self._simple_list('stores', 'province, city, name')
        for r in rows:
            r['services'] = json.loads(r['services'])
        return {'items': rows}

    def _store_clean(self, data, sid=None):
        oh = int(_num(data.get('open_hour', 10), 'Jam buka', 0))
        ch = int(_num(data.get('close_hour', 22), 'Jam tutup', 0))
        if not (0 <= oh < ch <= 24):
            raise ApiError(400, 'Jam buka harus lebih kecil dari jam tutup (0-24).')
        return {
            'id': sid or _text(data.get('id'), 'ID toko', maxlen=40),
            'name': _text(data.get('name'), 'Nama', maxlen=150),
            'mall': _text(data.get('mall'), 'Mal', required=False, maxlen=150),
            'city': _text(data.get('city'), 'Kota', maxlen=80),
            'province': _text(data.get('province'), 'Provinsi', required=False, maxlen=80),
            'address': _text(data.get('address'), 'Alamat', required=False, maxlen=500),
            'phone': _text(data.get('phone'), 'Telepon', required=False, maxlen=40),
            'lat': _num(data.get('lat'), 'Lat', allow_none=True), 'lng': _num(data.get('lng'), 'Lng', allow_none=True),
            'open_hour': oh, 'close_hour': ch,
            'services': json.dumps([str(s) for s in _list(data.get('services'), 'Layanan')], ensure_ascii=False),
        }

    def store_save(self, admin, data, sid=None):
        s = self._store_clean(data, sid)
        with self.store.lock, self.store.connect() as db:
            exists = db.execute('SELECT 1 FROM stores WHERE id=?', (s['id'],)).fetchone()
            if sid is None and exists:
                raise ApiError(409, 'ID toko sudah ada.')
            if sid is not None and not exists:
                raise ApiError(404, 'Toko tidak ditemukan.')
            db.execute(
                'INSERT INTO stores VALUES (:id,:name,:mall,:city,:province,:address,:phone,:lat,:lng,:open_hour,'
                ':close_hour,:services) ON CONFLICT(id) DO UPDATE SET name=:name,mall=:mall,city=:city,'
                'province=:province,address=:address,phone=:phone,lat=:lat,lng=:lng,open_hour=:open_hour,'
                'close_hour=:close_hour,services=:services', s)
            self.audit(db, admin, 'update' if sid else 'create', 'store', s['id'], s['name'])
            db.commit()
        return s

    def stores_import_seed(self, admin):
        seed = HERE / 'stores_seed.json'
        if not seed.exists():
            raise ApiError(404, 'stores_seed.json tidak ada.')
        items = json.loads(seed.read_text(encoding='utf8')).get('stores', [])
        n = 0
        with self.store.lock, self.store.connect() as db:
            for raw in items:
                s = self._store_clean(raw, str(raw['id']))
                if db.execute('SELECT 1 FROM stores WHERE id=?', (s['id'],)).fetchone():
                    continue
                db.execute(
                    'INSERT INTO stores VALUES (:id,:name,:mall,:city,:province,:address,:phone,:lat,:lng,'
                    ':open_hour,:close_hour,:services)', s)
                n += 1
            self.audit(db, admin, 'import', 'store', '', f'{n} toko dari seed')
            db.commit()
        return {'imported': n}

    def delete_simple(self, admin, table, key, value, entity):
        with self.store.lock, self.store.connect() as db:
            cur = db.execute(f'DELETE FROM {table} WHERE {key}=?', (value,))
            if cur.rowcount == 0:
                raise ApiError(404, 'Data tidak ditemukan.')
            self.audit(db, admin, 'delete', entity, value)
            db.commit()
        return {'ok': True}

    # ------------------------------------------------------------ feedback
    def feedback_list(self, q):
        page, per, off = self._page(q)
        where, args = [], []
        act = q.get('action', [''])[0]
        if act:
            where.append('f.action=?')
            args.append(act)
        text = (q.get('q', [''])[0] or '').strip()
        if text:
            where.append('(p.name LIKE ? OR u.email LIKE ?)')
            args += [f'%{text}%'] * 2
        sw = ('WHERE ' + ' AND '.join(where)) if where else ''
        base = 'FROM feedback f JOIN products p ON p.id=f.product_id JOIN users u ON u.id=f.user_id ' + sw
        with self.store.connect() as db:
            total = db.execute('SELECT COUNT(*) ' + base, args).fetchone()[0]
            rows = db.execute('SELECT f.id,f.action,f.created_at,f.status,f.admin_note,p.id AS product_id,p.name AS product,u.email '
                              + base + ' ORDER BY f.id DESC LIMIT ? OFFSET ?', args + [per, off]).fetchall()
        return {'items': [dict(r) for r in rows], 'total': total, 'page': page, 'per_page': per}

    def audit_list(self, q):
        page, per, off = self._page(q)
        with self.store.connect() as db:
            total = db.execute('SELECT COUNT(*) FROM audit_log').fetchone()[0]
            rows = db.execute('SELECT * FROM audit_log ORDER BY id DESC LIMIT ? OFFSET ?', (per, off)).fetchall()
        return {'items': [dict(r) for r in rows], 'total': total, 'page': page, 'per_page': per}

    def data_table_list(self, name, q):
        """Daftar baca-saja untuk tabel operasional yang aman ditampilkan admin."""
        page, per, off = self._page(q)
        search = (q.get('q', [''])[0] or '').strip()
        configs = {
            'variants': ('''SELECT v.id,v.product_id,p.name AS product_name,v.color_code,v.color_name,v.size,v.price,v.original_price
                FROM product_variants v LEFT JOIN products p ON p.id=v.product_id''',
                'v.product_id LIKE ? OR p.name LIKE ? OR v.color_code LIKE ? OR v.size LIKE ?', 'v.id DESC'),
            'orders': ('''SELECT o.id,o.order_date,o.subtotal,o.total_price,o.payment_method,o.payment_status,o.order_status,
                u.name AS customer,u.email,COUNT(oi.id) AS item_count FROM orders o JOIN users u ON u.id=o.user_id
                LEFT JOIN order_items oi ON oi.order_id=o.id''',
                'o.id LIKE ? OR u.name LIKE ? OR u.email LIKE ?', 'o.order_date DESC,o.id DESC'),
            'order-items': ('''SELECT i.id,i.order_id,i.product_name,i.size,i.price,i.quantity,i.subtotal,
                u.email,o.order_date FROM order_items i JOIN orders o ON o.id=i.order_id JOIN users u ON u.id=o.user_id''',
                'i.order_id LIKE ? OR i.product_name LIKE ? OR u.email LIKE ?', 'i.id DESC'),
            'addresses': ('''SELECT a.id,a.user_id,a.recipient_name,a.phone,a.address,a.city,a.postal_code,a.label,a.is_default,a.created_at,
                u.name AS customer,u.email FROM addresses a JOIN users u ON u.id=a.user_id''',
                'a.recipient_name LIKE ? OR a.address LIKE ? OR u.email LIKE ?', 'a.id DESC'),
            'cart': ('''SELECT c.id,c.product_id,p.name AS product_name,c.color_code,c.size,c.quantity,c.is_selected,c.updated_at,
                u.name AS customer,u.email FROM cart_items c JOIN users u ON u.id=c.user_id LEFT JOIN products p ON p.id=c.product_id''',
                'p.name LIKE ? OR u.name LIKE ? OR u.email LIKE ?', 'c.updated_at DESC,c.id DESC'),
            'wishlist': ('''SELECT w.id,w.product_id,p.name AS product_name,w.created_at,u.name AS customer,u.email
                FROM wishlist w JOIN users u ON u.id=w.user_id LEFT JOIN products p ON p.id=w.product_id''',
                'p.name LIKE ? OR u.name LIKE ? OR u.email LIKE ?', 'w.id DESC'),
            'activities': ('''SELECT a.id,a.activity_type,a.title,a.detail,a.points,a.created_at,u.name AS customer,u.email
                FROM member_activities a JOIN users u ON u.id=a.user_id''',
                'a.title LIKE ? OR a.detail LIKE ? OR u.email LIKE ?', 'a.created_at DESC,a.id DESC'),
            'points': ('''SELECT p.id,p.order_id,p.points_delta,p.reason,p.created_at,u.name AS customer,u.email
                FROM member_points p JOIN users u ON u.id=p.user_id''',
                'p.reason LIKE ? OR u.name LIKE ? OR u.email LIKE ?', 'p.id DESC'),
            'profiles': ('''SELECT s.user_id,s.updated_at,s.profile_json,s.model_json,u.name AS customer,u.email
                FROM style_profiles s JOIN users u ON u.id=s.user_id''',
                'u.name LIKE ? OR u.email LIKE ? OR s.profile_json LIKE ?', 's.updated_at DESC'),
            'reviews': ('''SELECT r.id,r.product_id,p.name AS product_name,r.author,r.rating,r.review_text,r.created_at,r.source,r.is_visible,r.moderation_note,u.email
                FROM reviews r JOIN users u ON u.id=r.user_id JOIN products p ON p.id=r.product_id''',
                'p.name LIKE ? OR r.author LIKE ? OR r.review_text LIKE ? OR u.email LIKE ?', 'r.created_at DESC'),
        }
        if name not in configs:
            raise ApiError(404, 'Tabel data tidak tersedia.')
        base, search_sql, order = configs[name]
        conditions = []
        args = []
        if search:
            conditions.append('(' + search_sql + ')')
            args += [f'%{search}%'] * search_sql.count('?')
        if name == 'orders':
            order_status = (q.get('order_status', [''])[0] or '').strip()
            payment_status = (q.get('payment_status', [''])[0] or '').strip()
            payment_method = (q.get('payment_method', [''])[0] or '').strip()
            if order_status:
                conditions.append('o.order_status=?'); args.append(order_status)
            if payment_status:
                conditions.append('o.payment_status=?'); args.append(payment_status)
            if payment_method:
                conditions.append('o.payment_method=?'); args.append(payment_method)
        where = (' WHERE ' + ' AND '.join(conditions)) if conditions else ''
        with self.store.connect() as db:
            # Count over the same joined source, applying the search predicate.
            if name == 'orders':
                count_sql = 'SELECT COUNT(DISTINCT o.id) FROM orders o JOIN users u ON u.id=o.user_id LEFT JOIN order_items oi ON oi.order_id=o.id' + where
                total = db.execute(count_sql, args).fetchone()[0]
                rows_sql = base + where + ' GROUP BY o.id ORDER BY ' + order + ' LIMIT ? OFFSET ?'
            else:
                count_sql = 'SELECT COUNT(*) FROM (' + base + where + ') AS data'
                total = db.execute(count_sql, args).fetchone()[0]
                rows_sql = base + where + ' ORDER BY ' + order + ' LIMIT ? OFFSET ?'
            rows = db.execute(rows_sql, args + [per, off]).fetchall()
        items = []
        for row in rows:
            item = dict(row)
            if name == 'profiles':
                try: item['profile'] = json.loads(item.pop('profile_json') or '{}')
                except (ValueError, TypeError): item['profile'] = {}
                try: item['model'] = json.loads(item.pop('model_json') or '{}')
                except (ValueError, TypeError): item['model'] = {}
                item.pop('profile_json', None); item.pop('model_json', None)
            items.append(item)
        return {'items': items, 'total': total, 'page': page, 'per_page': per}

    # --------------------------------------------------------- akun admin
    def admins_list(self):
        with self.store.connect() as db:
            return {'items': [self._admin_dict(r) for r in db.execute('SELECT * FROM admins ORDER BY id')]}

    def admin_create(self, admin, data):
        username = _text(data.get('username'), 'Username', maxlen=40).lower()
        password = str(data.get('password') or '')
        role = data.get('role') or 'admin'
        if role not in ('admin', 'owner'):
            raise ApiError(400, 'Peran hanya Admin atau Owner.')
        if len(password) < 8:
            raise ApiError(400, 'Password admin minimal 8 karakter.')
        salt = secrets.token_hex(16)
        with self.store.lock, self.store.connect() as db:
            try:
                db.execute('INSERT INTO admins (username,name,password_hash,salt,role,created_at) VALUES (?,?,?,?,?,?)',
                           (username, _text(data.get('name'), 'Nama', required=False), _hash(password, salt), salt,
                            role, _now()))
            except sqlite3.IntegrityError:
                raise ApiError(409, 'Username sudah dipakai.')
            self.audit(db, admin, 'create', 'admin', username, role)
            db.commit()
        return {'ok': True}

    def admin_update(self, admin, aid, data):
        with self.store.lock, self.store.connect() as db:
            row = db.execute('SELECT * FROM admins WHERE id=?', (aid,)).fetchone()
            if not row:
                raise ApiError(404, 'Admin tidak ditemukan.')
            role = data.get('role', row['role'])
            active = _bool(data.get('active', row['active']))
            if role not in ('admin', 'owner'):
                raise ApiError(400, 'Peran hanya Admin atau Owner.')
            if row['role'] == 'owner' and (role != 'owner' or not active):
                owners = db.execute("SELECT COUNT(*) FROM admins WHERE role='owner' AND active=1").fetchone()[0]
                if owners <= 1:
                    raise ApiError(400, 'Owner terakhir tidak boleh diturunkan atau dinonaktifkan.')
            if row['id'] == admin['id'] and (role != 'owner' or not active):
                raise ApiError(400, 'Anda tidak bisa menurunkan atau menonaktifkan akun sendiri.')
            fields, args = ['role=?', 'active=?', 'name=?'], [role, active, _text(data.get('name', row['name']), 'Nama', required=False)]
            pw = data.get('password')
            if pw:
                if len(str(pw)) < 8:
                    raise ApiError(400, 'Password admin minimal 8 karakter.')
                salt = secrets.token_hex(16)
                fields += ['password_hash=?', 'salt=?']
                args += [_hash(str(pw), salt), salt]
            db.execute(f'UPDATE admins SET {",".join(fields)} WHERE id=?', args + [aid])
            if pw or not active:
                db.execute('DELETE FROM admin_sessions WHERE admin_id=?', (aid,))
            self.audit(db, admin, 'update', 'admin', aid, role)
            db.commit()
        return {'ok': True}

    def change_own_password(self, admin, old, new):
        with self.store.lock, self.store.connect() as db:
            row = db.execute('SELECT * FROM admins WHERE id=?', (admin['id'],)).fetchone()
            if not hmac.compare_digest(_hash(old or '', row['salt']), row['password_hash']):
                raise ApiError(400, 'Password lama salah.')
            if len(new or '') < 8:
                raise ApiError(400, 'Password baru minimal 8 karakter.')
            salt = secrets.token_hex(16)
            db.execute('UPDATE admins SET password_hash=?, salt=? WHERE id=?', (_hash(new, salt), salt, admin['id']))
            self.audit(db, admin, 'change_password', 'admin', admin['id'])
            db.commit()
        return {'ok': True}

    # ------------------------------------------------------------- model ML
    KNOWN_COMPONENTS = ('tone_color', 'color_pair', 'color_market', 'face_shape', 'skin_depth')

    @classmethod
    def validate_model(cls, m):
        if not isinstance(m, dict) or m.get('schema') != 1:
            raise ApiError(400, 'model.json tidak valid: field schema harus 1.')
        comps = m.get('components')
        if not isinstance(comps, dict) or not comps:
            raise ApiError(400, 'model.json tidak punya components.')
        for k, v in comps.items():
            if k not in cls.KNOWN_COMPONENTS:
                raise ApiError(400, f'Komponen tidak dikenal: {k}')
            if not isinstance(v, dict) or not v.get('source'):
                raise ApiError(400, f'Komponen {k} wajib punya field source.')
        tc = comps.get('tone_color')
        if tc:
            for u in ('warm', 'cool', 'neutral'):
                for d in ('light', 'medium', 'deep'):
                    row = tc.get('table', {}).get(u, {}).get(d)
                    if not isinstance(row, dict) or len(row) < 10:
                        raise ApiError(400, f'tone_color.table.{u}.{d} tidak lengkap (butuh 10 keluarga warna).')
        fs = comps.get('face_shape')
        if fs:
            n, k = len(fs.get('features', [])), len(fs.get('labels', []))
            if n != 5 or k < 2 or len(fs.get('W', [])) != k or any(len(r) != n for r in fs['W']) \
                    or len(fs.get('b', [])) != k or len(fs.get('mean', [])) != n or len(fs.get('std', [])) != n:
                raise ApiError(400, 'Dimensi face_shape tidak konsisten (5 fitur x kelas).')
        sd = comps.get('skin_depth')
        if sd and not (isinstance(sd.get('ita_light'), (int, float)) and isinstance(sd.get('ita_deep'), (int, float))
                       and sd['ita_light'] > sd['ita_deep']):
            raise ApiError(400, 'skin_depth butuh ita_light > ita_deep.')
        if not isinstance(m.get('datasets'), list):
            raise ApiError(400, 'model.json wajib mencantumkan datasets (bukti data).')

    def models_list(self):
        with self.store.connect() as db:
            rows = db.execute('SELECT id,version,origin,note,created_at,active,model_json FROM ml_models '
                              'ORDER BY id DESC').fetchall()
        out = []
        for r in rows:
            m = json.loads(r['model_json'])
            out.append({'id': r['id'], 'version': r['version'], 'origin': r['origin'], 'note': r['note'],
                        'created_at': r['created_at'], 'active': bool(r['active']),
                        'sources': {k: v.get('source') for k, v in m.get('components', {}).items()},
                        'datasets': [{'name': d.get('name'), 'kind': d.get('kind'), 'rows': d.get('rows')}
                                     for d in m.get('datasets', [])]})
        return {'items': out}

    def model_get(self, mid):
        with self.store.connect() as db:
            r = db.execute('SELECT * FROM ml_models WHERE id=?', (mid,)).fetchone()
        if not r:
            raise ApiError(404, 'Model tidak ditemukan.')
        return {'id': r['id'], 'version': r['version'], 'origin': r['origin'], 'note': r['note'],
                'active': bool(r['active']), 'model': json.loads(r['model_json']), 'report': r['report_md']}

    def _insert_model(self, db, admin, model, report, origin, note, activate):
        cur = db.execute('INSERT INTO ml_models (version,origin,note,created_at,model_json,report_md,active) '
                         'VALUES (?,?,?,?,?,?,0)',
                         (str(model.get('version', '?')), origin, note, _now(), json.dumps(model, ensure_ascii=False),
                          report or ''))
        mid = cur.lastrowid
        if activate:
            db.execute('UPDATE ml_models SET active=0')
            db.execute('UPDATE ml_models SET active=1 WHERE id=?', (mid,))
        self.audit(db, admin, 'create', 'ml_model', mid, f'{origin} {model.get("version")}')
        return mid

    def model_upload(self, admin, data):
        model = data.get('model')
        self.validate_model(model)
        with self.store.lock, self.store.connect() as db:
            mid = self._insert_model(db, admin, model, str(data.get('report') or ''), 'upload',
                                     _text(data.get('note'), 'Catatan', required=False, maxlen=300),
                                     _bool(data.get('activate')))
            db.commit()
        return {'id': mid}

    def model_activate(self, admin, mid):
        with self.store.lock, self.store.connect() as db:
            if not db.execute('SELECT 1 FROM ml_models WHERE id=?', (mid,)).fetchone():
                raise ApiError(404, 'Model tidak ditemukan.')
            db.execute('UPDATE ml_models SET active=0')
            db.execute('UPDATE ml_models SET active=1 WHERE id=?', (mid,))
            self.audit(db, admin, 'activate', 'ml_model', mid)
            db.commit()
        return {'ok': True}

    def model_deactivate(self, admin):
        with self.store.lock, self.store.connect() as db:
            db.execute('UPDATE ml_models SET active=0')
            self.audit(db, admin, 'deactivate', 'ml_model', '', 'kembali ke model bawaan aplikasi')
            db.commit()
        return {'ok': True}

    def model_delete(self, admin, mid):
        with self.store.lock, self.store.connect() as db:
            r = db.execute('SELECT active FROM ml_models WHERE id=?', (mid,)).fetchone()
            if not r:
                raise ApiError(404, 'Model tidak ditemukan.')
            if r['active']:
                raise ApiError(400, 'Model aktif tidak bisa dihapus. Aktifkan model lain dulu.')
            db.execute('DELETE FROM ml_models WHERE id=?', (mid,))
            self.audit(db, admin, 'delete', 'ml_model', mid)
            db.commit()
        return {'ok': True}

    def active_model(self):
        """Model untuk aplikasi: yang aktif di database, jika tidak ada model bawaan."""
        with self.store.connect() as db:
            r = db.execute('SELECT model_json FROM ml_models WHERE active=1').fetchone()
        if r:
            return json.loads(r['model_json'])
        if BUNDLED_MODEL.exists():
            return json.loads(BUNDLED_MODEL.read_text(encoding='utf8'))
        return None

    def ml_status(self):
        deps = subprocess.run([sys.executable, '-c', 'import numpy,pandas,sklearn,PIL'], capture_output=True)
        raw = []
        if ML_RAW.exists():
            for p in sorted(ML_RAW.iterdir()):
                size = sum(f.stat().st_size for f in p.rglob('*') if f.is_file()) if p.is_dir() else p.stat().st_size
                raw.append({'name': p.name, 'dir': p.is_dir(), 'size': size})
        with self.store.connect() as db:
            n_fb = db.execute("SELECT COUNT(*) FROM feedback f JOIN style_profiles s ON s.user_id=f.user_id "
                              "WHERE f.action IN ('like','dislike','cart')").fetchone()[0]
        return {'python_deps_ok': deps.returncode == 0, 'python': sys.executable,
                'train_script': (ML_DIR / 'train.py').exists(), 'raw_files': raw, 'trainable_feedback_rows': n_fb}

    def _raw_path(self, name, want_dir):
        if not name:
            return None
        p = (ML_RAW / name).resolve()
        if ML_RAW.resolve() not in p.parents and p != ML_RAW.resolve():
            raise ApiError(400, 'Path data tidak valid.')
        if not p.exists() or p.is_dir() != want_dir:
            raise ApiError(400, f'{"Folder" if want_dir else "Berkas"} tidak ditemukan di ml/data/raw: {name}')
        return str(p)

    def model_train(self, admin, data):
        if not (ML_DIR / 'train.py').exists():
            raise ApiError(500, 'ml/train.py tidak ditemukan.')
        if not self.train_lock.acquire(blocking=False):
            raise ApiError(409, 'Pelatihan lain sedang berjalan.')
        try:
            import tempfile
            out = tempfile.mkdtemp(prefix='uplus_train_')
            cmd = [sys.executable, str(ML_DIR / 'train.py'), '--out', out]
            if data.get('use_feedback', True):
                cmd += ['--db', self.store.path]
            for key, flag, is_dir in (('styles', '--styles', False), ('faces', '--faces', True),
                                      ('skin_csv', '--skin-csv', False), ('pairs', '--pairs', False)):
                p = self._raw_path(str(data.get(key) or ''), is_dir)
                if p:
                    cmd += [flag, p]
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
            if proc.returncode != 0:
                raise ApiError(500, 'Pelatihan gagal: ' + (proc.stderr or proc.stdout)[-600:])
            model = json.loads((Path(out) / 'model.json').read_text(encoding='utf8'))
            report = (Path(out) / 'REPORT.md').read_text(encoding='utf8')
            self.validate_model(model)
            with self.store.lock, self.store.connect() as db:
                mid = self._insert_model(db, admin, model, report, 'trained',
                                         _text(data.get('note'), 'Catatan', required=False, maxlen=300),
                                         _bool(data.get('activate')))
                db.commit()
            return {'id': mid, 'version': model['version'], 'log': proc.stdout[-800:]}
        except subprocess.TimeoutExpired:
            raise ApiError(504, 'Pelatihan melewati batas waktu 30 menit.')
        finally:
            self.train_lock.release()


def _hash_user(password, salt):
    """Sama dengan Store._hash di server.py (120.000 iterasi) untuk akun member."""
    return hashlib.pbkdf2_hmac('sha256', password.encode('utf8'), bytes.fromhex(salt), 120_000).hex()


# =============================================================== routing HTTP
def handle(admin, h, method):
    """Menangani satu permintaan /admin*. [h] adalah BaseHTTPRequestHandler."""
    from urllib.parse import urlparse
    parsed = urlparse(h.path)
    path = parsed.path.rstrip('/') or '/'
    q = parse_qs(parsed.query)

    if method == 'GET' and path in ('/admin',):
        return _send_html(h)

    try:
        body = {}
        if method in ('POST', 'PUT', 'DELETE'):
            length = int(h.headers.get('Content-Length') or 0)
            if length > 20_000_000:
                raise ApiError(413, 'Data terlalu besar.')
            if length > 0:
                try:
                    body = json.loads(h.rfile.read(length).decode('utf8'))
                except (ValueError, UnicodeDecodeError):
                    raise ApiError(400, 'Body JSON tidak valid.')
                if not isinstance(body, dict):
                    raise ApiError(400, 'Body harus berupa objek JSON.')
        result = _route(admin, h, method, path, q, body)
        return _send_json(h, 200, result)
    except ApiError as e:
        return _send_json(h, e.status, {'error': e.message})
    except Exception as e:  # jangan bocorkan detail internal
        print('Admin error:', repr(e))
        return _send_json(h, 500, {'error': 'Terjadi kesalahan di server.'})


def _route(admin, h, method, path, q, body):
    ip = h.client_address[0]
    if path == '/admin/api/login' and method == 'POST':
        return admin.login(str(body.get('username', '')), str(body.get('password', '')), ip)

    me = admin.admin_for(h.headers.get('Authorization', ''))
    if me is None:
        raise ApiError(401, 'Sesi admin tidak valid. Silakan masuk lagi.')
    write = method in ('POST', 'PUT', 'DELETE')
    if write:
        Admin.need(me, 'admin')

    parts = [p for p in path.split('/') if p][2:]       # buang 'admin','api'
    seg = parts[0] if parts else ''

    if seg == 'logout' and method == 'POST':
        admin.logout(h.headers.get('Authorization', ''))
        return {'ok': True}
    if seg == 'me':
        if method == 'PUT':
            return admin.change_own_password(me, body.get('old_password'), body.get('new_password'))
        return {'admin': admin._admin_dict(me)}
    if seg == 'dashboard':
        return admin.dashboard()

    if seg == 'products':
        if len(parts) == 1:
            if method == 'GET':
                return admin.products_list(q)
            if method == 'POST':
                return admin.product_create(me, body)
        if len(parts) == 2 and parts[1] == 'bulk' and method == 'POST':
            return admin.product_bulk(me, body)
        if len(parts) == 2 and parts[1] == 'export' and method == 'GET':
            return {'products': admin.product_export()}
        if len(parts) == 2:
            pid = _unq(parts[1])
            if method == 'PUT':
                return admin.product_update(me, pid, body)
            if method == 'DELETE':
                return admin.product_delete(me, pid)

    if seg == 'users':
        if len(parts) == 1 and method == 'GET':
            return admin.users_list(q)
        if len(parts) >= 2:
            uid = int(parts[1]) if parts[1].isdigit() else -1
            if len(parts) == 2 and method == 'GET':
                return admin.user_get(uid)
            if len(parts) == 2 and method == 'PUT':
                return admin.user_update(me, uid, body)
            if len(parts) == 3 and parts[2] == 'reset-password' and method == 'POST':
                Admin.need(me, 'owner')
                return admin.user_reset_password(me, uid)

    for name, lister, saver, table, key in (
            ('vouchers', admin.vouchers_list, admin.voucher_save, 'vouchers', 'code'),
            ('news', admin.news_list, admin.news_save, 'news', 'id'),
            ('stores', admin.stores_list, admin.store_save, 'stores', 'id')):
        if seg != name:
            continue
        if len(parts) == 1 and method == 'GET':
            return lister()
        if len(parts) == 1 and method == 'POST':
            return saver(me, body)
        if name == 'stores' and len(parts) == 2 and parts[1] == 'import-seed' and method == 'POST':
            return admin.stores_import_seed(me)
        if len(parts) == 2 and method == 'PUT':
            return saver(me, body, _unq(parts[1]))
        if len(parts) == 2 and method == 'DELETE':
            return admin.delete_simple(me, table, key, _unq(parts[1]), name.rstrip('s'))

    if seg == 'data' and len(parts) == 2 and method == 'GET':
        return admin.data_table_list(parts[1], q)

    if seg == 'feedback' and method == 'GET':
        return admin.feedback_list(q)
    if seg == 'audit' and method == 'GET':
        return admin.audit_list(q)

    if seg == 'admins':
        Admin.need(me, 'owner')
        if len(parts) == 1 and method == 'GET':
            return admin.admins_list()
        if len(parts) == 1 and method == 'POST':
            return admin.admin_create(me, body)
        if len(parts) == 2 and method == 'PUT' and parts[1].isdigit():
            return admin.admin_update(me, int(parts[1]), body)

    if seg == 'ml':
        sub = parts[1] if len(parts) > 1 else ''
        if sub == 'status' and method == 'GET':
            return admin.ml_status()
        if sub == 'models':
            if len(parts) == 2 and method == 'GET':
                return admin.models_list()
            if len(parts) == 2 and method == 'POST':
                return admin.model_upload(me, body)
            if len(parts) >= 3 and parts[2].isdigit():
                mid = int(parts[2])
                if len(parts) == 3 and method == 'GET':
                    return admin.model_get(mid)
                if len(parts) == 3 and method == 'DELETE':
                    return admin.model_delete(me, mid)
                if len(parts) == 4 and parts[3] == 'activate' and method == 'POST':
                    return admin.model_activate(me, mid)
            if len(parts) == 3 and parts[2] == 'deactivate' and method == 'POST':
                return admin.model_deactivate(me)
        if sub == 'train' and method == 'POST':
            Admin.need(me, 'owner')
            return admin.model_train(me, body)

    try:
        import feature_extensions
        extra = feature_extensions.admin_handle(admin, me, method, path, q, body)
        if extra is not None:
            return extra
    except ImportError:
        pass
    raise ApiError(404, 'Endpoint admin tidak ditemukan.')


def _unq(s):
    from urllib.parse import unquote
    return unquote(s)


def _send_json(h, status, payload):
    body = json.dumps(payload, ensure_ascii=False).encode('utf8')
    h.send_response(status)
    h.send_header('Content-Type', 'application/json; charset=utf-8')
    h.send_header('Content-Length', str(len(body)))
    h.send_header('Cache-Control', 'no-store')
    h.send_header('X-Content-Type-Options', 'nosniff')
    h.end_headers()
    h.wfile.write(body)


def _send_html(h):
    body = UI_FILE.read_bytes() if UI_FILE.exists() else b'<h1>admin_ui.html tidak ditemukan</h1>'
    h.send_response(200)
    h.send_header('Content-Type', 'text/html; charset=utf-8')
    h.send_header('Content-Length', str(len(body)))
    h.send_header('Cache-Control', 'no-store')
    h.send_header('X-Frame-Options', 'DENY')
    h.send_header('X-Content-Type-Options', 'nosniff')
    h.send_header('Referrer-Policy', 'no-referrer')
    h.send_header('Content-Security-Policy',
                  "default-src 'self'; img-src 'self' https: data:; style-src 'self' 'unsafe-inline'; "
                  "script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'")
    h.end_headers()
    h.wfile.write(body)
