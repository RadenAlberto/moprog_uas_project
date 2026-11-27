import 'package:flutter/material.dart';

import '../DATA/video_data.dart';
import '../MODELS/video_model.dart';
import '../UTILS/app_theme.dart';
import '../WIDGETS/ui_kit.dart';
import '../WIDGETS/video_widgets.dart';

/// Galeri video UNIQLO dengan filter topik.
class VideoListPage extends StatefulWidget {
  const VideoListPage({super.key});

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  String? _topic;

  @override
  Widget build(BuildContext context) {
    final topics = <String>[];
    for (final video in kVideos) {
      if (!topics.contains(video.topic)) topics.add(video.topic);
    }
    final List<VideoItem> videos = _topic == null
        ? kVideos
        : kVideos.where((v) => v.topic == _topic).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('VIDEO UNIQLO')),
      body: SafeArea(
        child: Center(
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
                      for (final topic in topics) _chip(topic, topic),
                    ],
                  ),
                ),
                Expanded(
                  child: videos.isEmpty
                      ? const EmptyState(
                          icon: Icons.smart_display_outlined,
                          title: 'Belum ada video',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          itemCount: videos.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) => VideoCard(
                            video: videos[index],
                            width: double.infinity,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String? topic) {
    final selected = _topic == topic;
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
        onSelected: (_) => setState(() => _topic = topic),
      ),
    );
  }
}
