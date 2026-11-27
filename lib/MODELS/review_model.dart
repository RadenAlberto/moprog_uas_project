/// Ulasan produk.
class Review {
  final String id;
  final String productId;
  final String memberId;
  final String author;
  final int rating;
  final String text;
  final DateTime at;

  /// `true` untuk ulasan awal (data contoh bawaan aplikasi).
  final bool isSample;

  const Review({
    required this.id,
    required this.productId,
    required this.memberId,
    required this.author,
    required this.rating,
    required this.text,
    required this.at,
    this.isSample = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'memberId': memberId,
        'author': author,
        'rating': rating,
        'text': text,
        'at': at.toIso8601String(),
      };

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      productId: json['productId'] as String,
      memberId: json['memberId'] as String,
      author: json['author'] as String,
      rating: ((json['rating'] as num).toInt()).clamp(1, 5).toInt(),
      text: (json['text'] as String?) ?? '',
      at: DateTime.parse(json['at'] as String),
      isSample: json['isSample'] == true || json['is_sample'] == 1 || json['source'] == 'sample',
    );
  }
}

/// Ringkasan rating: rata-rata dan jumlah ulasan.
class RatingSummary {
  final double average;
  final int count;

  const RatingSummary(this.average, this.count);

  /// Record agar mudah dipakai dengan `context.select` (punya kesamaan nilai).
  (double, int) get record => (double.parse(average.toStringAsFixed(1)), count);
}
