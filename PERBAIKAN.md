# Penjelasan Error dan Perbaikan

## Penyebab error (garis merah di Android Studio)

Berkas proyek tercampur dua versi. Pada 11 Nov 2026 pukul 21:16, 12 berkas
tertimpa versi lama yang sederhana, sedangkan 64 berkas lainnya masih versi
baru yang lebih lengkap. Versi baru memanggil fungsi dan paket yang tidak ada
di versi lama, sehingga muncul error.

### 1. Paket belum terdaftar di `pubspec.yaml`
`pubspec.yaml` versi lama hanya berisi `provider`, `sqflite`, dan `path`.

| Paket | Dipakai oleh | Berkas yang merah |
|---|---|---|
| `shared_preferences` | `UTILS/prefs_store.dart` | prefs_store.dart |
| `url_launcher` | `UTILS/external_link.dart` | external_link.dart |
| `crypto` | `PROVIDERS/auth_provider.dart` (hash password) | auth_provider.dart |

### 2. `AppState` versi lama tidak punya fungsi yang dipanggil kode lain
`PROVIDERS/app_state.dart` yang tertimpa tidak punya: `saleProducts`,
`isNewsRead`, `markNewsRead`, `markAllNewsRead`, `unreadNewsCount`, `news`,
`newsById`, `ratingOf`, `addRecentSearch`, `recentSearches`, `searchProducts`,
`showCategory`, `setTab`, `setActiveMember`, `addOrderItemsToCart`, dan lainnya.

| Berkas yang merah | Fungsi yang hilang |
|---|---|
| flash_sale.dart | saleProducts |
| news_widgets.dart | isNewsRead |
| product_card.dart | ratingOf (+ isOnSale, discountPercent, isNew) |
| news_detail_page.dart | markNewsRead, newsById, setTab |
| news_list_page.dart | news, unreadNewsCount, markAllNewsRead |
| search_page.dart | addRecentSearch, recentSearches, searchProducts, showCategory |
| membership_page.dart | unreadNewsCount |
| order_actions.dart | addOrderItemsToCart, setTab |
| app_providers.dart | `AppState(store:)`, setActiveMember |

### 3. `Product` versi lama kurang field
`MODELS/product_model.dart` lama tidak punya `features`, `originalPrice`,
`isNew`, `isOnSale`, `discountPercent`, `formattedOriginalPrice`, padahal
`DATA/product_data.dart` (50 produk) memakainya. `CartItem` juga didefinisikan
dua kali (di product_model dan app_state), sehingga bentrok.

### 4. Berkas versi lama lain yang tidak cocok
`main.dart` (tidak memakai `AppProviders`, tidak ada login/penyimpanan),
`main_navigation.dart` (tab Keanggotaan hanya placeholder), `homepage`,
`daftarproduk`, `detailproduk`, `cart_page`, `checkout_page`, `wishlist_page`
(tidak terhubung ke login, voucher, poin, pesanan), dan `widget_test.dart`
(mengimpor `providers/app_state.dart` huruf kecil, padahal foldernya `PROVIDERS`).

`main.dart` lama juga menjalankan `DBHelper` (sqflite) saat start. sqflite tidak
jalan di web/Windows tanpa konfigurasi tambahan, sehingga bisa menggagalkan
aplikasi sebelum tampil. Aplikasi ini memakai `shared_preferences`, jadi
inisialisasi database dihapus (berkas `db_helper.dart` dibiarkan).

## Yang diperbaiki

- `pubspec.yaml`: tambah `shared_preferences`, `url_launcher`, `crypto`,
  dan daftar aset logo.
- Ditulis ulang: `app_state.dart`, `product_model.dart`, `main.dart`,
  `main_navigation.dart`, `homepage_uniqlo.dart`, `daftarprodukpage_uniqlo.dart`,
  `detailproduk_uniqlo.dart`, `cart_page.dart`, `checkout_page.dart`,
  `widget_test.dart`; `wishlist_page.dart` diperbaiki (API usang `withOpacity`).
- Logo UNIQLO PLUS: `assets/images/logo.png`, widget `AppLogo`, ikon launcher
  Android, nama aplikasi, dan logo di header, halaman masuk, serta kartu member.
- Animasi pembuka: `SCREENS/splash_page.dart` (animasi logo dari kode, tanpa video).
- Android: izin INTERNET (release) dan `queries` https untuk url_launcher.

## Alur masuk aplikasi

1. Layar gelap (`#0D1213`, sama dengan latar native Android) agar tidak ada kilatan putih.
2. Animasi logo (±3,6 detik): cincin cahaya merah dan grid memancar dari tengah,
   logo muncul membesar sambil berputar halus lalu berpendar, kilau menyapu logo,
   titik-titik mengorbit, tulisan UNIQLO PLUS muncul huruf demi huruf, disusul
   slogan dan garis progres. Ketuk layar untuk melewati.
3. Seluruh isi membesar sedikit lalu memudar masuk ke aplikasi (tab Home).


## Fitur baru: UNIQLO PLUS Stylist

Ditambahkan tanpa mengubah fitur belanja yang sudah ada.

- Paket baru di `pubspec.yaml`: `http` (internet), `camera` (kamera selfie),
  `image_picker` (foto dari galeri).
- Android: izin `CAMERA`, `usesCleartextTraffic` (agar bisa memanggil server
  `http://` saat pengembangan), `compileSdk`/`minSdk`/`targetSdk` mengikuti
  versi Flutter (`flutter.compileSdkVersion`, dst.) karena plugin kamera
  membutuhkan SDK lebih baru daripada `34` yang sebelumnya dikunci.
- `AppState`: katalog bisa diganti dengan data dari server (`replaceCatalog`).
- `AuthProvider`: setelah masuk/daftar, akun lokal disamakan dengan server
  (`onSignedIn`) dan sesi server diputus saat keluar (`onSignedOut`).
- `AppProviders`: menambahkan `ApiService` dan `StyleProvider`.
- Beranda: banner Stylist dan tombol cepat "Stylist".
- Folder `backend/`: server + database SQLite.
- Uji baru: `test/style_test.dart` (analisis wajah, model ML, rekomendasi,
  klien server) dan `backend/test_server.py`.
