# UNIQLO+ Backend

Python standard library + SQLite. Backend adalah sumber data utama untuk akun member, transaksi, poin/level, alamat, ulasan, dan konten aplikasi.

## Menjalankan

Windows (sesuai environment project):

```cmd
C:\msys64\mingw64\bin\python.exe server.py
```

Atau:

```cmd
python server.py
```

Server: `http://localhost:8000`  
Admin Control Panel: `http://localhost:8000/admin`

Database default: `backend/uniqlo_plus.sqlite3`.

## Akun admin

Tidak ada password default yang dibuat otomatis. Untuk membuat akun Owner baru:

```cmd
C:\msys64\mingw64\bin\python.exe buat_admin.py USERNAME_KAMU
```

Script meminta password dua kali melalui prompt tersembunyi. Password minimal 8 karakter. Script membuat Owner baru atau memperbarui akun dengan username yang sama. Akun Owner yang sudah ada tidak dihapus.

Role hanya dua:

- **Owner**: semua hak Admin, ditambah pengelolaan akun Admin/Owner dan role.
- **Admin**: mengelola konten dan operasional member/pesanan, tetapi tidak dapat mengelola akun admin atau role.

Owner yang menghapus Owner lain harus memasukkan password akun Owner yang sedang login. Sistem menolak penghapusan akun sendiri dan Owner terakhir. Semua perubahan dicatat di `audit_log`.

## Database dan migrasi

Migrasi fitur menggunakan perubahan additive (`ALTER TABLE`, index, dan seed idempotent). Migrasi tidak menghapus akun, katalog, transaksi, atau ulasan yang sudah tersimpan. Sebelum mengganti project, tetap backup `uniqlo_plus.sqlite3`.

Tabel utama:

| Tabel | Fungsi |
|---|---|
| `products`, `product_variants` | Katalog produk dan kombinasi warna/ukuran |
| `users`, `tokens` | Akun member, hash password, dan sesi |
| `addresses` | Banyak alamat per member, satu alamat utama, alamat pesanan tetap disimpan sebagai snapshot |
| `cart_items`, `wishlist` | Keranjang dan wishlist per member |
| `orders`, `order_items` | Pesanan, status pesanan, status pembayaran, dan snapshot item |
| `member_points` | Ledger poin; koreksi selalu menjadi transaksi baru |
| `reviews` | Ulasan member dan contoh (`source=sample` / `member`) serta status moderasi |
| `member_activities`, `feedback` | Aktivitas member dan umpan balik produk |
| `style_profiles` | Profil Style Advisor dan konfigurasi model per member |
| `vouchers`, `news`, `stores` | Konten yang dikelola dari panel admin |
| `admins`, `admin_sessions`, `audit_log` | Akun admin, sesi, dan audit perubahan |
| `ml_models` | Versi model rekomendasi yang dikelola melalui panel |

Database project saat ini berisi 13 member (Valencia dan 12 akun contoh), 1.376 produk, 16.775 varian, dan 4.128 ulasan contoh yang ditautkan ke 12 akun penulis contoh.

## Aturan member, poin, dan level

- Registrasi server menetapkan bonus awal 200 poin; nilai bonus tidak diambil dari input Flutter.
- Check-in dilakukan melalui endpoint server dan hanya bisa sekali per hari. Reward 5 poin hari pertama, naik 2 poin per hari beruntun, maksimal 15.
- Poin belanja hanya diberikan setelah status pesanan `selesai` dan pembayaran `Paid`.
- Rumus poin: 1 poin per Rp10.000 belanja bersih, dikalikan multiplier level saat penyelesaian pesanan (Regular 1.0, Silver 1.25, Gold 1.5, Platinum 2.0).
- Saldo dihitung dari jumlah `points_delta` di `member_points`. Penggunaan poin bernilai negatif; pembatalan/refund menghasilkan transaksi pengembalian/koreksi baru. Baris ledger lama tidak diubah.
- Level berdasarkan total belanja bersih dari pesanan selesai dan tidak direfund: Regular Rp0, Silver Rp1.000.000, Gold Rp3.000.000, Platinum Rp7.500.000.
- Status pesanan dan pembayaran adalah dua field terpisah. Alur status pesanan: `diproses` → `dikemas` → `dikirim` → `selesai`; pesanan dapat dibatalkan sesuai aturan. Status pembayaran diverifikasi dan diubah admin, bukan dipercaya dari snapshot Flutter.

## API member utama

Semua endpoint member berikut memerlukan `Authorization: Bearer <token>`.

| Metode | Path | Keterangan |
|---|---|---|
| POST | `/api/auth/register` | Membuat akun member dan sesi |
| POST | `/api/auth/login` | Login server-first |
| GET | `/api/me` | Data akun |
| PUT | `/api/me` | Memperbarui nama, telepon, alamat profil |
| GET | `/api/member/bootstrap` | Memulihkan akun, alamat, cart, wishlist, order, aktivitas, ledger poin, ulasan, dan ringkasan level |
| POST | `/api/member/sync` | Sinkronisasi cache Flutter; order bersifat insert-only, poin/status tidak dipercaya dari client |
| GET/POST/PUT/DELETE | `/api/addresses` | CRUD buku alamat member |
| POST | `/api/addresses/{id}/default` | Menetapkan alamat utama |
| POST | `/api/orders/{id}/cancel` | Membatalkan pesanan saat masih `diproses` |
| GET | `/api/orders`, `/api/orders/{id}` | Riwayat dan detail pesanan |
| GET | `/api/points` | Saldo, level, dan ledger poin |
| POST | `/api/points/checkin` | Check-in harian server |
| GET | `/api/reviews?product_id={id}` | Ulasan produk yang tampil |
| GET | `/api/reviews?product_id=all` | Ulasan yang tampil untuk cache Flutter |
| POST | `/api/reviews` | Mengirim ulasan member |
| GET/PUT | `/api/profile` | Profil Style Advisor dan model personal |
| POST | `/api/feedback` | Umpan balik rekomendasi |
| GET | `/api/products`, `/api/vouchers`, `/api/news`, `/api/stores` | Katalog dan konten aktif |

## Panel admin

- **Konten**: produk (termasuk varian melalui editor produk), berita, voucher, toko.
- **Member**: daftar/detail member, edit data tertentu, aktif/nonaktif, alamat, Style Advisor (lihat saja), cart/wishlist/aktivitas (lihat saja), ledger poin.
- **Pesanan**: detail snapshot alamat/item, filter status pesanan dan pembayaran, perubahan status dengan validasi alur.
- **Ulasan**: lihat sumber ulasan dan tampilkan/sembunyikan tanpa menghapus riwayat.
- **Feedback**: status tindak lanjut dan catatan admin.
- **Poin**: koreksi melalui ledger baru dengan alasan; riwayat lama tidak dapat diedit.
- **Sistem**: pengelolaan Admin/Owner dan audit log.
- Token, hash password, dan salt tidak ditampilkan di panel.

## Pengujian backend

Jalankan dari folder `backend`:

```cmd
C:\msys64\mingw64\bin\python.exe -m unittest -v test_server test_admin test_features
```

Catatan: backend ini untuk pengembangan lokal/tugas. Payment status tetap `Pending` sampai diverifikasi admin; gateway pembayaran sungguhan dan deployment HTTPS belum disertakan.
