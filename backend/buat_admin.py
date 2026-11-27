#!/usr/bin/env python3
"""Buat/reset akun owner control panel secara eksplisit.

Pemakaian:
  python buat_admin.py USERNAME [nama_database]
Password diminta via prompt tersembunyi; tidak ada kredensial bawaan.
"""
import getpass
import secrets
import sqlite3
import sys
from pathlib import Path

import admin as A
import server

if len(sys.argv) < 2:
    raise SystemExit('Pemakaian: python buat_admin.py USERNAME [nama_database]')
username = sys.argv[1].strip()
if not username:
    raise SystemExit('Username tidak boleh kosong.')
db_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).parent / 'uniqlo_plus.sqlite3'
password = getpass.getpass('Password admin (minimal 8 karakter): ')
confirm = getpass.getpass('Ulangi password: ')
if len(password) < 8:
    raise SystemExit('Password minimal 8 karakter.')
if password != confirm:
    raise SystemExit('Konfirmasi password tidak cocok.')

# Pastikan skema tersedia tanpa memulai server permanen.
httpd = server.make_server('127.0.0.1', 0, db_path)
httpd.server_close()
salt = secrets.token_hex(16)
hashed = A._hash(password, salt)
with sqlite3.connect(db_path) as db:
    row = db.execute('SELECT id FROM admins WHERE lower(username)=lower(?)', (username,)).fetchone()
    if row:
        db.execute('UPDATE admins SET name=?,password_hash=?,salt=?,role="owner",active=1 WHERE id=?',
                   (username, hashed, salt, row[0]))
        print('Akun admin diperbarui dan diaktifkan.')
    else:
        db.execute('INSERT INTO admins (username,name,password_hash,salt,role,active,created_at) VALUES (?,?,?,?,?,1,?)',
                   (username, username, hashed, salt, 'owner', A._now()))
        print('Akun admin berhasil dibuat.')
    db.execute('DELETE FROM login_attempts')
print(f'Username: {username}\nPeran: owner\nDatabase: {db_path}')
