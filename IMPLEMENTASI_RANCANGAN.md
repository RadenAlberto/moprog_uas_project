# UNIQLO+ — Catatan implementasi rancangan

Dokumen ini mencatat isi ZIP hasil implementasi dan batas pengujian yang benar-benar dilakukan.

## Fitur yang diimplementasikan

### Member dan sinkronisasi
- Registrasi dan login Flutter melakukan autentikasi server terlebih dahulu saat `autoSync` aktif.
- Akun yang sudah ada di server dapat masuk dari instalasi/perangkat lain; cache lokal dibuat atau diperbarui setelah autentikasi server berhasil.
- Endpoint bootstrap mengirim data member, alamat, cart, wishlist, order, aktivitas, ledger poin, ulasan, serta ringkasan poin/level.
- Flutter memulihkan status pesanan, poin, level, riwayat poin, cart, wishlist, dan ulasan dari backend.
- Sinkronisasi member bersifat insert-only untuk order dan ledger; snapshot client tidak dapat mengubah status order, saldo poin, bonus pendaftaran, atau status pembayaran dari pesanan yang sudah ada.
- Password member disimpan sebagai PBKDF2-SHA256 + salt di server. Password/token tidak dikirim ke panel admin.

### Alamat dan checkout
- Member dapat memiliki beberapa alamat.
- Backend menjaga maksimum satu alamat utama per member dengan unique partial index.
- Flutter checkout dapat memilih alamat tersimpan, menambah, mengedit, menghapus, dan menjadikan alamat utama.
- Pesanan menyimpan snapshot alamat dan item sehingga perubahan alamat member tidak mengubah pesanan lama.

### Poin dan level
- Poin disimpan sebagai ledger append-only di `member_points`.
- Bonus pendaftaran ditetapkan server sebesar 200 poin.
- Check-in server hanya satu kali per tanggal; reward mengikuti aturan aplikasi (5 poin hari pertama, +2 per hari beruntun, maksimum 15).
- Poin belanja baru diberikan setelah pesanan berstatus `selesai` dan pembayaran `Paid`.
- Perhitungan mengikuti aturan aplikasi: 1 poin per Rp10.000 belanja bersih dengan multiplier Regular 1.0, Silver 1.25, Gold 1.5, Platinum 2.0.
- Level dihitung dari total belanja bersih pesanan selesai yang belum direfund: Regular Rp0, Silver Rp1.000.000, Gold Rp3.000.000, Platinum Rp7.500.000.
- Pembatalan/refund membuat transaksi koreksi/pengembalian baru. Ledger lama tidak dihapus atau diedit.
- Admin dapat membuat koreksi poin dengan alasan; saldo tidak boleh menjadi negatif.

### Ulasan
- 4.128 ulasan contoh dimigrasikan ke `reviews` (3 per produk pada katalog saat migrasi).
- Setiap ulasan contoh ditautkan ke akun member penulis dari 12 nama: Dewi, Rizky, Anisa, Budi, Maya, Fajar, Sinta, Andre, Putri, Kevin, Laras, Hendra.
- Teks dan nilai rating memakai pool ulasan contoh yang sudah ada; tanggal mengikuti pola tanggal contoh. Karena ulasan sebelumnya dibangkitkan saat runtime (bukan disimpan sebagai record database), pembagian penulis/teks per produk dibuat ulang secara deterministik agar hasil migrasi stabil di semua perangkat.
- Ulasan dibedakan dengan `source='sample'`/`'member'` dan `is_sample`.
- Flutter mengambil ulasan dari API server setelah login; data statis hanya menjadi fallback offline.
- Admin dapat menyembunyikan/menampilkan ulasan tanpa menghapusnya.

