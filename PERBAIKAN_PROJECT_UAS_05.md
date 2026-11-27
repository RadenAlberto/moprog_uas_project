# Perbaikan berdasarkan project_uas_05.zip

## Perubahan
1. Checkout ambil di toko:
   - Jika katalog toko dari database server belum memiliki metadata `services` (seluruhnya kosong), semua toko di katalog ditampilkan sebagai pilihan pickup simulasi.
   - Jika metadata layanan sudah diisi, daftar tetap difilter ke toko yang memiliki layanan `Pickup pesanan`.
   - Pemilihan toko tetap menyimpan ID, nama, dan alamat sebagai snapshot pada pesanan.

2. Detail riwayat pembelian:
   - Tombol pada kartu riwayat diberi label `Lihat Detail`.
   - Saat detail dibuka, Flutter meminta ulang bootstrap pesanan dari backend.
   - Detail menampilkan ringkasan pesanan, status pesanan/pembayaran, metode dan info pembayaran, referensi transaksi, cara penerimaan, detail toko/alamat, item, dan rincian harga.
   - Tombol `Batalkan` tersedia selama pesanan belum selesai atau dibatalkan; pesanan selesai hanya menampilkan `Beli Lagi`.
   - Endpoint backend menerapkan aturan pembatalan yang sama dan menolak pembatalan untuk pesanan selesai/dibatalkan.

## Database
Database `backend/uniqlo_plus.sqlite3` dipertahankan tanpa perubahan. SHA-256:
`6d953a563694f77d81bd1e6efabe54c5e9b18c91f67d6fcb61734c11aa20a5fa`

## Pemeriksaan
- Backend unittest: 24 tes lulus.
- Python compileall: lulus.
- SQLite integrity_check: `ok`; foreign_key_check: 0 pelanggaran.
- Flutter/Dart test dan analyze belum dapat dijalankan di lingkungan penyusunan ini karena Flutter SDK/Dart SDK tidak tersedia. Test widget detail dan test pickup ditambahkan untuk dijalankan lokal dengan `flutter test`.
