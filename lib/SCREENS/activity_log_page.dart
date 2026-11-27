import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/activity_model.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/formatters.dart';
import '../WIDGETS/member_required_view.dart';
import '../WIDGETS/ui_kit.dart';

/// Log aktivitas akun: pendaftaran, masuk/keluar, pesanan, ulasan, dll.
/// Berguna untuk memantau alur penggunaan akun.
class ActivityLogPage extends StatefulWidget {
  const ActivityLogPage({super.key});

  @override
  State<ActivityLogPage> createState() => _ActivityLogPageState();
}

class _ActivityLogPageState extends State<ActivityLogPage> {
  ActivityType? _filter;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('AKTIVITAS AKUN')),
      body: SafeArea(
        child: auth.isLoggedIn
            ? _buildBody(auth)
            : const MemberRequiredView(
                title: 'Aktivitas akun khusus member',
                message: 'Masuk untuk melihat catatan aktivitas akun Anda.',
                icon: Icons.history,
              ),
      ),
    );
  }

  Widget _buildBody(AuthProvider auth) {
    final all = auth.myActivities;
    final events =
        _filter == null ? all : all.where((e) => e.type == _filter).toList();

    final usedTypes = <ActivityType>[
      for (final type in ActivityType.values)
        if (all.any((e) => e.type == type)) type,
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                children: [
                  _chip('Semua', null),
                  for (final type in usedTypes) _chip(type.label, type),
                ],
              ),
            ),
            Expanded(
              child: events.isEmpty
                  ? const EmptyState(
                      icon: Icons.history,
                      title: 'Belum ada aktivitas',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: events.length,
                      itemBuilder: (context, index) => _EventTile(
                        event: events[index],
                        isLast: index == events.length - 1,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, ActivityType? type) {
    final selected = _filter == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: AppColors.ink,
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? AppColors.ink : AppColors.line),
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        onSelected: (_) => setState(() => _filter = type),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.isLast});

  final ActivityEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = event.type.color;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                IconBadge(icon: event.type.icon, color: color, size: 36),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: AppColors.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (event.points != 0)
                        Text(
                          '${event.points > 0 ? '+' : ''}${event.points} poin',
                          style: TextStyle(
                            color: event.points > 0
                                ? AppColors.success
                                : AppColors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  if (event.detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      event.detail,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '${formatDateTime(event.at)} • ${timeAgo(event.at)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
