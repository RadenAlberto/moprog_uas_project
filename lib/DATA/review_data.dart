import '../MODELS/review_model.dart';

const List<String> _names = [
  'Dewi', 'Rizky', 'Anisa', 'Budi', 'Maya', 'Fajar',
  'Sinta', 'Andre', 'Putri', 'Kevin', 'Laras', 'Hendra',
];

const List<(int, String)> _pool = [
  (5, 'Bahannya halus dan nyaman dipakai seharian. Sesuai ekspektasi.'),
  (5, 'Potongannya rapi, ukuran pas sesuai tabel. Pasti beli lagi.'),
  (4, 'Kualitas bagus untuk harganya. Warna sesuai foto.'),
  (5, 'Adem, tidak gerah, cocok untuk cuaca Jakarta.'),
  (4, 'Jahitan rapi dan tidak mudah kusut setelah dicuci.'),
  (5, 'Dipakai untuk kuliah dan jalan-jalan, nyaman sekali.'),
  (4, 'Ukurannya sedikit longgar, tapi justru enak dipakai.'),
  (5, 'Simpel dan mudah dipadukan dengan outfit apa pun.'),
  (4, 'Pengiriman cepat dan kemasan rapi. Produk sesuai deskripsi.'),
  (3, 'Bagus, hanya warnanya sedikit lebih gelap dari foto.'),
  (5, 'Tidak luntur setelah beberapa kali dicuci. Worth it!'),
  (4, 'Cocok untuk harian, bahan lembut di kulit.'),
];

/// Ulasan awal (DATA CONTOH) yang dibuat deterministik dari id produk,
/// supaya halaman ulasan tidak kosong saat pertama kali dibuka.
List<Review> sampleReviewsFor(String productId) {
  final seed = int.tryParse(productId) ?? productId.hashCode.abs();
  final base = DateTime(2026, 9, 20);
  return [
    for (var i = 0; i < 3; i++)
      () {
        final entry = _pool[(seed * 5 + i * 4) % _pool.length];
        return Review(
          id: 'sample-$productId-$i',
          productId: productId,
          memberId: 'sample',
          author: _names[(seed * 3 + i * 5) % _names.length],
          rating: entry.$1,
          text: entry.$2,
          at: base.subtract(Duration(days: 4 + i * 9 + seed % 5)),
          isSample: true,
        );
      }(),
  ];
}
