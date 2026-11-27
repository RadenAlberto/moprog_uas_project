# UNIQLO PLUS (project_uts)

Aplikasi belanja LifeWear berbasis Flutter: katalog, wishlist, keranjang,
checkout, keanggotaan (poin, level, voucher), berita, video, dan
**UNIQLO PLUS Stylist** untuk membantu orang yang belum paham fashion menemukan
pakaian yang cocok.

## Menjalankan

```
flutter pub get
flutter analyze
flutter test
flutter run
```

Saat dibuka, aplikasi menampilkan animasi logo UNIQLO PLUS (dibuat dengan kode,
±3,6 detik; ketuk layar untuk melewati), lalu masuk ke aplikasi.

Aplikasi memiliki cache lokal, tetapi akun member dan data transaksi yang disinkronkan menggunakan backend sebagai sumber data utama. Login dan registrasi online diverifikasi ke server terlebih dahulu; saat login, aplikasi memulihkan pesanan, cart, wishlist, poin, level, aktivitas, dan ulasan dari server. Untuk memakai database server, jalankan:

```
cd backend
C:\msys64\mingw64\bin\python.exe server.py  # Windows (port 8000)
# Control panel: http://localhost:8000/admin
```

Untuk Android Emulator, alamat server bawaan adalah `http://10.0.2.2:8000`. Untuk HP asli pada Wi-Fi yang sama, gunakan IP komputer:

| Perangkat | Alamat server |
|---|---|
| Emulator Android | `http://10.0.2.2:8000` (bawaan) |
| HP asli (satu Wi-Fi dengan komputer) | `http://IP-komputer:8000`, mis. `http://192.168.1.10:8000` |
| Windows / Web | `http://localhost:8000` |

## UNIQLO PLUS Stylist

1. **Data diri**: jenis kelamin, tinggi, berat badan (BMI -> tipe tubuh), kebutuhan
   berpakaian, dan batas harga.
2. **Foto selfie** (kamera depan dengan bingkai wajah, atau pilih dari galeri):
   aplikasi mengukur bentuk wajah (oval/bulat/kotak/hati/lonjong) dan warna kulit
   (kecerahan + nada hangat/netral/dingin). Foto diproses di perangkat, tidak
   disimpan, dan tidak dikirim ke server.
3. **Konfirmasi**: hasil bacaan bisa dikoreksi manual.
4. **Rekomendasi**: tips gaya, warna paling serasi, set pakaian lengkap, serta
   daftar produk dengan persentase kecocokan, alasan, ukuran, dan warna terbaik.

Tinggi dan berat badan diisi manual karena tidak bisa diukur akurat dari foto
selfie.

### Machine learning

`lib/SERVICES/style_recommender.dart` berisi model regresi logistik personal
yang dilatih di perangkat. Tiap produk diubah menjadi 11 fitur (kecocokan
bentuk wajah, tipe tubuh, tinggi, nada kulit, warna untuk tubuh, kebutuhan,
tren pengguna lain, harga, jenis & warna favorit). Bobot awal berasal dari
aturan stylist, lalu bergeser lewat SGD setiap pengguna menekan jempol
"Cocok" / "Kurang cocok" atau memasukkan produk ke keranjang. Bobot model dan
umpan balik disimpan per akun dan disinkronkan ke server; skor "tren pengguna
lain" dihitung server dari umpan balik semua member.

## Struktur

- `lib/main.dart` - titik masuk: penyimpanan, provider, tema, animasi pembuka
- `lib/SCREENS/splash_page.dart` - animasi logo pembuka
- `lib/SCREENS/style_advisor_page.dart` - wizard data diri -> foto -> konfirmasi
- `lib/SCREENS/camera_capture_page.dart` - kamera selfie dengan bingkai wajah
- `lib/SCREENS/style_result_page.dart` - hasil rekomendasi
- `lib/SERVICES/face_analyzer.dart` - analisis bentuk wajah dan warna kulit
- `lib/SERVICES/style_recommender.dart` - model ML + aturan stylist + outfit
- `lib/SERVICES/api_service.dart` - klien REST, login/registrasi server-first, pemulihan data member, buku alamat, check-in, pembatalan pesanan, dan ulasan server
- `lib/PROVIDERS/style_provider.dart` - profil gaya, model, sinkronisasi
- `lib/PROVIDERS/app_state.dart` - katalog, wishlist, keranjang, berita, ulasan
- `lib/PROVIDERS/auth_provider.dart` - cache lokal akun member dan pesanan, dengan status/poin/level resmi dipulihkan dari server
- `assets/data/products.json` - katalog produk Uniqlo Indonesia (1.376 produk, 16.775 varian warna x ukuran)
- `lib/DATA/product_data.dart` - memuat katalog di atas saat aplikasi dibuka
- `lib/DATABASE/db_helper.dart` - skema SQLite di perangkat (products + product_variants) dan `seedCatalogIfEmpty()`
- `backend/` - server Python + database SQLite (lihat `backend/README.md`)
- `backend/import_uniqlo.py` - mengonversi data mentah Uniqlo menjadi katalog aplikasi + seed server
- `assets/images/logo.png` - logo UNIQLO PLUS (juga dipakai sebagai ikon aplikasi)

Penjelasan perbaikan error ada di `PERBAIKAN.md`.


## Data produk (Uniqlo)

Semua produk berasal dari `raw_products.json` + `variants.csv` hasil pengumpulan
data Uniqlo Indonesia (12 Nov 2026). Tiap produk memuat nama, harga (promo bila
ada, harga normal dicoret), warna lengkap dengan **foto per warna**, semua
ukuran, kategori, dan target pengguna. Memilih warna di halaman detail
mengganti foto, dan keranjang/pesanan menyimpan foto sesuai warna yang dipilih.

Foto dimuat dari server gambar Uniqlo lewat internet (bukan disimpan di APK).
Perbarui katalog dengan:

```
python3 backend/import_uniqlo.py <folder uniqlo_output>
```

Perintah ini menulis ulang `backend/products_seed.json` dan
`assets/data/products.json` sekaligus (dan memeriksanya terhadap `variants.csv`).

## Integrasi data dan admin

Detail endpoint, aturan poin/level, migrasi database, role Owner/Admin, serta perintah membuat akun Owner ada di `backend/README.md`. Buat akun Owner milikmu dari CMD melalui `C:\msys64\mingw64\bin\python.exe buat_admin.py USERNAME_KAMU` di folder `backend`; password akan diminta secara tersembunyi.

## Catatan database server

Database aktif untuk backend dan panel admin berada di `backend/uniqlo_plus.sqlite3` (bukan file database di root proyek). Jalankan backend dari folder `backend` dengan `python server.py`; panel admin tersedia di `http://localhost:8000/admin`. Lihat `PERBAIKAN_LANJUTAN.md` untuk aturan alamat, pembayaran, ringkasan transaksi, dan hasil pengujian terakhir.
