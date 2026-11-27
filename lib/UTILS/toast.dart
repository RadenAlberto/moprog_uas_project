import 'dart:async';

import 'package:flutter/material.dart';

/// Toast di bagian atas layar (gaya yang sama dengan versi sebelumnya,
/// dipindahkan agar bisa dipakai di semua halaman).
void showAppToast(
  BuildContext context,
  String message, {
  Color color = const Color(0xFF16A34A),
  IconData icon = Icons.check_circle,
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (overlayContext) {
      final top = MediaQuery.of(overlayContext).padding.top + 12;

      return Positioned(
        top: top,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _TopToast(
                message: message,
                color: color,
                icon: icon,
                onFinished: () {
                  if (entry.mounted) {
                    entry.remove();
                  }
                },
              ),
            ),
          ),
        ),
      );
    },
  );

  overlay.insert(entry);
}

class _TopToast extends StatefulWidget {
  const _TopToast({
    required this.message,
    required this.color,
    required this.icon,
    required this.onFinished,
  });

  final String message;
  final Color color;
  final IconData icon;
  final VoidCallback onFinished;

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), widget.onFinished);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * -12),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(widget.icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
