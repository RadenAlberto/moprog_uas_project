import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/order_model.dart';
import '../PROVIDERS/app_state.dart';
import 'toast.dart';

/// "Beli Lagi": memasukkan semua item pesanan lama ke keranjang, lalu
/// membuka tab Keranjang.
void reorderItems(BuildContext context, Order order) {
  final appState = context.read<AppState>();
  final added = appState.addOrderItemsToCart(order.items);

  if (added == 0) {
    showAppToast(
      context,
      'Produk pada pesanan ini sudah tidak tersedia',
      color: Colors.red.shade700,
      icon: Icons.error_outline,
    );
    return;
  }

  showAppToast(
    context,
    '$added produk dimasukkan ke keranjang',
    icon: Icons.shopping_bag,
  );
  Navigator.of(context).popUntil((route) => route.isFirst);
  appState.setTab(3);
}
