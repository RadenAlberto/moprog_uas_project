import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/stats_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../WIDGETS/member_required_view.dart';
import '../WIDGETS/ui_kit.dart';

const List<String> _monthLabels = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

const List<Color> _categoryColors = [
  Color(0xFFEC1C24),
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFFEF6C00),
  Color(0xFF6A4FA3),
  Color(0xFF00897B),
];

/// Statistik belanja: pengeluaran per bulan, kategori favorit, dan metode
/// pembayaran yang paling sering dipakai.
class SpendingStatsPage extends StatelessWidget {
  const SpendingStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('STATISTIK BELANJA')),
      body: SafeArea(
        child: auth.isLoggedIn
            ? _buildBody(auth.stats)
            : const MemberRequiredView(
                title: 'Statistik belanja khusus member',
                message: 'Masuk atau gabung member untuk memantau '
                    'pengeluaran dan kebiasaan belanja Anda.',
                icon: Icons.insights_outlined,
              ),
      ),
    );
  }

  Widget _buildBody(SpendingStats stats) {
    if (stats.orderCount == 0 && stats.cancelledCount == 0) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'Belum ada data belanja',
        message: 'Statistik muncul setelah Anda menyelesaikan checkout.',
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.payments_outlined,
                    label: 'Total belanja',
                    value: formatRupiahCompact(stats.totalPaid),
                    color: AppColors.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.savings_outlined,
                    label: 'Total hemat',
                    value: formatRupiahCompact(stats.totalSavings),
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Pesanan',
                    value: '${stats.orderCount}',
                    color: const Color(0xFF1565C0),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.checkroom_outlined,
                    label: 'Barang dibeli',
                    value: '${stats.itemCount}',
                    color: const Color(0xFF6A4FA3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              child: Row(
                children: [
                  const IconBadge(icon: Icons.receipt_outlined),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Rata-rata per pesanan',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    formatRupiah(stats.averageOrder),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            if (stats.cancelledCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${stats.cancelledCount} pesanan dibatalkan tidak dihitung.',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            _section('Belanja 6 bulan terakhir'),
            SurfaceCard(child: _MonthChart(stats: stats)),
            const SizedBox(height: 20),
            _section('Kategori favorit'),
            SurfaceCard(child: _CategoryBreakdown(stats: stats)),
            const SizedBox(height: 20),
            _section('Metode pembayaran'),
            SurfaceCard(child: _MethodList(stats: stats)),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 36),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MonthChart extends StatelessWidget {
  const _MonthChart({required this.stats});

  final SpendingStats stats;

  @override
  Widget build(BuildContext context) {
    final max = stats.maxMonthAmount;

    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final month in stats.months)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    month.amount == 0 ? '' : formatRupiahCompact(month.amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: max == 0
                        ? 4
                        : (4 + 110 * (month.amount / max)).toDouble(),
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: month.amount == 0 ? AppColors.line : AppColors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _monthLabels[month.month.month - 1],
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.stats});

  final SpendingStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.categories.isEmpty) {
      return const Text('Belum ada data kategori.');
    }
    final total = stats.categoryTotal;
    final shown = stats.categories.take(6).toList();

    return Column(
      children: [
        for (var i = 0; i < shown.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shown[i].category,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${shown[i].quantity} pcs • ${formatRupiahCompact(shown[i].amount)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : shown[i].amount / total,
                    minHeight: 8,
                    backgroundColor: AppColors.line,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _categoryColors[i % _categoryColors.length],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MethodList extends StatelessWidget {
  const _MethodList({required this.stats});

  final SpendingStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.methods.isEmpty) {
      return const Text('Belum ada data metode pembayaran.');
    }
    return Column(
      children: [
        for (final method in stats.methods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.credit_card, size: 20, color: AppColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    method.method,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${method.count}x • ${formatRupiahCompact(method.amount)}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
