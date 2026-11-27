import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/point_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../WIDGETS/member_required_view.dart';
import '../WIDGETS/ui_kit.dart';

/// Riwayat poin: dari mana poin didapat dan untuk apa dipakai.
class PointHistoryPage extends StatelessWidget {
  const PointHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('RIWAYAT POIN')),
      body: SafeArea(
        child: auth.isLoggedIn
            ? RefreshIndicator(onRefresh: auth.refreshServerData, child: _buildBody(auth))
            : const MemberRequiredView(
                title: 'Riwayat poin khusus member',
                message: 'Masuk atau gabung member untuk mulai mengumpulkan '
                    'dan melihat poin Anda.',
                icon: Icons.stars_outlined,
              ),
      ),
    );
  }

  Widget _buildBody(AuthProvider auth) {
    final entries = auth.pointHistory;
    var earned = 0;
    var used = 0;
    for (final e in entries) {
      if (e.points > 0) {
        earned += e.points;
      } else {
        used += -e.points;
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.red, AppColors.redDark],
                ),
                boxShadow: AppShadows.lift,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'POIN TERSEDIA',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${auth.points}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Setara ${formatRupiah(auth.points * 100)} untuk potongan belanja',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _stat('Total didapat', '+$earned')),
                      Expanded(child: _stat('Total dipakai', '-$used')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Riwayat',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyState(
                  icon: Icons.stars_outlined,
                  title: 'Belum ada aktivitas poin',
                ),
              )
            else
              for (final entry in entries) _PointTile(entry: entry),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PointTile extends StatelessWidget {
  const _PointTile({required this.entry});

  final PointEntry entry;

  @override
  Widget build(BuildContext context) {
    final positive = entry.points > 0;
    final color = positive ? AppColors.success : AppColors.red;

    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(
            icon: positive ? Icons.add_circle_outline : Icons.remove_circle_outline,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                if (entry.detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  formatDateTime(entry.at),
                  style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${entry.points}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
