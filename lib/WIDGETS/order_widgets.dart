import 'package:flutter/material.dart';

import '../MODELS/order_model.dart';

/// Lencana status pesanan berwarna.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({super.key, required this.status, this.label});

  final OrderStatus status;

  /// Teks pengganti (mis. "Siap diambil" untuk pesanan ambil di toko).
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 13, color: status.color),
          const SizedBox(width: 4),
          Text(
            label ?? status.label,
            style: TextStyle(
              color: status.color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
