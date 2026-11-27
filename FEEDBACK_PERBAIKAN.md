# Perbaikan berdasarkan feedback Control Panel dan Flutter

Tanggal pengerjaan: 23 November 2026

ZIP ini dibuat dari `project_uas_01.zip` yang diunggah pengguna. Fokus perbaikan dibatasi pada feedback Control Panel dan alur checkout/pesanan. Tidak ada fitur stok atau login multi-perangkat tambahan yang dikerjakan.

## Control Panel

1. **Tanggal ulasan**: tanggal ISO seperti `2026-09-13` tidak diubah menjadi tanggal hari ini. Fungsi format tanggal sekarang menerima timestamp Unix maupun tanggal ISO, sehingga tanggal contoh lama ditampilkan sebagai tanggal yang valid tanpa memalsukan waktu.
2. **Pengguna**: ditambahkan aksi `Hapus / nonaktifkan` dan `Aktifkan kembali`. Ini menggunakan soft-delete (`is_active=0`) agar riwayat transaksi, poin, dan ulasan tetap utuh. Token sesi dicabut saat akun dinonaktifkan.
3. **Audit log**: kolom Objek tetap dipertahankan karena menunjukkan jenis entitas dan ID target tindakan (misalnya `user` + `user1`). Tampilan dipisahkan menjadi jenis dan ID agar lebih mudah dibaca.
4. **Umpan balik**: status diberi label sebagai status peninjauan internal; catatan diberi label Catatan internal admin. Tindak lanjut hanya mengubah status dan catatan internal. Data feedback di tabel ini adalah sinyal interaksi produk (`like`, `dislike`, `cart`, `view`), bukan tiket keluhan. Catatan ini tidak dikirim ke aplikasi Flutter dan tidak terlihat oleh member.
5. **Koreksi poin**: fungsi yang ada tetap berupa transaksi ledger baru dengan alasan; riwayat lama tidak diedit/dihapus.

## Aplikasi Flutter dan backend

1. **Alamat checkout**: checkout tidak lagi membuat alamat baru secara otomatis ketika ID alamat belum dipilih. Pengguna harus memilih alamat tersimpan atau menambahkannya melalui buku alamat. Order menyimpan `addressId`, sehingga sinkronisasi dapat mengaitkan order ke baris alamat yang sama, bukan membuat duplikat.
2. **Edit alamat**: endpoint PUT alamat mengembalikan alamat yang telah diperbarui; API Flutter mendukung DELETE dan mempertahankan ID pada hasil edit.
3. **Pilihan penerimaan**: halaman fulfillment sekarang menampilkan daftar alamat tersimpan (dengan pilihan dan tombol edit) untuk pengiriman. Pilihan toko/pengiriman dikirim ke backend dan disimpan pada snapshot order.
4. **Mencegah race checkout**: setelah pesanan dibuat, Flutter menunggu sinkronisasi awal selesai sebelum membuka alur fulfillment, sehingga endpoint fulfillment tidak dipanggil sebelum order tersedia di server.
5. **Detail pesanan**: model order menyimpan `paymentStatus`; detail dan riwayat menampilkan status pembayaran dari server. Pesanan non-COD hanya Pending bila belum ada referensi konfirmasi gateway; COD berstatus Unpaid.
6. **Pembayaran simulasi**: endpoint server mengubah Pending non-COD menjadi Paid melalui permintaan terautentikasi. COD tidak menggunakan simulasi pembayaran online. Ini hanya simulasi, tidak ada uang sungguhan yang berpindah.
7. **Pembatalan/refund simulasi**: pembatalan setelah Paid mengubah status pembayaran menjadi Refunded, mencatat nominal refund simulasi, mengembalikan poin yang dipakai, dan mengoreksi poin pesanan bila pernah diberikan. Flutter menampilkan pemberitahuan refund simulasi.
8. **Status pada layar sukses**: tidak lagi menyatakan pembayaran diterima bila status server masih Pending; pengguna diarahkan membuka detail pesanan untuk simulasi pembayaran. COD menampilkan instruksi pembayaran tunai saat pesanan diterima.

## Pengujian yang dilakukan

