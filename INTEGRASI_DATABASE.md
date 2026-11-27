# Integrasi Flutter, Backend, dan Control Panel

Patch ini tidak mengubah `pubspec.yaml` dan tidak menambahkan dependency baru.

## Cara memasang tanpa menghapus database/admin yang sudah ada

1. Buat salinan folder `backend/uniqlo_plus.sqlite3` sebagai cadangan.
2. Ekstrak `project_uas_integrasi_patch.zip` langsung ke folder proyek `project_uas` yang sedang dipakai dan izinkan file kode ditimpa.
3. **Jangan menimpa atau menghapus `backend/uniqlo_plus.sqlite3`**. Database yang sedang dipakai tetap menyimpan akun admin yang sudah dibuat.
4. Hentikan backend yang sedang berjalan, lalu jalankan kembali `python server.py` dari folder `backend`.
5. Lakukan Hot Restart aplikasi Flutter. Tidak perlu `flutter clean` atau `flutter pub get` karena tidak ada dependency baru.

## Data yang tersinkron

- Pendaftaran/login member, profil akun, dan alamat -> `users`, `addresses`, `tokens`.
- Keranjang dan favorit -> `cart_items`, `wishlist`.
- Checkout dan detail pembelian -> `orders`, `order_items`, `addresses`.
- Aktivitas, bonus/check-in/poin transaksi -> `member_activities`, `member_points`.
- Profil stylist dan model personal -> `style_profiles`.
- Interaksi produk dan ulasan -> `feedback`, `reviews`.
- Katalog dan varian produk -> `products`, `product_variants`.
- Konten dari panel -> `news`, `vouchers`, `stores`, lalu diambil aplikasi saat startup.

Sinkronisasi member dibuat idempoten untuk mencegah alamat dan item pesanan terduplikasi saat snapshot dikirim berulang.

## Isi awal konten

Pada server start, jika tabel masih kosong, backend mengimpor 82 toko, 4 voucher, dan 9 berita contoh dari berkas seed. Seed tidak menimpa tabel yang sudah memiliki data. Produk dan varian tetap menggunakan katalog yang sudah ada.

## Menu tambahan di Control Panel

- **Konten:** Varian Produk.
- **Pelanggan:** Alamat Pelanggan, Pesanan, Item Pesanan, Keranjang, Wishlist, Aktivitas Member, Riwayat Poin, Profil Gaya, Ulasan Produk, selain Pengguna dan Umpan Balik.
- **Machine Learning:** Model ML.
- **Sistem:** Log Audit dan Admin & Akses.

Tabel operasional pelanggan ditampilkan baca-saja. Hash password, token sesi, dan data autentikasi rahasia tidak ditampilkan.

## Catatan

- Untuk Android Emulator, alamat server lokal tetap `http://10.0.2.2:8000`.
- `ml_models` boleh tetap kosong sampai model diunggah/dilatih melalui panel; aplikasi masih memiliki model bawaan di `assets/data/ml_model.json`.
- `audit_log` akan bertambah ketika admin melakukan perubahan. Tabel yang memang menunggu aktivitas pengguna (pesanan, keranjang, ulasan, dan sebagainya) baru terisi saat fitur tersebut dipakai.
