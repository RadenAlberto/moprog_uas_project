import 'package:flutter/material.dart';

import '../DATA/video_data.dart';
import '../MODELS/video_model.dart';
import '../UTILS/app_theme.dart';
import '../UTILS/external_link.dart';
import 'ui_kit.dart';

/// Kartu video: thumbnail YouTube (jika ada ID) atau latar gradasi dengan
/// tombol putar. Ketuk untuk membuka detail dan tombol "Tonton di YouTube".
class VideoCard extends StatelessWidget {
  const VideoCard({super.key, required this.video, this.width = 250});

  final VideoItem video;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showVideoSheet(context, video),
      child: SizedBox(
        width: width,
        child: Container(
          decoration: cardDecoration(radius: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: VideoThumbnail(video: video, radius: 14, topOnly: true),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      video.topic,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thumbnail video dengan tombol putar.
class VideoThumbnail extends StatelessWidget {
  const VideoThumbnail({
    super.key,
    required this.video,
    this.radius = 12,
    this.topOnly = false,
  });

  final VideoItem video;
  final double radius;
  final bool topOnly;

  @override
  Widget build(BuildContext context) {
    final borderRadius = topOnly
        ? BorderRadius.vertical(top: Radius.circular(radius))
        : BorderRadius.circular(radius);

    final gradient = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: video.gradient,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -16,
            child: Icon(
              video.icon,
              size: 120,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: PillTag(
              label: video.topic.toUpperCase(),
              color: Colors.white.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video.hasThumbnail)
            Image.network(
              video.thumbnailUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => gradient,
            )
          else
            gradient,
          Container(color: Colors.black.withValues(alpha: 0.12)),
          Center(
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                boxShadow: AppShadows.lift,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.red,
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet detail video dengan tombol buka YouTube.
Future<void> showVideoSheet(BuildContext context, VideoItem video) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: VideoThumbnail(video: video, radius: 14),
              ),
              const SizedBox(height: 14),
              Text(
                video.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                video.subtitle,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    openExternalUrl(context, video.url);
                  },
                  icon: const Icon(Icons.smart_display_outlined),
                  label: const Text(
                    'TONTON DI YOUTUBE',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              if (!video.hasThumbnail)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Membuka hasil pencarian YouTube untuk topik ini.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Baris video horizontal untuk beranda.
class VideoStrip extends StatelessWidget {
  const VideoStrip({super.key, this.limit = 6});

  final int limit;

  @override
  Widget build(BuildContext context) {
    final videos = kVideos.take(limit).toList();
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: videos.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) => VideoCard(video: videos[index]),
      ),
    );
  }
}