- Python syntax check: `server.py`, `admin.py`, `feature_extensions.py`, dan `test_features.py` lulus.
- Backend test suites: `test_server.py` 5/5, `test_admin.py` 7/7, `test_features.py` 8/8 — total **20/20 lulus**.
- Pengujian tambahan memeriksa pemilihan fulfillment delivery/pickup, simulasi pembayaran, pembatalan dan status refund, edit alamat pada ID yang sama, dan pencegahan duplikasi alamat saat order disinkronkan.
- JavaScript control panel: `node --check` lulus.
- Database dalam ZIP: 13 member, 1.376 produk, 16.775 varian, 1 pesanan, 2 alamat, 4.128 ulasan; `PRAGMA integrity_check = ok` dan `foreign_key_check` kosong.
- Flutter SDK tidak tersedia di lingkungan pengerjaan ini. Karena itu `flutter analyze`, `flutter test`, dan build Android belum dapat dijalankan. Jalankan di Android Studio/terminal setelah ZIP diekstrak.

## Batasan yang dipertahankan

- Produk tetap simulasi tanpa stok.
- Tidak ada integrasi payment gateway sungguhan atau transfer refund sungguhan.
- Feedback admin adalah catatan internal; belum ada sistem balasan customer-service yang tampil di Flutter.
- Login multi-perangkat tidak menjadi fokus pada patch ini.

## Audit lanjutan dan koreksi rancangan (23 November 2026)

1. **Buku alamat tidak lagi dibuat dari snapshot pesanan.** Sinkronisasi pesanan hanya mengisi `orders.address_id` bila `addressId` yang dikirim benar-benar milik member. Teks alamat historis tetap disimpan di `orders.order_json`. Bila ID tidak ada/tidak valid, `address_id` dibiarkan NULL; backend tidak melakukan INSERT ke `addresses`.
2. **Perubahan alamat profil tidak menambah baris.** Jika member mengubah alamat profil dan sudah memiliki alamat utama, baris alamat utama diperbarui berdasarkan ID yang sama. Jika belum ada alamat utama, sinkronisasi profil tidak membuat alamat baru. Pembuatan alamat baru hanya melalui endpoint `POST /api/addresses`; edit memakai `PUT /api/addresses/{id}`.
3. **Snapshot pesanan tidak berubah saat alamat diedit.** Detail pesanan menggunakan salinan alamat pada snapshot order; perubahan pada buku alamat tidak menulis ulang snapshot order lama.
4. **Pembayaran non-COD mengikuti hasil gateway simulasi.** Order yang dikirim dengan `gatewayRef` hasil pembayaran berhasil langsung disimpan sebagai `Paid`. Order non-COD tanpa referensi konfirmasi disimpan `Pending`, sehingga member tetap mendapat tombol simulasi pembayaran. COD disimpan sebagai `Unpaid` dan tidak dapat menggunakan endpoint simulasi pembayaran online.
5. **Ringkasan transaksi dipisah dari perhitungan level.** Riwayat menampilkan total transaksi dan total hemat dari kelompok pesanan yang sama: Paid, belum dibatalkan, dan belum direfund. Total belanja penentu level tetap hanya pesanan Paid yang sudah selesai. Refund ongkir pickup dikurangkan dari nilai transaksi bersih.
6. **Panel admin pesanan.** Filter mencakup status pesanan, status pembayaran, dan metode pembayaran. Status `Unpaid` tersedia untuk COD. Detail pesanan admin menampilkan data penerimaan, snapshot alamat/toko, item, diskon, ongkir, dan refund.
7. **Sumber database dibuat tidak ambigu.** Database aktif tetap `backend/uniqlo_plus.sqlite3`. File `uniqlo_plus.sqlite3` kosong di root proyek dihapus agar tidak disangka sebagai database aktif.

### Pengujian tambahan

- Edit alamat: ID tetap sama dan jumlah baris tidak bertambah.
- Sinkronisasi beberapa pesanan dengan alamat ID yang sama: tetap memakai satu baris alamat.
- Sinkronisasi order tanpa ID alamat: tidak membuat alamat baru.
- Edit alamat setelah order: snapshot alamat pada order lama tetap sama.
- Gateway berhasil + `gatewayRef`: status `Paid`.
- COD: status `Unpaid`, endpoint simulasi online ditolak.
- Pembayaran non-COD tanpa referensi konfirmasi: status `Pending`, endpoint simulasi mengubah status persisten menjadi `Paid`.
- Ringkasan total transaksi/hemat dan filter metode pembayaran diuji.
- Backend suite terbaru: **23/23 lulus** (`test_server.py`, `test_admin.py`, `test_features.py`).
- Flutter SDK/Dart tidak tersedia di lingkungan audit ini; `flutter analyze`, `flutter test`, dan build Android belum dapat dijalankan.
