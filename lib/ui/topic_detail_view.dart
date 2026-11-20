import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'group_topics_view.dart';
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

  /// Loaded replies and the comments endpoint's total. They are
  /// seeded from the first page when the detail future resolves
  /// (see the identity check in build), and grow through the
  /// footer's load-more; a topic change re-seeds them.
  List<TopicComment> _comments = const [];
  int _total = 0;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  String _loadedId = '';

  @override
  void didUpdateWidget(covariant TopicDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId) {
      _future = widget.repository.fetchTopic(widget.topicId);
      _loadedId = '';
    }
  }

  Future<void> _loadMoreComments() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repository.fetchTopicComments(widget.topicId, start: _comments.length, count: 20);
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, ...page.comments];
        if (page.total > 0) _total = page.total;
        _loadMoreFailed = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Footer for the reply list: auto-loads the next page when it
  /// appears (LoadMoreFooter), shows the loaded/total count, and
  /// offers a retry after a failure instead of a SnackBar.
  Widget _commentsFooter() {
    return LoadMoreFooter(
      canLoadMore: () => !_loadingMore && _comments.length < _total,
      onLoadMore: _loadMoreComments,
      failed: _loadMoreFailed,
      countText: _total > 0 ? '已加载 ${_comments.length} / $_total' : null,
    );
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
        // Seed the reply state from the first page, once per
        // topic. Rebuilds from load-more must not re-seed (the
        // identity check), and a topic change re-seeds via the
        // new id (didUpdateWidget also clears _loadedId).
        if (_loadedId != detail.topic.id) {
          _loadedId = detail.topic.id;
          _comments = List.of(detail.comments);
          _total = detail.commentsTotal > 0 ? detail.commentsTotal : detail.topic.commentsCount;
          _loadingMore = false;
          _loadMoreFailed = false;
        }
        // The reply header shows the loaded count against the
        // comments endpoint's total; when the total is unknown
        // (0), it shows just the loaded count.
        final replyTitle = _total > 0
            ? '回复 (已加载 ${_comments.length} / $_total)'
            : '回复 (${_comments.length})';
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < Breakpoints.textMaxWidth) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _headerCard(context, detail),
                  const SizedBox(height: 16),
                  SelectableText(detail.content, style: const TextStyle(height: 1.6)),
                  _topicMedia(context, detail),
                  const Divider(height: 32),
                  Text(replyTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_comments.isEmpty) const EmptyState(message: '暂无回复'),
                  for (final c in _comments) _commentRow(c),
                  if (_comments.isNotEmpty || _total > 0) _commentsFooter(),
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
                        SelectableText(detail.content, style: const TextStyle(height: 1.6)),
                        _topicMedia(context, detail),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(replyTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (_comments.isEmpty) const EmptyState(message: '暂无回复'),
                        for (final c in _comments) _commentRow(c),
                        if (_comments.isNotEmpty || _total > 0) _commentsFooter(),
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
            Text(detail.topic.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: InkWell(
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
                child: Stack(
                  children: [
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: detail.videoCoverUrl == null
                          ? Container(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const Icon(Icons.play_circle_outlined, size: 48))
                          : CachedNetworkImage(
                              imageUrl: detail.videoCoverUrl!,
                              httpHeaders: doubanImageHeaders,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) => const Icon(Icons.play_circle_outlined, size: 48),
                            ),
                    ),
                    const Positioned.fill(
                      child: Center(
                        child: Icon(Icons.play_circle_filled, size: 56, color: Colors.white),
                      ),
                    ),
                    if (detail.videoDuration != null && detail.videoDuration!.isNotEmpty)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                          child: Text(detail.videoDuration!, style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (photoUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final cell = (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < photoUrls.length; i++)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ImagePreviewPage(urls: photoUrls, initialIndex: i)),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: photoUrls[i],
                          httpHeaders: doubanImageHeaders,
                          width: cell,
                          height: cell,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
                ],
              );
            },
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

  /// Flat reply row (no Card, no ListTile — its trailing would
  /// squeeze the body): avatar, author · time, body, and the like
  /// count at the bottom right.
  Widget _commentRow(TopicComment c) {
    final meta = [
      if (c.authorName.isNotEmpty) c.authorName,
      if (c.createTime.isNotEmpty) c.createTime,
    ].join(' · ');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _authorAvatar(c.authorAvatar),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (meta.isNotEmpty) Text(meta, style: Theme.of(context).textTheme.bodySmall),
                    if (meta.isNotEmpty) const SizedBox(height: 4),
                    SelectableText(c.text),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Spacer(),
                        const Icon(Icons.thumb_up_outlined, size: 14),
                        const SizedBox(width: 4),
                        Text('${c.voteCount}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
