import 'order_model.dart';

class MonthSpend {
  final DateTime month;
  final double amount;
  final int orders;

  const MonthSpend({
    required this.month,
    required this.amount,
    required this.orders,
  });
}

class CategorySpend {
  final String category;
  final double amount;
  final int quantity;

  const CategorySpend({
    required this.category,
    required this.amount,
    required this.quantity,
  });
}

class MethodUsage {
  final String method;
  final int count;
  final double amount;

  const MethodUsage({
    required this.method,
    required this.count,
    required this.amount,
  });
}

/// Ringkasan belanja untuk halaman "Statistik Belanja".
class SpendingStats {
  final double totalPaid;
  final double totalSavings;
  final int orderCount;
  final int cancelledCount;
  final int itemCount;
  final List<MonthSpend> months;
  final List<CategorySpend> categories;
  final List<MethodUsage> methods;

  const SpendingStats({
    required this.totalPaid,
    required this.totalSavings,
    required this.orderCount,
    required this.cancelledCount,
    required this.itemCount,
    required this.months,
    required this.categories,
    required this.methods,
  });

  double get averageOrder => orderCount == 0 ? 0 : totalPaid / orderCount;

  double get maxMonthAmount {
    var max = 0.0;
    for (final m in months) {
      if (m.amount > max) max = m.amount;
    }
    return max;
  }

  double get categoryTotal =>
      categories.fold<double>(0, (sum, c) => sum + c.amount);
}

/// Menghitung statistik dari daftar pesanan.
/// Pesanan dibatalkan hanya dihitung pada [SpendingStats.cancelledCount].
SpendingStats buildSpendingStats(
  List<Order> orders, {
  required String Function(String productId) categoryOf,
  DateTime? now,
  int monthCount = 6,
}) {
  final today = now ?? DateTime.now();

  final monthKeys = <DateTime>[
    for (var i = monthCount - 1; i >= 0; i--)
      DateTime(today.year, today.month - i, 1),
  ];
  final monthAmount = <int, double>{};
  final monthOrders = <int, int>{};
  int keyOf(DateTime d) => d.year * 12 + d.month;

  final categoryAmount = <String, double>{};
  final categoryQty = <String, int>{};
  final methodCount = <String, int>{};
  final methodAmount = <String, double>{};

  var totalPaid = 0.0;
  var savings = 0.0;
  var cancelled = 0;
  var orderCount = 0;
  var itemCount = 0;

  for (final order in orders) {
    if (order.isCancelled) {
      cancelled++;
      continue;
    }
    // Statistik transaksi memakai kelompok yang sama dengan ringkasan:
    // hanya pembayaran yang sudah Paid; COD Unpaid belum menjadi belanja.
    if (!order.isPaid) continue;
    orderCount++;
    totalPaid += order.total;
    savings += order.totalSavings;
    itemCount += order.itemCount;

    final key = keyOf(order.createdAt);
    monthAmount[key] = (monthAmount[key] ?? 0) + order.total;
    monthOrders[key] = (monthOrders[key] ?? 0) + 1;

    methodCount[order.paymentMethod] =
        (methodCount[order.paymentMethod] ?? 0) + 1;
    methodAmount[order.paymentMethod] =
        (methodAmount[order.paymentMethod] ?? 0) + order.total;

    final ratio =
        order.subtotal > 0 ? order.merchandisePaid / order.subtotal : 1.0;
    for (final item in order.items) {
      final category = categoryOf(item.productId);
      categoryAmount[category] =
          (categoryAmount[category] ?? 0) + item.lineTotal * ratio;
      categoryQty[category] = (categoryQty[category] ?? 0) + item.quantity;
    }
  }

  final categories = [
    for (final entry in categoryAmount.entries)
      CategorySpend(
        category: entry.key,
        amount: entry.value,
        quantity: categoryQty[entry.key] ?? 0,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  final methods = [
    for (final entry in methodCount.entries)
      MethodUsage(
        method: entry.key,
        count: entry.value,
        amount: methodAmount[entry.key] ?? 0,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));

  return SpendingStats(
    totalPaid: totalPaid,
    totalSavings: savings,
    orderCount: orderCount,
    cancelledCount: cancelled,
    itemCount: itemCount,
    months: [
      for (final month in monthKeys)
        MonthSpend(
          month: month,
          amount: monthAmount[keyOf(month)] ?? 0,
          orders: monthOrders[keyOf(month)] ?? 0,
        ),
    ],
    categories: categories,
    methods: methods,
  );
}
