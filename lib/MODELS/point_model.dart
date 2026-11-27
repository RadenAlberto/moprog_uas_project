import 'activity_model.dart';
import 'member_model.dart';
import 'order_model.dart';
import 'pricing.dart';

/// Satu baris riwayat poin (positif = masuk, negatif = terpakai).
class PointEntry {
  final String title;
  final String detail;
  final int points;
  final DateTime at;

  const PointEntry({
    required this.title,
    this.detail = '',
    required this.points,
    required this.at,
  });
}

/// Menyusun riwayat poin (terbaru dulu) dari bonus daftar, check-in, dan
/// pesanan. Pesanan yang dibatalkan menampilkan poin yang dikembalikan.
List<PointEntry> buildPointHistory(
  Member member,
  List<Order> orders,
  List<ActivityEvent> activities,
) {
  final entries = <PointEntry>[
    PointEntry(
      title: 'Bonus pendaftaran',
      detail: 'Selamat datang di member LifeWear',
      points: PricingRules.welcomeBonusPoints,
      at: member.joinedAt,
    ),
    for (final event in activities)
      if (event.type == ActivityType.checkIn && event.points != 0)
        PointEntry(
          title: 'Check-in harian',
          detail: event.detail,
          points: event.points,
          at: event.at,
        ),
  ];

  for (final order in orders) {
    if (order.pointsEarned > 0) {
      entries.add(PointEntry(
        title: 'Poin dari belanja',
        detail: order.id,
        points: order.isCancelled ? 0 : order.pointsEarned,
        at: order.createdAt,
      ));
    }
    if (order.pointsUsed > 0) {
      entries.add(PointEntry(
        title: 'Tukar poin',
        detail: order.isCancelled
            ? '${order.id} (dibatalkan, poin dikembalikan)'
            : order.id,
        points: order.isCancelled ? 0 : -order.pointsUsed,
        at: order.createdAt,
      ));
    }
  }

  entries.removeWhere((e) => e.points == 0);
  entries.sort((a, b) => b.at.compareTo(a.at));
  return entries;
}
