# Fitur Studio (tab ke-6 "Studio")

Jalankan dulu: `flutter pub get` (ada paket baru: `camera_windows`, `path_provider`).

| Fitur | File utama | Catatan |
|---|---|---|
| Lemari Digital | `SCREENS/wardrobe_page.dart`, `SERVICES/image_tools.dart`, `SERVICES/outfit_engine.dart` | Foto pakaian -> latar dihapus otomatis (flood fill di tepi) -> warna dominan -> padu padan warna dengan katalog |
| AI Stylist | `SCREENS/stylist_page.dart`, `SERVICES/stylist_engine.dart`, `SERVICES/weather_service.dart` | Cuaca Open-Meteo (tanpa API key). Agenda disimpan di dalam aplikasi. "AI" = mesin aturan, bukan LLM |
| Pelacak Harga & Stok | `SCREENS/price_tracker_page.dart`, `PROVIDERS/tracker_provider.dart` | Notifikasi berupa banner di dalam aplikasi + daftar notifikasi + lencana. Ada "Mode demo" untuk simulasi |
| Kalkulator Ukuran | `SCREENS/fit_calculator_page.dart`, `SERVICES/fit_engine.dart` | Tombol "Cari ukuran saya" juga ada di detail produk |
| Komunitas OOTD | `SCREENS/ootd_page.dart`, `PROVIDERS/ootd_provider.dart` | Postingan disimpan di perangkat (belum sinkron server). 4 contoh bawaan ditandai "CONTOH" |
| Coba Virtual | `SCREENS/try_on_page.dart`, `SERVICES/camera_session.dart` | Overlay 2D di atas kamera, digeser/zoom/putar manual (roda mouse untuk zoom) |

## Kamera
`CameraSession` membaca semua kamera perangkat: HP = depan/belakang (tombol ganti kamera), laptop = webcam.
Windows butuh `camera_windows` (sudah ditambahkan). Jika kamera tidak ada/izin ditolak, tersedia pilihan foto dari galeri.

## Batasan yang perlu diketahui
- Notifikasi harga hanya muncul saat aplikasi terbuka. Push sungguhan (aplikasi tertutup) butuh FCM/server.
- Data harga/stok berasal dari katalog (aset + server lokal), jadi perubahan nyata hanya terjadi bila katalog diperbarui.
- Agenda belum membaca kalender bawaan perangkat (plugin kalender hanya ada di HP).
- Try-on bukan AR pelacak tubuh; pengguna menyelaraskan sendiri dengan garis bantu.
