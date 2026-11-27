# Catatan Perbaikan Lanjutan UNIQLO+

Tanggal: 23 November 2026

## Cakupan yang disentuh

- `backend/server.py`: edit alamat profil memperbarui alamat utama yang sudah ada, tanpa INSERT otomatis.
- `backend/feature_extensions.py`: sinkronisasi order tidak membuat alamat; status pembayaran diset berdasarkan COD/referensi gateway; ringkasan transaksi dan level dipisah; refund ongkir pickup dicatat; COD ditolak pada endpoint simulasi online.
- `backend/admin.py` dan `backend/admin_ui.html`: filter metode pembayaran dan status Unpaid COD; detail pesanan admin diperluas.
- `lib/MODELS/order_model.dart`, `lib/PROVIDERS/auth_provider.dart`: status pembayaran awal dan metrik transaksi dipisah dari total belanja level.
- `lib/SCREENS/order_history_page.dart`, `lib/MODELS/stats_model.dart`: riwayat/statistik hanya memasukkan transaksi Paid pada metrik transaksi.
- `lib/SCREENS/order_detail_page.dart`, `lib/MODELS/payment_model.dart`, `lib/SCREENS/payment_history_page.dart`: status COD Unpaid dan Pending ditampilkan sesuai status server.

## Database

Database aktif: `backend/uniqlo_plus.sqlite3`. Database ini tidak dimigrasikan atau ditulis ulang selama patch ini; salinan backup audit disimpan terpisah selama proses pengerjaan. File kosong di root yang berpotensi membingungkan telah dihapus.

## Verifikasi

- `python -m py_compile backend/server.py backend/feature_extensions.py backend/admin.py backend/test_features.py backend/test_server.py` — lulus.
- Backend tests `test_server.py`, `test_admin.py`, `test_features.py` — 23/23 lulus.
- `node --check` untuk JavaScript di `backend/admin_ui.html` — lulus.
- Flutter analyze/test/build — belum dijalankan, karena perintah `flutter` dan `dart` tidak tersedia di lingkungan ini.

## Perilaku yang perlu diuji di perangkat

1. Edit alamat tersimpan dari checkout: pastikan ID di panel admin tetap sama.
2. Buat dua pesanan memakai alamat tersimpan yang sama: jumlah baris `addresses` tidak berubah.
3. Edit alamat setelah order selesai dibuat: detail order lama tetap menampilkan snapshot lama.
4. Pembayaran VA/QRIS/kartu berhasil: status Flutter dan admin harus Paid.
5. COD: status Unpaid sampai admin/backend mencatat pembayaran; tidak ada tombol simulasi online.
6. Buat order non-COD yang belum terkonfirmasi: status Pending dan tombol simulasi harus mengubah status di server menjadi Paid.
7. Periksa ringkasan riwayat transaksi, total hemat, level membership, dan detail order.
- Riwayat pembayaran Flutter kini mengikuti `paymentStatus` persisten: COD Unpaid tidak otomatis berubah menjadi Lunas hanya karena status pesanan selesai; pesanan dibatalkan tanpa refund ditampilkan sebagai Dibatalkan.
- `lib/DATABASE/db_helper.dart` juga diamankan: upgrade database lokal tidak lagi menonaktifkan foreign key lalu DROP TABLE. Migrasi hanya menambahkan tabel yang belum ada (`CREATE TABLE IF NOT EXISTS`); perubahan skema yang tidak kompatibel harus memakai migrasi terencana setelah backup.