### Admin dan panel
- Role aktif hanya `Owner` dan `Admin`; role lama `editor`/`viewer` dimigrasikan menjadi `admin`.
- Admin mengelola konten dan operasional; hanya Owner yang mengelola akun admin/role.
- Owner dapat menghapus Owner lain dengan password ulang; tidak dapat menghapus diri sendiri atau Owner terakhir.
- Admin dapat melihat/mengelola status pesanan dan pembayaran secara terpisah, melihat detail snapshot pesanan, mengelola alamat, menindaklanjuti feedback, memoderasi ulasan, mengaktif/nonaktifkan member, dan membuat koreksi poin.
- Perubahan penting dicatat di `audit_log`.
- Penghapusan akun member dari panel tidak disediakan; member dinonaktifkan agar riwayat transaksi tetap terjaga.
- Produk/varian, berita, voucher, toko, profil gaya, cart, wishlist, aktivitas, model ML, dan audit tetap memakai backend/panel yang sudah ada.

## Kondisi database dalam ZIP

| Data | Jumlah saat ZIP dibuat |
|---|---:|
| Member | 13 (Valencia + 12 akun contoh) |
| Produk | 1.376 |
| Varian produk | 16.775 |
| Pesanan | 1 |
| Item pesanan | 3 |
| Alamat | 2 |
| Cart items | 3 |
| Wishlist | 4 |
| Ledger poin | 16 |
| Ulasan contoh | 4.128 |
| Akun admin | 1 (`david`, Owner) |

Pada database yang diunggah hanya ada satu akun admin (`david`, Owner); tidak ditemukan akun generik bawaan Python terpisah. Akun `david` dipertahankan. Untuk membuat akun Owner milikmu sendiri, gunakan perintah CLI di bawah.

Integritas SQLite: `ok`. Seed ulasan dan migrasi bersifat idempotent.

## Pengujian

- Python syntax check: lulus.
- Admin UI JavaScript syntax check (`node --check`): lulus.
- Backend unit/integration tests: **18/18 lulus** (`test_server.py`, `test_admin.py`, `test_features.py`).
- Pengujian khusus mencakup alamat/default, ulasan contoh, alur status pesanan, awarding poin idempotent, koreksi poin, dan perlindungan penghapusan Owner.
- Flutter SDK tidak tersedia pada lingkungan pembuatan ZIP ini. Karena itu `flutter analyze`, `flutter test`, dan `flutter build` belum dapat dijalankan di sini. Jalankan perintah tersebut di komputer project setelah ekstraksi.

## Batas yang belum termasuk

- Integrasi payment gateway sungguhan/webhook belum tersedia. Order baru selalu `Pending`; Admin mengubah status pembayaran setelah verifikasi. Ini sengaja dilakukan agar client tidak dapat mengklaim pembayaran berhasil.
- Deployment ke server publik/HTTPS belum dilakukan; project tetap untuk pengembangan lokal.
- Untuk membuat akun Owner milikmu, jalankan `python buat_admin.py USERNAME_KAMU` dari folder `backend`. Password diminta secara tersembunyi. Akun Owner `david` yang ada tidak dihapus.

## Koreksi audit lanjutan (23 November 2026)

- Sinkronisasi order tidak pernah membuat baris alamat. `address_id` hanya diisi dari `addressId` valid; snapshot alamat tersimpan di JSON order dan tidak berubah ketika alamat buku alamat diedit.
- Pembaruan profil mengubah alamat utama yang sudah ada pada ID yang sama; pembuatan alamat baru hanya melalui aksi tambah alamat.
- Status pembayaran backend: non-COD dengan referensi gateway berhasil = `Paid`; non-COD tanpa konfirmasi = `Pending`; COD = `Unpaid`. Simulasi pembayaran hanya tersedia untuk Pending non-COD.
- Ringkasan riwayat memisahkan total transaksi/hemat dari belanja kualifikasi level. Total transaksi dan hemat memakai kohort Paid, tidak dibatalkan, tidak direfund; level memakai Paid dan selesai.
- Refund ongkir pickup dicatat pada `refund_amount` dan dikurangkan dari total transaksi bersih.
- Pengujian backend terbaru 23/23 lulus. Pengujian Flutter belum dapat dilakukan karena Flutter SDK dan Dart tidak tersedia di lingkungan audit.
- Migrasi `DBHelper` lokal yang sebelumnya menghapus tabel pada upgrade diganti menjadi additive-only. Tabel yang sudah ada dipertahankan; `CREATE TABLE IF NOT EXISTS` hanya menambahkan yang belum tersedia.
