import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'breakpoints.dart';
import '../data/local_lists.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'group_topics_view.dart';
import 'image_preview_page.dart';
import 'video_preview_page.dart';
import 'widgets.dart';

class TopicDetailPage extends StatefulWidget {
  const TopicDetailPage({super.key, required this.repository, required this.topicId});

  final DoubanRepository repository;
  final String topicId;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  final _detail = ValueNotifier<TopicDetail?>(null);

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('话题详情'),
        actions: [
          ValueListenableBuilder<TopicDetail?>(
            valueListenable: _detail,
            builder: (context, detail, _) {
              if (detail == null) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListenableBuilder(
                    listenable: LocalLists.instance,
                    builder: (context, _) {
                      final favorited = LocalLists.instance.isFavoriteTopic(detail.topic.id);
                      return IconButton(
                        icon: Icon(favorited ? Icons.star : Icons.star_border),
                        tooltip: favorited ? '取消收藏' : '收藏话题',
                        onPressed: () => LocalLists.instance.toggleFavoriteTopic(
                          id: detail.topic.id,
                          title: detail.topic.title,
                        ),
                      );
                    },
                  ),
                  if (detail.sharingUrl.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        if (value == 'copy') {
                          await Clipboard.setData(ClipboardData(text: detail.sharingUrl));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('链接已复制')),
                            );
                          }
                        } else if (value == 'browser') {
                          await launchUrl(Uri.parse(detail.sharingUrl), mode: LaunchMode.externalApplication);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'copy', child: Text('复制链接')),
                        PopupMenuItem(value: 'browser', child: Text('浏览器打开')),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: TopicDetailView(
        repository: widget.repository,
        topicId: widget.topicId,
        onDetail: (d) => _detail.value = d,
      ),
    );
  }
}

/// Stateful so the topic future is created once in initState: as a
/// StatelessWidget it was created in build, and the ancestors that
/// rebuild this view on resize (the group tab's LayoutBuilder, and
/// main.dart's MediaQuery builder for a pushed page) re-fetched the
/// topic and flashed the spinner on every window drag.
class TopicDetailView extends StatefulWidget {
  const TopicDetailView({super.key, required this.repository, required this.topicId, this.onDetail});

  final DoubanRepository repository;
  final String topicId;

  /// Called once per loaded detail (not on rebuilds), so a host
  /// page can build AppBar actions (star, menu) from it.
  final ValueChanged<TopicDetail>? onDetail;

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

  /// Show only the topic author's replies.
  bool _onlyAuthor = false;

