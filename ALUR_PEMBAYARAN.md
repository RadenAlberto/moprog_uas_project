# Revisi Alur Pembayaran & Penerimaan Pesanan

## Alur baru
Checkout → **Payment Gateway** → pesanan dibuat → **Pilih penerimaan** (ambil di toko / diantar) → **Layar sukses** (tombol *Beli lagi*, *Lihat pesanan*, *Lanjut belanja*).

Aplikasi tidak lagi otomatis kembali ke beranda setelah bayar. Layar sukses tetap tampil sampai pembeli memilih langkah berikutnya.

## Payment gateway (`lib/SERVICES/payment_gateway.dart`, `lib/SCREENS/payment_gateway_page.dart`)
- Antarmuka `PaymentGateway` + `SandboxPaymentGateway` (simulasi, **tidak ada uang yang bergerak**).
- Virtual Account BCA/Mandiri: nomor VA, hitung mundur 24 jam, cek status otomatis tiap 4 detik.
- QRIS / GoPay / OVO / ShopeePay: QR ilustrasi (bukan QR yang dapat dipindai), batas 15 menit.
- Kartu: validasi Luhn, masa berlaku, CVV, lalu OTP 3-D Secure.
- COD tidak lewat gateway.
- Uji sandbox: kartu `4811 1111 1111 1114` berhasil; `4811 1111 0003 0002` ditolak; `4811 1111 0002 0003` saldo kurang; OTP `112233`; tombol "Sandbox: simulasikan pembayaran berhasil" untuk VA/QRIS.
- Keluar dari halaman bayar = pesanan belum dibuat, keranjang tetap utuh.

**Gateway sungguhan (Midtrans/Xendit):** belum tersambung karena butuh akun dan kunci Anda. Buat kelas baru yang `implements PaymentGateway` dan memanggil server Anda (kunci rahasia hanya di server, jangan di aplikasi), lalu berikan lewat parameter `gateway` pada `PaymentGatewayPage`.

## Penerimaan pesanan (`lib/SCREENS/fulfillment_page.dart`)
- **Ambil di toko**: hanya toko berlayanan "Pickup pesanan", filter kota, estimasi siap ±2 jam dalam jam buka toko, kode ambil `PU-XXXX-AB`. Ongkir yang sudah dibayar **dikembalikan** (`Order.shippingRefund`).
- **Diantar**: nama, HP, alamat dapat diubah; layanan Reguler (ongkir sudah termasuk).
- Pilihan hanya bisa dibuat sekali (mencegah pengembalian ongkir ganda). Bila ditunda, Detail Pesanan menampilkan tombol "Pilih sekarang".
- Status pesanan menyesuaikan: ambil di toko → Diproses → Disiapkan → Siap diambil → Selesai.

## Data
`Order` mendapat field fulfillment dan gateway. Pesanan lama otomatis dianggap "diantar" (JSON kompatibel).

## Catatan jujur
Kode ini ditulis tanpa Flutter di lingkungan saya, jadi **belum dikompilasi atau dijalankan**. Jalankan `flutter pub get`, `flutter analyze`, `flutter test` (tes baru: `test/checkout_flow_test.dart`) dan coba alur di aplikasi.


## Penyesuaian status pembayaran pada feedback 23 November 2026
- Server mempertahankan status `Pending` sampai ada konfirmasi pembayaran melalui aksi terautentikasi.
- Detail Pesanan dan Riwayat Pembelian menampilkan status pembayaran.
- Untuk pengujian, member dapat memakai tombol **Simulasikan Pembayaran Berhasil** pada Detail Pesanan. Ini mengubah status server menjadi `Paid`, tanpa perpindahan uang sungguhan.
- Jika pesanan berstatus `Paid` dibatalkan, server menandainya `Refunded`, mencatat nominal refund simulasi, dan aplikasi menampilkan pemberitahuan bahwa dana telah direfund (simulasi).

## Aturan status pembayaran setelah audit 23 November 2026

- Checkout non-COD hanya membuat order setelah gateway simulasi mengembalikan hasil sukses. Referensi `gatewayRef` disimpan bersama order dan backend langsung menetapkan `payment_status='Paid'`.
- Jika order non-COD masuk tanpa `gatewayRef`, backend menetapkannya `Pending`. Ini diperlakukan sebagai alur pembayaran yang belum terkonfirmasi; member dapat memakai tombol **Simulasikan Pembayaran Berhasil** di Detail Pesanan. Endpoint backend mengubah status SQLite menjadi `Paid`.
- COD tidak melewati gateway dan dibuat dengan `payment_status='Unpaid'`. Detail pesanan menjelaskan bahwa pembayaran dilakukan saat barang diterima/diambil. Tombol simulasi pembayaran online tidak ditampilkan dan endpoint menolak permintaan untuk order COD.
- Riwayat pembayaran membaca status pembayaran dari server, tidak menebak bahwa COD otomatis lunas hanya karena status pengiriman sudah selesai.
