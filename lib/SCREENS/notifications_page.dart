import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/news_model.dart';
import '../MODELS/order_model.dart';
import '../PROVIDERS/app_state.dart';
import '../PROVIDERS/auth_provider.dart';
import '../UTILS/formatters.dart';
import '../WIDGETS/news_widgets.dart';
import 'order_detail_page.dart';

/// Pusat notifikasi: status pesanan, berita & promo, dan pemberitahuan umum.
class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final auth = context.watch<AuthProvider>();
    final orders = auth.myOrders.take(5).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          'NOTIFIKASI',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Tandai semua sudah dibaca',
            icon: const Icon(Icons.done_all),
            onPressed: appState.unreadNewsCount == 0
                ? null
                : appState.markAllNewsRead,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (auth.isLoggedIn) ...[
                  const _GroupTitle('Pesanan Anda'),
                  if (orders.isEmpty)
                    const _EmptyLine('Belum ada pesanan.')
                  else
                    for (final order in orders) _OrderNotification(order: order),
                  const SizedBox(height: 16),
                ],
                const _GroupTitle('Berita & Promo'),
                for (final item in appState.news.take(6))
                  _Tile(
                    leading: Icon(item.category.icon, color: item.category.color),
                    title: item.title,
                    subtitle:
                        '${item.category.label}  |  ${formatDate(item.date)}',
                    unread: !appState.isNewsRead(item.id),
                    onTap: () => openNews(context, item),
                  ),
                const SizedBox(height: 16),
                const _GroupTitle('Pemberitahuan'),
                for (final text in appState.notifications)
                  _Tile(
                    leading: const Icon(Icons.info_outline,
                        color: Color(0xFF1565C0)),
                    title: text,
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderNotification extends StatelessWidget {
  const _OrderNotification({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final status = order.status;

    return _Tile(
      leading: Icon(status.icon, color: status.color),
      title: '${order.id} - ${order.statusLabel(status)}',
      subtitle:
          '${order.statusDescription(status)}  ${timeAgo(order.stageStart(status))}',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OrderDetailPage(orderId: order.id),
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.unread = false,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final bool unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: unread ? const Color(0xFFFFF8F8) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unread ? const Color(0xFFFFCDD2) : Colors.grey.shade200,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: leading,
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
              ),
        trailing: unread
            ? Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFEC1C24),
                  shape: BoxShape.circle,
                ),
              )
            : (onTap == null ? null : const Icon(Icons.chevron_right)),
      ),
    );
  }
}
