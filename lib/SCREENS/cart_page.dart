import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../MODELS/product_model.dart';
import '../PROVIDERS/app_state.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/auth_gate.dart';
import '../UTILS/formatters.dart';
import '../UTILS/nav.dart';
import '../WIDGETS/product_image.dart';
import '../WIDGETS/ui_kit.dart';
import 'checkout_page.dart';
import 'detailproduk_uniqlo.dart';

/// Tab Keranjang. Checkout hanya untuk member: tamu diminta masuk/daftar dulu
/// (isi keranjang tetap tersimpan dan ikut pindah ke akun).
class CartPage extends StatelessWidget {
  const CartPage({super.key});

  Future<void> _checkout(BuildContext context) async {
    final ok = await requireMember(context);
    if (!ok || !context.mounted) return;
    await pushPage(context, const CheckoutPage());
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final cart = appState.cart;
    final checkedCount = appState.checkedCartItems.length;
    final allChecked = cart.isNotEmpty && checkedCount == cart.length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('KERANJANG')),
      body: SafeArea(
        child: cart.isEmpty
            ? EmptyState(
                icon: Icons.shopping_bag_outlined,
                title: 'Keranjang masih kosong',
                message:
                    'Tambahkan produk favorit Anda, lalu lanjutkan ke pembayaran.',
                actionLabel: 'Mulai Belanja',
                onAction: () => appState.setTab(1),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: allChecked,
                            activeColor: AppColors.red,
                            onChanged: (_) {
                              for (var i = 0; i < cart.length; i++) {
                                if (cart[i].isChecked == allChecked) {
                                  appState.toggleCartCheck(i);
                                }
                              }
                            },
                          ),
                          Expanded(
                            child: Text(
                              'Pilih semua (${cart.length} baris)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      for (var i = 0; i < cart.length; i++)
                        _CartTile(index: i, item: cart[i]),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total (belum termasuk ongkir & diskon)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  formatRupiah(appState.selectedCartTotal),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: checkedCount == 0
                              ? null
                              : () => _checkout(context),
                          child: Text(
                            'CHECKOUT ($checkedCount)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _CartTile extends StatelessWidget {
  const _CartTile({required this.index, required this.item});

  final int index;
  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    final product = item.product;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
      decoration: cardDecoration(radius: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.isChecked,
            activeColor: AppColors.red,
            onChanged: (_) => appState.toggleCartCheck(index),
          ),
          GestureDetector(
            onTap: () =>
                pushPage(context, ProductDetailPage(product: product)),
            child: ProductImage(
              product,
              color: item.selectedColor,
              width: 72,
              height: 96,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Ukuran ${item.selectedSize}  |  ${product.colorNameOf(item.selectedColor) ?? colorLabel(item.selectedColor)}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatRupiah(item.lineTotal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: AppColors.red,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.remove,
                      onTap: () => appState.updateQuantity(index, -1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _QtyButton(
                      icon: Icons.add,
                      onTap: () => appState.updateQuantity(index, 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Hapus dari keranjang',
            icon: const Icon(Icons.close, color: Colors.grey, size: 18),
            onPressed: () => appState.removeFromCart(index),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16),
      ),
    );
  }
}
