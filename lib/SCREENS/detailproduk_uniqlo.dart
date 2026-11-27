import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/activity_model.dart';
import '../MODELS/product_model.dart';
import '../MODELS/review_model.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/auth_gate.dart';
import '../UTILS/formatters.dart';
import '../UTILS/nav.dart';
import '../UTILS/toast.dart';
import '../WIDGETS/app_network_image.dart';
import '../WIDGETS/product_card.dart';
import '../WIDGETS/product_image.dart';
import '../WIDGETS/ui_kit.dart';
import '../PROVIDERS/tracker_provider.dart';
import 'fit_calculator_page.dart';
import 'price_tracker_page.dart';
import 'size_guide_page.dart';
import 'try_on_page.dart';

/// Detail produk: foto, harga, pilihan warna/ukuran, ulasan, dan produk serupa.
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key, required this.product});

  final Product product;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late String _selectedSize;
  late Color _selectedColor;

  /// Foto galeri yang sedang dibuka; `null` = foto utama sesuai warna.
  String? _galleryUrl;
  bool _showAllReviews = false;

  Product get _product => widget.product;

  @override
  void initState() {
    super.initState();
    _selectedSize =
        _product.availableSizes.isNotEmpty ? _product.availableSizes.first : 'S';
    _selectedColor = _product.availableColors.isNotEmpty
        ? _product.availableColors.first
        : Colors.black;

    // notifyListeners tidak boleh dipanggil saat build; tunggu frame pertama.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().markViewed(_product);
    });
  }

  Future<void> _findMySize() async {
    final size = await pushPage<String>(
      context,
      FitCalculatorPage(product: _product),
    );
    if (size != null && mounted && _product.availableSizes.contains(size)) {
      setState(() => _selectedSize = size);
    }
  }

  Future<void> _writeReview() async {
    final ok = await requireMember(
      context,
      message: 'Menulis ulasan khusus member UNIQLO. Masuk atau gabung member '
          'untuk membagikan pengalaman Anda.',
    );
    if (!ok || !mounted) return;

    final auth = context.read<AuthProvider>();
    final appState = context.read<AppState>();
    final member = auth.currentMember;
    if (member == null) return;

    if (appState.hasReviewed(_product.id, member.id)) {
      showAppToast(
        context,
        'Anda sudah memberi ulasan untuk produk ini',
        color: Colors.grey.shade900,
        icon: Icons.info_outline,
      );
      return;
    }

    final result = await showModalBottomSheet<_ReviewDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _ReviewSheet(productName: _product.name),
    );
    if (result == null || !mounted) return;

    await appState.addReview(
      product: _product,
      memberId: member.id,
      author: member.name,
      rating: result.rating,
      text: result.text,
    );
    await auth.logActivity(
      ActivityType.review,
      'Ulasan untuk ${_product.name}',
      detail: '${result.rating} bintang',
    );
    if (!mounted) return;
    showAppToast(context, 'Terima kasih! Ulasan Anda tersimpan.',
        icon: Icons.rate_review);
  }

  /// Thumbnail galeri. [url] null = foto utama (sesuai warna terpilih).
  Widget _thumb(String imageUrl, String? url) {
    final selected = _galleryUrl == url;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _galleryUrl = url),
        child: Container(
          width: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? Colors.black : AppColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: AppNetworkImage(
            imageUrl,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isLiked = appState.isWishlisted(_product);
    final rating = appState.ratingOf(_product);
    final reviews = appState.reviewsFor(_product.id);
    final shownReviews = _showAllReviews ? reviews : reviews.take(3).toList();
    final similar = appState.allProducts
        .where((p) => p.id != _product.id && p.category == _product.category)
        .take(8)
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('DETAIL PRODUK'),
        actions: [
          IconButton(
            tooltip: isLiked ? 'Hapus dari wishlist' : 'Simpan ke wishlist',
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? AppColors.red : Colors.black,
            ),
            onPressed: () => appState.toggleWishlist(_product, context),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              children: [
                // Bingkai foto 3:4 (sama dengan foto Uniqlo): foto tampil utuh,
                // tidak terpotong. Di layar lebar dibatasi 480 px dan ditaruh
                // di tengah supaya tidak membesar berlebihan.
                Container(
                  color: const Color(0xFFF3F3F3),
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: AspectRatio(
                      aspectRatio: kProductPhotoAspect,
                      child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_galleryUrl == null)
                      ProductImage(
                        _product,
                        color: _selectedColor,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    else
                      // Foto galeri bisa berbeda rasio: tampilkan utuh.
                      AppNetworkImage(
                        _galleryUrl!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                      ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_product.isOnSale)
                            PillTag(label: '-${_product.discountPercent}%'),
                          if (_product.isNew)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: PillTag(
                                label: 'BARU',
                                color: AppColors.ink,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                      ),
                    ),
                  ),
                ),
                if (_product.galleryFor(_selectedColor).isNotEmpty)
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      children: [
                        _thumb(_product.imageFor(_selectedColor), null),
                        for (final url in _product.galleryFor(_selectedColor))
                          _thumb(url, url),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _product.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          RatingStars(rating: rating.average, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            rating.count == 0
                                ? 'Belum ada ulasan'
                                : '${rating.average.toStringAsFixed(1)} (${rating.count} ulasan)',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _product.formattedPrice,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.red,
                            ),
                          ),
                          if (_product.isOnSale) ...[
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                _product.formattedOriginalPrice,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.muted,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (_product.features.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final feature in _product.features)
                              PillTag(
                                label: feature.toUpperCase(),
                                color: AppColors.redSoft,
                                textColor: AppColors.red,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      Text(
                        'Warna: ${_product.colorNameOf(_selectedColor) ?? colorLabel(_selectedColor)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          for (final color in _product.availableColors)
                            GestureDetector(
                              onTap: () => setState(() {
                                _selectedColor = color;
                                _galleryUrl = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _selectedColor.toARGB32() ==
                                            color.toARGB32()
                                        ? Colors.black
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  backgroundColor: color,
                                  radius: 14,
                                  child: color.toARGB32() ==
                                          Colors.white.toARGB32()
                                      ? Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.black26,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ukuran: $_selectedSize',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                pushPage(context, const SizeGuidePage()),
                            icon: const Icon(Icons.straighten,
                                size: 16, color: AppColors.red),
                            label: const Text(
                              'Panduan ukuran',
                              style: TextStyle(
                                color: AppColors.red,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final size in _product.availableSizes)
                            GestureDetector(
                              onTap: () => setState(() => _selectedSize = size),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: size == _selectedSize
                                      ? Colors.black
                                      : Colors.white,
                                  border: Border.all(color: Colors.black),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  size,
                                  style: TextStyle(
                                    color: size == _selectedSize
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.straighten, size: 16),
                            label: const Text('Cari ukuran saya'),
                            onPressed: _findMySize,
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.view_in_ar_outlined, size: 16),
                            label: const Text('Coba virtual'),
                            onPressed: () =>
                                pushPage(context, TryOnPage(product: _product)),
                          ),
                          ActionChip(
                            avatar: Icon(
                              context.select<TrackerProvider, bool>((t) =>
                                      t.isTracked(_product.id, _selectedSize))
                                  ? Icons.notifications_active
                                  : Icons.notifications_none,
                              size: 16,
                            ),
                            label: const Text('Lacak harga'),
                            onPressed: () => showTrackSheet(
                              context,
                              _product,
                              size: _selectedSize,
                              color: _selectedColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Deskripsi',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _product.description,
                        style: const TextStyle(height: 1.45),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ulasan (${reviews.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.red,
                              side: const BorderSide(color: AppColors.red),
                            ),
                            onPressed: _writeReview,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Tulis ulasan'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final review in shownReviews)
                        _ReviewTile(review: review),
                      if (reviews.length > 3)
                        TextButton(
                          onPressed: () => setState(
                            () => _showAllReviews = !_showAllReviews,
                          ),
                          child: Text(
                            _showAllReviews
                                ? 'Tampilkan lebih sedikit'
                                : 'Lihat semua ulasan',
                            style: const TextStyle(color: AppColors.red),
                          ),
                        ),
                    ],
                  ),
                ),
                if (similar.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'Produk Serupa',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  HorizontalProductList(products: similar),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => appState.addToCart(
                  _product,
                  _selectedSize,
                  _selectedColor,
                  context,
                ),
                child: const Text(
                  'TAMBAH KE KERANJANG',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.redSoft,
                child: Text(
                  review.author.isEmpty ? '?' : review.author[0].toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.author,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                formatDate(review.at),
                style: const TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          RatingStars(rating: review.rating.toDouble(), size: 14),
          if (review.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.text, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _ReviewDraft {
  const _ReviewDraft(this.rating, this.text);

  final int rating;
  final String text;
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.productName});

  final String productName;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final TextEditingController _controller = TextEditingController();
  int _rating = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ulasan: ${widget.productName}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i bintang',
                    onPressed: () => setState(() => _rating = i),
                    icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: AppColors.star,
                      size: 34,
                    ),
                  ),
              ],
            ),
            TextField(
              controller: _controller,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: 'Ceritakan pengalaman Anda (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.of(context).pop(
                _ReviewDraft(_rating, _controller.text.trim()),
              ),
              child: const Text(
                'KIRIM ULASAN',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
