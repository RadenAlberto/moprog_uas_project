# Audit Awal Integrasi Database — UNIQLO PLUS

Tanggal pemeriksaan: 21 November 2026

Dokumen ini mencatat kondisi proyek sebelum perubahan integrasi database. Audit dilakukan pada kode Flutter, backend Python, database SQLite yang disertakan, dan control panel admin.

## 1. Temuan utama

Proyek memiliki dua mekanisme penyimpanan yang berbeda:

1. **Database server**: `backend/uniqlo_plus.sqlite3`, diakses oleh `backend/server.py` dan `backend/admin.py`.
2. **Database lokal Flutter**: skema didefinisikan di `lib/DATABASE/db_helper.dart`.

Pencarian referensi kode menemukan `DBHelper` hanya didefinisikan di `db_helper.dart`; belum ditemukan pemanggilan `DBHelper` dari file Dart lain. Karena itu, tabel lokal yang didefinisikan di sana belum terbukti dipakai oleh fitur aplikasi.

Aplikasi saat ini tetap dapat berjalan offline. Keranjang dan wishlist dikelola oleh `AppState` melalui `KeyValueStore`/`SharedPreferences`. Akun, pesanan, poin, dan aktivitas dikelola oleh `AuthProvider` melalui penyimpanan lokal. Backend hanya menerima sinkronisasi akun saat login/registrasi, profil gaya, katalog, dan feedback sesuai endpoint yang tersedia.

## 2. Isi database server saat file ZIP diperiksa

| Tabel | Jumlah baris |
|---|---:|
| products | 1.376 |
| product_variants | 16.775 |
| admins | 2 |
| admin_sessions | 2 |
| users | 0 |
| tokens | 0 |
| style_profiles | 0 |
| feedback | 0 |
| login_attempts | 0 |
| audit_log | 0 |
| vouchers | 0 |
| news | 0 |
| stores | 0 |
| ml_models | 0 |

Database server belum memiliki tabel transaksi seperti `cart_items`, `wishlist`, `addresses`, `orders`, `order_items`, dan `payments`.

## 3. Endpoint backend yang sudah tersedia

- `GET /api/health`
- `GET /api/products`
- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/me`
- `GET/PUT /api/profile`
- `POST /api/feedback`
- `GET /api/popularity`
- `GET /api/ml/model`
- `GET /api/vouchers`
- `GET /api/news`
- `GET /api/stores`

Belum ada endpoint untuk menyimpan keranjang, wishlist, alamat, pesanan, pembayaran, atau poin membership.

## 4. Temuan risiko yang perlu ditangani

### 4.1 Migrasi database lokal berpotensi menghapus data

`lib/DATABASE/db_helper.dart` menetapkan versi database lokal 2. Pada `onUpgrade`, kode menonaktifkan foreign key lalu menghapus tabel `order_items`, `orders`, `cart_items`, `wishlist`, `addresses`, `product_variants`, `products`, `categories`, dan `users`, kemudian membuat ulang tabel.

Ini berpotensi menghapus akun dan data belanja lokal ketika database lama di-upgrade. Migrasi pengganti harus dirancang berdasarkan skema versi lama dan diuji dengan salinan database. Jangan menjalankan migrasi destruktif pada data asli.

### 4.2 Penyimpanan transaksi masih lokal

`AppState` menyimpan keranjang dan wishlist dalam `KeyValueStore`. `AuthProvider` menyimpan member, pesanan, poin, dan aktivitas secara lokal. Karena belum ada API transaksi di server, data tersebut tidak akan muncul pada database server atau control panel.

### 4.3 Password akun lokal dan server memakai mekanisme berbeda

`AuthProvider` membuat hash SHA-256 lokal, sedangkan backend memakai PBKDF2-SHA256 dengan salt. Backend mempunyai autentikasi terpisah. Integrasi login saat ini mencoba menyamakan akun lokal dengan akun server, tetapi data pesanan dan poin belum disinkronkan.

### 4.4 Control panel belum memiliki Database Viewer umum

`admin_ui.html` menampilkan dashboard dan menu pengelolaan tertentu, bukan daftar seluruh tabel SQLite. Fitur Database Viewer perlu dibuat dengan endpoint admin read-only, daftar tabel yang diizinkan, pagination, dan pembatasan kolom sensitif.

### 4.5 Dokumentasi port control panel

`server.py` menjalankan API dan control panel pada server/port yang sama. Port bawaan adalah `8000`, sehingga alamat bawaan control panel adalah `http://localhost:8000/admin`. Dokumentasi backend telah diperbaiki agar sesuai.

## 5. Perubahan aman pada tahap audit awal

- Memperbaiki pengelolaan koneksi SQLite pada `Store.connect()`: koneksi kini ditutup secara eksplisit setelah transaksi selesai. Context manager bawaan `sqlite3.Connection` melakukan commit/rollback, tetapi tidak menutup koneksi.
- Memperbaiki alamat control panel bawaan dalam dokumentasi backend dari port 8080 menjadi 8000.
- Tidak mengubah isi database, tidak menghapus tabel, dan belum menambahkan tabel transaksi sebelum rancangan relasi disepakati.

## 6. Rencana implementasi berikutnya

Urutan yang disarankan:

1. Tetapkan database server sebagai sumber data utama untuk akun dan transaksi yang perlu terlihat di control panel.
2. Rancang tabel dan relasi server: cart, wishlist, addresses, orders, order_items, payments, dan membership/points.
3. Buat migrasi SQLite yang bersifat additive (`CREATE TABLE IF NOT EXISTS`/penambahan kolom yang tervalidasi), dengan backup dan pengujian.
4. Buat endpoint terautentikasi untuk operasi data tersebut.
5. Hubungkan `AppState` dan `AuthProvider` ke API server dengan penanganan offline/sinkronisasi yang jelas.
6. Tambahkan Database Viewer read-only pada control panel.
7. Uji alur end-to-end: registrasi, login, keranjang, wishlist, checkout, pembayaran simulasi, pembatalan, poin, dan tampilan admin.

**Catatan:** jangan menghapus atau mengganti database lokal/server yang sudah ada. Buat backup sebelum menjalankan migrasi apa pun.

## 7. Implementasi lanjutan pada revisi ini

- Backend kini menambahkan tabel server `addresses`, `wishlist`, `cart_items`, `orders`, `order_items`, `member_activities`, dan `member_points` dengan foreign key ke member/produk.
- Tabel `users` diperluas secara additive dengan `address`, `member_code`, `bonus_points`, `last_check_in_day`, dan `check_in_streak`; migrasi tidak menghapus akun lama.
- Flutter mengirim atribut member saat register/login dan memperbarui atribut profil dasar melalui `PUT /api/me`.
- `ApiService` menyediakan `POST /api/member/sync`; provider Flutter memanggilnya saat keranjang, wishlist, pesanan, aktivitas, atau poin berubah. Snapshot disimpan ke tabel transaksi server dalam satu transaksi SQLite.
- Data transaksi yang disinkronkan adalah snapshot per member. Sinkronisasi unduh/pemulihan snapshot server ke perangkat baru belum diterapkan pada revisi ini; data lokal yang sudah ada tidak otomatis dihapus.
- Akun admin `admin` bawaan pada database contoh dihapus; akun `david` dipertahankan. Pembuatan akun baru kini eksplisit melalui `python buat_admin.py USERNAME` dengan password tersembunyi.
- Pengujian backend server dan admin lulus setelah perubahan. Flutter SDK tidak tersedia pada lingkungan revisi ini, sehingga `flutter analyze` dan pengujian perangkat belum dapat dijalankan.
