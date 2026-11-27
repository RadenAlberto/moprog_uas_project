import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../PROVIDERS/app_state.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/time_utils.dart';
import 'product_card.dart';

/// Bagian "Flash Sale" dengan hitung mundur hingga tengah malam.
class FlashSaleSection extends StatefulWidget {
  const FlashSaleSection({super.key});

  @override
  State<FlashSaleSection> createState() => _FlashSaleSectionState();
}

class _FlashSaleSectionState extends State<FlashSaleSection> {
  Timer? _timer;
  late Duration _left;

  @override
  void initState() {
    super.initState();
    _left = timeUntilMidnight(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = timeUntilMidnight(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sale = context.select<AppState, int>((s) => s.saleProducts.length);
    if (sale == 0) return const SizedBox.shrink();
    final products = context.read<AppState>().saleProducts;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.red, AppColors.redDark],
        ),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.bolt_rounded, color: Colors.amber, size: 26),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Flash Sale',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                _TimeBox(value: twoDigits(_left.inHours)),
                const _Colon(),
                _TimeBox(value: twoDigits(_left.inMinutes % 60)),
                const _Colon(),
                _TimeBox(value: twoDigits(_left.inSeconds % 60)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text(
              'Diskon terbatas, berakhir tengah malam ini.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          HorizontalProductList(products: products),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        ':',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
    );
  }
}
