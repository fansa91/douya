import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'group_page.dart';
import 'image_preview_page.dart';
import 'video_preview_page.dart';
import 'widgets.dart';

class TopicDetailPage extends StatelessWidget {
  const TopicDetailPage({super.key, required this.repository, required this.topicId});

  final DoubanRepository repository;
  final String topicId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('话题详情')),
      body: TopicDetailView(repository: repository, topicId: topicId),
    );
  }
}

/// Stateful so the topic future is created once in initState: as a
/// StatelessWidget it was created in build, and the ancestors that
/// rebuild this view on resize (the group tab's LayoutBuilder, and
/// main.dart's MediaQuery builder for a pushed page) re-fetched the
/// topic and flashed the spinner on every window drag.
class TopicDetailView extends StatefulWidget {
  const TopicDetailView({super.key, required this.repository, required this.topicId});

  final DoubanRepository repository;
  final String topicId;

  @override
  State<TopicDetailView> createState() => _TopicDetailViewState();
}

class _TopicDetailViewState extends State<TopicDetailView> {
  late Future<TopicDetail> _future = widget.repository.fetchTopic(widget.topicId);

  @override
  void didUpdateWidget(covariant TopicDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId) {
      _future = widget.repository.fetchTopic(widget.topicId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TopicDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingList();
        }
        if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
        final detail = snapshot.data;
        if (detail == null) return const EmptyState(message: '暂无话题');
        // Wide detail pane (>=720, measured on the pane itself, not
        // the window): content left, replies right, each scrolling
        // on its own. Narrow panes — mobile, and the group tab's
        // detail pane when the window is too small to split — keep
        // the single top-to-bottom column.
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < Breakpoints.textMaxWidth) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _headerCard(context, detail),
                  const SizedBox(height: 16),
                  SelectableText(detail.content),
                  _topicMedia(context, detail),
                  const Divider(height: 32),
                  Text('回复 (${detail.comments.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (detail.comments.isEmpty) const EmptyState(message: '暂无回复'),
                  for (final c in detail.comments) _commentCard(c),
                ],
              );
            }
            // The split itself is capped at 1440 so neither column
            // stretches across an ultrawide window.
            return CenteredWidth(
              maxWidth: Breakpoints.gridMaxWidth,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _headerCard(context, detail),
                        const SizedBox(height: 16),
                        SelectableText(detail.content),
                        _topicMedia(context, detail),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('回复 (${detail.comments.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (detail.comments.isEmpty) const EmptyState(message: '暂无回复'),
                        for (final c in detail.comments) _commentCard(c),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _headerCard(BuildContext context, TopicDetail detail) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail.topic.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                _authorAvatar(detail.topic.authorAvatar),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${detail.topic.authorName} · ${detail.topic.createTime} · 回应 ${detail.topic.commentsCount}'),
                ),
              ],
            ),
            if (detail.groupName.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: detail.groupId.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GroupTopicsPage(repository: widget.repository, groupId: detail.groupId),
                          ),
                        );
                      },
                child: Row(
                  children: [
                    const Icon(Icons.group_outlined, size: 16),
                    const SizedBox(width: 4),
                    Expanded(child: Text(detail.groupName)),
                    if (detail.groupId.isNotEmpty) const Icon(Icons.chevron_right, size: 16),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Attached pictures and video, shown below the body text. The
  /// photos array and the content's <img> URLs are the same images
  /// (verified 2026-10-31); fetchTopic already prefers the array.
  /// The video entry only appears when the topic carries a video
  /// (video_info was null in every topic probed 2026-10-31).
  Widget _topicMedia(BuildContext context, TopicDetail detail) {
    final photoUrls = detail.photos.map((p) => p.url).whereType<String>().toList();
    final hasVideo = detail.videoUrl != null && detail.videoUrl!.isNotEmpty;
    if (!hasVideo && photoUrls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasVideo)
          ListTile(
            leading: detail.videoCoverUrl == null
                ? const Icon(Icons.play_circle_outlined)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: detail.videoCoverUrl!,
                      httpHeaders: doubanImageHeaders,
                      width: 72,
                      height: 48,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const Icon(Icons.play_circle_outlined),
                    ),
                  ),
            title: const Text('视频'),
            subtitle: detail.videoDuration != null && detail.videoDuration!.isNotEmpty ? Text(detail.videoDuration!) : null,
            trailing: const Icon(Icons.play_arrow),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoPreviewPage(
                    trailers: [
                      Trailer(
                        id: '',
                        title: detail.topic.title,
                        videoUrl: detail.videoUrl,
                        coverUrl: detail.videoCoverUrl,
                        runtime: detail.videoDuration ?? '',
                      ),
                    ],
                    initialIndex: 0,
                  ),
                ),
              );
            },
          ),
        if (photoUrls.isNotEmpty) ...[
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: photoUrls.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ImagePreviewPage(urls: photoUrls, initialIndex: i)),
                );
              },
              child: CachedNetworkImage(
                imageUrl: photoUrls[i],
                httpHeaders: doubanImageHeaders,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Avatar with the same fallback as the feed cards: a real
  /// avatar URL when the payload carries one, a person icon when
  /// it does not (the topic/comment payloads do not always).
  Widget _authorAvatar(String? url) {
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: 16, backgroundImage: doubanImageProvider(url));
    }
    return const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16));
  }

  Widget _commentCard(TopicComment c) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: _authorAvatar(c.authorAvatar),
        title: Text(c.authorName),
        subtitle: SelectableText(c.text),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.thumb_up_outlined, size: 16),
            const SizedBox(width: 4),
            Text('${c.voteCount}'),
          ],
        ),
      ),
    );
  }
}
