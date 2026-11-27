import '../MODELS/member_model.dart';
import '../MODELS/news_model.dart';
import '../MODELS/pricing.dart';
import '../UTILS/formatters.dart';

/// Gambar memakai URL Unsplash yang sama dengan katalog produk.
String _img(String photoId) =>
    'https://images.unsplash.com/$photoId?q=80&w=1000';

/// Berita & info contoh (data contoh aplikasi, bukan berita resmi).
final List<NewsItem> kNews = [
  NewsItem(
    id: 'n1',
    title: 'Promo Akhir Tahun: Diskon Hingga 30%',
    summary:
        'Jaket, jeans, dan fleece pilihan turun harga selama periode promo akhir tahun.',
    content:
        'Sambut akhir tahun dengan koleksi LifeWear pilihan yang kini tersedia dengan harga spesial. '
        'Ultra Light Down Jacket, Wide Straight Jeans, Parka UV Protection, hingga Fleece Full-Zip Jacket '
        'mendapat potongan harga hingga 30%.\n\n'
        'Cari label harga coret di halaman produk untuk melihat berapa banyak yang Anda hemat. '
        'Promo dapat digabungkan dengan diskon level member dan voucher yang berlaku.\n\n'
        'Stok terbatas dan dapat berubah sewaktu-waktu. Selesaikan pesanan Anda lebih awal agar tidak kehabisan ukuran favorit.',
    image: _img('photo-1544441893-675973e31985'),
    category: NewsCategory.promo,
    date: DateTime(2026, 10, 14),
    isPinned: true,
    action: NewsAction.catalog,
    actionLabel: 'Belanja Sekarang',
  ),
  NewsItem(
    id: 'n2',
    title:
        'Gabung Member LifeWear, Dapatkan ${PricingRules.welcomeBonusPoints} Poin Gratis',
    summary:
        'Daftar sekarang untuk diskon otomatis, kumpulkan poin, dan lacak riwayat pembelian Anda.',
    content:
        'Menjadi member LifeWear gratis dan hanya butuh satu menit. Setelah mendaftar, Anda langsung mendapat '
        '${PricingRules.welcomeBonusPoints} poin bonus yang bisa ditukar menjadi potongan harga saat checkout '
        '(1 poin = ${formatRupiah(PricingRules.pointValue)}).\n\n'
        'Keuntungan lain: diskon otomatis sesuai level, gratis ongkir dengan minimal belanja lebih rendah, '
        'voucher khusus member, serta riwayat pembelian lengkap yang bisa dicek kapan saja.\n\n'
        'Sudah punya akun? Masuk lewat tab Keanggotaan untuk melihat kartu member digital Anda.',
    image: _img('photo-1507679799987-c73779587ccf'),
    category: NewsCategory.member,
    date: DateTime(2026, 10, 13),
    isPinned: true,
    action: NewsAction.membership,
    actionLabel: 'Buka Keanggotaan',
  ),
  NewsItem(
    id: 'n3',
    title: 'Koleksi HEATTECH untuk Musim Hujan',
    summary:
        'Tetap hangat dan nyaman saat cuaca dingin dengan lapisan dalam HEATTECH.',
    content:
        'Cuaca yang lebih dingin dan basah membutuhkan lapisan yang tepat. HEATTECH Crew Neck T-Shirt dirancang '
        'sebagai lapisan dalam yang tipis namun hangat, mudah dipadukan dengan kemeja, fleece, maupun jaket.\n\n'
        'Padukan dengan Fleece Full-Zip Jacket atau Parka UV Protection yang ringan untuk perlindungan menyeluruh '
        'tanpa terasa berat.',
    image: _img('photo-1551488831-00ddcb6c6bd3'),
    category: NewsCategory.koleksi,
    date: DateTime(2026, 10, 12),
    isPinned: true,
    action: NewsAction.catalog,
    actionLabel: 'Lihat Koleksi',
  ),
  NewsItem(
    id: 'n4',
    title: 'Cara Naik Level Member: Silver, Gold, Platinum',
    summary:
        'Level ditentukan dari total belanja kumulatif. Ini syarat dan keuntungannya.',
    content:
        'Level member dihitung otomatis dari total belanja kumulatif Anda (tidak termasuk ongkir dan pesanan yang dibatalkan).\n\n'
        'Silver: belanja kumulatif ${formatRupiah(MemberTier.silver.minSpend)} (diskon ${MemberTier.silver.discountPercent}%). '
        'Gold: ${formatRupiah(MemberTier.gold.minSpend)} (diskon ${MemberTier.gold.discountPercent}%). '
        'Platinum: ${formatRupiah(MemberTier.platinum.minSpend)} (diskon ${MemberTier.platinum.discountPercent}%).\n\n'
        'Setiap Rp10.000 belanja memberi 1 poin, dikalikan pengali level: Silver x1,25, Gold x1,5, dan Platinum x2. '
        'Pantau progres level Anda di halaman Keanggotaan.',
    image: _img('photo-1602810318383-e386cc2a3ccf'),
    category: NewsCategory.info,
    date: DateTime(2026, 10, 10),
    action: NewsAction.membership,
    actionLabel: 'Lihat Keuntungan Member',
  ),
  NewsItem(
    id: 'n5',
    title: 'Weekend Sale: Voucher Tambahan untuk Member',
    summary:
        'Gunakan voucher HEMAT50 untuk potongan Rp50.000 khusus member.',
    content:
        'Akhir pekan ini, member yang sudah masuk bisa memakai voucher HEMAT50 untuk potongan Rp50.000 '
        'dengan minimal belanja Rp500.000.\n\n'
        'Voucher dapat dipakai di halaman checkout. Jika Anda member Gold atau Platinum, jangan lewatkan voucher '
        'GOLDSPECIAL dengan diskon 15% (maksimal Rp250.000).',
    image: _img('photo-1622290291468-a28f7a7dc6a8'),
    category: NewsCategory.event,
    date: DateTime(2026, 10, 9),
    action: NewsAction.vouchers,
    actionLabel: 'Lihat Voucher',
  ),
  NewsItem(
    id: 'n6',
    title: 'Koleksi Baru: Blouse & Celana Pleats Wanita',
    summary:
        'Tampilan rapi dan nyaman untuk kerja maupun akhir pekan.',
    content:
        'Koleksi wanita terbaru hadir dengan Rayon Blouse yang ringan dan Pleated Wide Pants dengan detail pleats '
        'yang memberi siluet rapi sekaligus nyaman bergerak.\n\n'
        'Padukan keduanya untuk tampilan kantor yang bersih, atau gunakan terpisah dengan item basic favorit Anda.',
    image: _img('photo-1485968579580-b6d095142e6e'),
    category: NewsCategory.koleksi,
    date: DateTime(2026, 10, 7),
    action: NewsAction.catalog,
    actionLabel: 'Lihat Koleksi',
  ),
  NewsItem(
    id: 'n7',
    title: 'Gratis Ongkir dengan Kode ONGKIRFREE',
    summary:
        'Bebas ongkos kirim untuk semua pesanan minimal Rp150.000.',
    content:
        'Masukkan kode ONGKIRFREE di halaman checkout untuk menggratiskan ongkos kirim pesanan Anda '
        '(minimal belanja Rp150.000).\n\n'
        'Member juga mendapat gratis ongkir otomatis dengan minimal belanja yang lebih rendah sesuai level: '
        'Silver ${formatRupiah(MemberTier.silver.freeShippingMinSpend)}, '
        'Gold ${formatRupiah(MemberTier.gold.freeShippingMinSpend)}, dan Platinum tanpa minimal belanja.',
    image: _img('photo-1584917865442-de89df76afd3'),
    category: NewsCategory.promo,
    date: DateTime(2026, 10, 5),
    action: NewsAction.vouchers,
    actionLabel: 'Lihat Voucher',
  ),
  NewsItem(
    id: 'n8',
    title: 'Panduan Memilih Ukuran & Penukaran',
    summary:
        'Tips memilih ukuran yang pas agar nyaman dipakai sehari-hari.',
    content:
        'Tidak yakin dengan ukuran Anda? Bandingkan dengan pakaian yang paling nyaman di lemari Anda, '
        'lalu pilih ukuran yang paling mendekati. Untuk potongan slim seperti Celana Chino Slim Fit, '
        'pertimbangkan satu ukuran lebih besar jika Anda menyukai kesan lebih longgar.\n\n'
        'Pantau status pesanan Anda di Riwayat Pembelian. Pesanan yang masih berstatus Diproses '
        'dapat dibatalkan langsung dari halaman detail pesanan.',
    image: _img('photo-1541099649105-f69ad21f3246'),
    category: NewsCategory.info,
    date: DateTime(2026, 10, 2),
  ),
  NewsItem(
    id: 'n9',
    title: 'Fleece Hangat untuk Perjalanan Anda',
    summary:
        'Ringan, lembut, dan mudah dibawa untuk perjalanan jarak dekat maupun jauh.',
    content:
        'Fleece Full-Zip Jacket menghadirkan kehangatan tanpa bobot berlebih. Bahannya lembut di kulit '
        'dan mudah dipadukan dengan berbagai gaya.\n\n'
        'Tersedia dalam beberapa pilihan warna dan sedang dalam penawaran harga spesial.',
    image: _img('photo-1578587018452-892bacefd3f2'),
    category: NewsCategory.koleksi,
    date: DateTime(2026, 9, 28),
    action: NewsAction.catalog,
    actionLabel: 'Belanja Sekarang',
  ),
];

/// Berita disematkan lebih dulu, lalu yang terbaru.
List<NewsItem> sortedNews(List<NewsItem> source) {
  final list = List<NewsItem>.of(source);
  list.sort((a, b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.date.compareTo(a.date);
  });
  return list;
}
