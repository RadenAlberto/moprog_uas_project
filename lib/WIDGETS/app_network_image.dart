import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../SERVICES/image_cache.dart';

/// Gambar jaringan dengan indikator loading dan tampilan cadangan saat gagal.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
  });

  /// Matikan di unit test (cache butuh plugin penyimpanan perangkat).
  static bool useCache = true;

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Tampilan cadangan bila gambar kosong atau gagal dimuat.
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder = fallback ??
        Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: Icon(
            Icons.image_not_supported_outlined,
            color: Colors.grey.shade400,
          ),
        );

    if (url.isEmpty) {
      return borderRadius == null
          ? placeholder
          : ClipRRect(borderRadius: borderRadius!, child: placeholder);
    }

    final loading = Container(
      width: width,
      height: height,
      color: Colors.grey.shade100,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );

    final Widget image = useCache
        ? CachedNetworkImage(
            imageUrl: url,
            cacheManager: kImageCache,
            width: width,
            height: height,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder: (context, _) => loading,
            errorWidget: (context, _, __) => placeholder,
          )
        : Image.network(
            url,
            width: width,
            height: height,
            fit: fit,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : loading,
            errorBuilder: (context, error, stackTrace) => placeholder,
          );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