  @override
  void didUpdateWidget(covariant TopicDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId) {
      _future = widget.repository.fetchTopic(widget.topicId);
      _loadedId = '';
      _onlyAuthor = false;
    }
  }

  void _reload() {
    setState(() {
      _future = widget.repository.fetchTopic(widget.topicId);
      _loadedId = '';
    });
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

  /// Hot replies: the API's popular_comments when present (up to
  /// 3, floor unknown), else the three most-liked loaded replies
  /// (labelled "已加载中最赞"). Skipped when there are too few
  /// replies to pick from.
  List<(int?, TopicComment)> _hotReplies(TopicDetail detail) {
    if (detail.popularComments.isNotEmpty) {
      return detail.popularComments.take(3).map((c) => (null, c)).toList();
    }
    if (_comments.length < 6) return const [];
    final sorted = _comments.asMap().entries.toList()
      ..sort((a, b) => b.value.voteCount.compareTo(a.value.voteCount));
    return sorted
        .take(3)
        .where((e) => e.value.voteCount > 0)
        .map((e) => (e.key + 1, e.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TopicDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const TopicDetailSkeleton();
        }
        if (snapshot.hasError) {
          final e = snapshot.error;
          if (e is DioException && e.response?.statusCode == 404) {
            return const EmptyState(message: '这个话题已被删除或不存在');
          }
          if (e is DioException && e.response?.statusCode == 403) {
            return const EmptyState(message: '没有权限查看这个话题，可能需要登录');
          }
          return Center(child: RetryState(message: '加载失败', onRetry: _reload));
        }
        final detail = snapshot.data;
        if (detail == null) return const EmptyState(message: '暂无话题');
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
          // Notify the host page after this build finishes: setting
          // the ValueNotifier during build would mark the AppBar
          // dirty while the framework is building this subtree.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _loadedId == detail.topic.id) widget.onDetail?.call(detail);
          });
        }
        final blocks = parseContentBlocks(detail.contentHtml);
        final replyTitle = _total > 0 ? '回应 $_total' : '回应 ${_comments.length}';
        // Visible replies with their floor numbers (position in
        // the default order). The floor is the index in the full
        // loaded list, not in the filtered view.
        final visible = _comments
            .asMap()
            .entries
            .where((e) => !_onlyAuthor || (e.value.authorId.isNotEmpty && e.value.authorId == detail.topic.authorId))
            .map((e) => (e.key + 1, e.value))
            .toList();
        final hot = _hotReplies(detail);
        // Wide detail pane (>=900, measured on the pane itself,
        // not the window): body left (max 760, centred), replies
        // right (fixed 440, own scroll, pinned header). Narrow
        // panes — mobile, and the group tab's detail pane when the
        // window is too small to split — keep the single
        // top-to-bottom column.
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < Breakpoints.paneSplit) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _headerCard(context, detail),
                  const SizedBox(height: 16),
                  ..._bodyBlocks(context, detail, blocks),
                  _topicMedia(context, detail, blocks),
                  const Divider(height: 32),
                  _repliesHeader(context, detail, replyTitle),
                  const SizedBox(height: 8),
                  ..._replyChildren(context, detail, visible, hot),
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
                    child: CenteredWidth(
                      maxWidth: 760,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _headerCard(context, detail),
                          const SizedBox(height: 16),
                          ..._bodyBlocks(context, detail, blocks),
                          _topicMedia(context, detail, blocks),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: 440,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: _repliesHeader(context, detail, replyTitle),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: _replyChildren(context, detail, visible, hot),
                          ),
                        ),
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

  /// "回应 N" plus the 只看楼主 toggle. On desktop this row is
  /// pinned above the independently scrolling reply list; on
  /// mobile it sits at the top of the single column.
  Widget _repliesHeader(BuildContext context, TopicDetail detail, String title) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        if (detail.topic.authorId.isNotEmpty)
          FilterChip(
            label: const Text('只看楼主'),
            selected: _onlyAuthor,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onSelected: (v) => setState(() => _onlyAuthor = v),
          ),
      ],
    );
  }

  List<Widget> _replyChildren(
    BuildContext context,
    TopicDetail detail,
    List<(int, TopicComment)> visible,
    List<(int?, TopicComment)> hot,
  ) {
    return [
      // The hot section is the API's (or most-liked) replies, not
      // the author's, so it is hidden under 只看楼主.
      if (hot.isNotEmpty && !_onlyAuthor) ...[
        Text(
          detail.popularComments.isNotEmpty ? '热门回应' : '已加载中最赞',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        for (final (floor, c) in hot) _commentRow(context, c, floor, detail.topic.authorId),
        const Divider(height: 24),
      ],
      if (visible.isEmpty)
        EmptyState(message: _onlyAuthor ? '楼主在已加载的回应中暂无发言' : '暂无回复')
      else
        for (final (floor, c) in visible) _commentRow(context, c, floor, detail.topic.authorId),
      if (visible.isNotEmpty || _total > 0) _commentsFooter(),
    ];
  }

  Widget _headerCard(BuildContext context, TopicDetail detail) {
    final authorLine = [
      if (detail.topic.authorName.isNotEmpty) detail.topic.authorName,
      if (detail.ipLocation != null && detail.ipLocation!.isNotEmpty) 'IP属地：${detail.ipLocation}',
      if (detail.topic.createTime.isNotEmpty) detail.topic.createTime,
    ].join(' · ');
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
                Expanded(child: Text(authorLine)),
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

  /// The body as paragraph/image blocks in original order, with
  /// links tappable. Falls back to the plain text when the HTML
  /// is empty (or unparseable).
  List<Widget> _bodyBlocks(BuildContext context, TopicDetail detail, List<ContentBlock> blocks) {
    if (blocks.isEmpty) {
      return [
        SelectableText(detail.content, style: const TextStyle(height: 1.6)),
        const SizedBox(height: 8),
      ];
    }
    final imageUrls = blocks.where((b) => b.isImage).map((b) => b.imageUrl!).toList();
    return [
      for (final block in blocks)
        if (block.isImage)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _bodyImage(context, block.imageUrl!, imageUrls),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(height: 1.6),
                children: [
                  for (final run in block.runs)
                    run.link == null
                        ? TextSpan(text: run.text)
                        : TextSpan(
                            text: run.text,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => launchUrl(Uri.parse(run.link!), mode: LaunchMode.externalApplication),
                          ),
                ],
              ),
            ),
          ),
    ];
  }

  Widget _bodyImage(BuildContext context, String url, List<String> allUrls) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ImagePreviewPage(urls: allUrls, initialIndex: allUrls.indexOf(url))),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: doubanImageHeaders,
            width: double.infinity,
            fit: BoxFit.contain,
            errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
          ),
        ),
      ),
    );
  }

  /// Attached video, plus any photos from the structured array
  /// that did not already appear as body blocks. The photos array
  /// and the content's <img> URLs are the same images (verified
  /// 2026-10-31), so the array is only a fallback here; the video
  /// entry only appears when the topic carries a video
  /// (video_info was null in every topic probed 2026-10-31).
  Widget _topicMedia(BuildContext context, TopicDetail detail, List<ContentBlock> blocks) {
    final shown = blocks.where((b) => b.isImage).map((b) => b.imageUrl!).toSet();
    final photoUrls = detail.photos.map((p) => p.url).whereType<String>().where((u) => !shown.contains(u)).toList();
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
  /// squeeze the body): avatar, nickname with a 楼主 badge and
  /// floor number, "时间 · IP属地" line, an indented quote block
  /// when the reply answers another comment, body, and the like
  /// count at the bottom right.
  Widget _commentRow(BuildContext context, TopicComment c, int? floor, String topicAuthorId) {
    final meta = [
      if (c.createTime.isNotEmpty) c.createTime,
      if (c.ipLocation != null && c.ipLocation!.isNotEmpty) 'IP属地：${c.ipLocation}',
    ].join(' · ');
    final isAuthor = c.authorId.isNotEmpty && c.authorId == topicAuthorId;
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
                    Row(
                      children: [
                        Flexible(child: Text(c.authorName, style: const TextStyle(fontWeight: FontWeight.w600))),
                        if (isAuthor) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('楼主', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                          ),
                        ],
                        if (floor != null) ...[
                          const Spacer(),
                          Text('$floor楼', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ],
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta, style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (c.refComment != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${c.refComment!.authorName}：${c.refComment!.text}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
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
