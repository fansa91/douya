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
  const TopicDetailPage({super.key, required this.repository, required this.topicId, this.initialTopic});

  final DoubanRepository repository;
  final String topicId;

  /// The topic as the caller already knows it (feed card, group
  /// list): title, author, cover. The header renders from it
  /// while the detail loads, instead of a bare skeleton.
  final GroupTopic? initialTopic;

  @override
  State<TopicDetailPage> createState() => _TopicDetailPageState();
}

class _TopicDetailPageState extends State<TopicDetailPage> {
  final _detail = ValueNotifier<TopicDetail?>(null);

  /// True once the body has scrolled past the header: the AppBar
  /// then shows the topic title instead of the fixed '话题详情'.
  bool _showTitle = false;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder<TopicDetail?>(
          valueListenable: _detail,
          builder: (context, detail, _) {
            final title = detail?.topic.title ?? widget.initialTopic?.title;
            if (_showTitle && title != null && title.isNotEmpty) {
              return Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
            }
            return const Text('话题详情');
          },
        ),
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
      body: NotificationListener<ScrollNotification>(
        // 120px past the top the header title has scrolled away,
        // so the AppBar takes over showing it. Only setState when
        // the flag actually flips.
        onNotification: (n) {
          final show = n.metrics.pixels > 120;
          if (show != _showTitle) setState(() => _showTitle = show);
          return false;
        },
        child: TopicDetailView(
          repository: widget.repository,
          topicId: widget.topicId,
          initialTopic: widget.initialTopic,
          onDetail: (d) => _detail.value = d,
        ),
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
  const TopicDetailView({super.key, required this.repository, required this.topicId, this.onDetail, this.initialTopic});

  final DoubanRepository repository;
  final String topicId;

  /// Called once per loaded detail (not on rebuilds), so a host
  /// page can build AppBar actions (star, menu) from it.
  final ValueChanged<TopicDetail>? onDetail;

  /// The topic as the caller already knows it (feed card, group
  /// list). The header renders from it while the detail loads.
  final GroupTopic? initialTopic;

  @override
  State<TopicDetailView> createState() => _TopicDetailViewState();
}

class _TopicDetailViewState extends State<TopicDetailView> with SingleTickerProviderStateMixin {
  late Future<TopicDetail> _future = widget.repository.fetchTopic(widget.topicId);
  late final TabController _tabController = TabController(length: 2, vsync: this);

  /// Mobile scroll controller, for the floating 跳到回应 / 回到顶部
  /// button. Desktop keeps its own scroll views (left list + right
  /// comments column) and shows no jump button.
  final _scrollController = ScrollController();

  /// The mobile tab row, so 跳到回应 can scroll it into view.
  final _tabRowKey = GlobalKey();

  /// Floating jump button (mobile, long posts only). _atTop picks
  /// the label: near the top it jumps to the replies, once scrolled
  /// down it goes back to the top.
  bool _showJump = false;
  bool _atTop = true;

  /// Reply tab: 0 最新， 1 热门. The TabBar switches it; there is
  /// no TabBarView because both tabs render into the same list.
  int _tab = 0;

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
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Long post: the content is taller than the viewport by a
    // margin. The label flips once the user has left the top.
    final isLong = pos.maxScrollExtent > 300;
    final atTop = pos.pixels < 200;
    if (isLong != _showJump || atTop != _atTop) {
      setState(() {
        _showJump = isLong;
        _atTop = atTop;
      });
    }
  }

  void _jumpToReplies() {
    final context = _tabRowKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void didUpdateWidget(covariant TopicDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.topicId != widget.topicId) {
      _future = widget.repository.fetchTopic(widget.topicId);
      _loadedId = '';
      _onlyAuthor = false;
      _tab = 0;
      _tabController.index = 0;
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
  /// offers a retry after a failure instead of a SnackBar. The key
  /// keeps the footer's state (its auto-page counter) when the list
  /// grows: without it the footer remounts on every page load and
  /// its desktop "pause after 3 auto pages" never engages.
  Widget _commentsFooter() {
    return LoadMoreFooter(
      key: const ValueKey('topic-comments-footer'),
      canLoadMore: () => !_loadingMore && _comments.length < _total,
      onLoadMore: _loadMoreComments,
      failed: _loadMoreFailed,
      countText: _total > 0 ? '已加载 ${_comments.length} / $_total' : null,
    );
  }

  /// Hot replies for the 热门 tab: the API's popular_comments when
  /// present (up to 10, floor unknown), else the ten most-liked
  /// loaded replies (labelled "已加载中最赞" by the caller). The
  /// server offers no hot sort — the comments endpoint was
  /// 403-gated across the board when probed 2026-11-21, so a sort
  /// parameter could not be verified — so the fallback ranks what
  /// the 最新 tab has already loaded. Respects 只看楼主.
  /// Floors are positions in the latest order, so the hot tab
  /// shows none (null): these rows are ranked by votes, not time.
  List<(int?, TopicComment)> _hotReplies(TopicDetail detail) {
    bool isAuthor(TopicComment c) => c.authorId.isNotEmpty && c.authorId == detail.topic.authorId;
    if (detail.popularComments.isNotEmpty) {
      final popular = _onlyAuthor ? detail.popularComments.where(isAuthor).toList() : detail.popularComments;
      return popular.take(10).map((c) => (null, c)).toList();
    }
    final pool = _onlyAuthor ? _comments.where(isAuthor).toList() : _comments;
    final sorted = pool.toList()..sort((a, b) => b.voteCount.compareTo(a.voteCount));
    return sorted.take(10).where((c) => c.voteCount > 0).map((c) => (null, c)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TopicDetail>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          final initial = widget.initialTopic;
          if (initial == null) return const TopicDetailSkeleton();
          // The caller already knows the title and author: show
          // the header from them at once, with skeleton bars for
          // the body that is still loading.
          final authorLine = [
            if (initial.authorName.isNotEmpty) initial.authorName,
            if (initial.createTime.isNotEmpty) initial.createTime,
          ].join(' · ');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(initial.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _authorAvatar(initial.authorAvatar),
                          const SizedBox(width: 8),
                          Expanded(child: Text(authorLine)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const SkeletonBar(),
              const SizedBox(height: 8),
              const SkeletonBar(),
              const SizedBox(height: 8),
              const SkeletonBar(width: 220),
            ],
          );
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
          // The content is laid out after this frame: re-check
          // whether the post is long enough for the jump button.
          WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
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
        // Wide detail pane (>=900, measured on the pane itself,
        // not the window): body left (max 760, centred), replies
        // right (fixed 440, own scroll, pinned header). Narrow
        // panes — mobile, and the group tab's detail pane when the
        // window is too small to split — keep the single
        // top-to-bottom column, with the tab row pinned once the
        // body has scrolled away.
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < Breakpoints.paneSplit) {
              return Stack(
                children: [
                  CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _header(context, detail),
                              const SizedBox(height: 16),
                              ..._bodyBlocks(context, detail, blocks),
                              _topicMedia(context, detail, blocks),
                            ],
                          ),
                        ),
                      ),
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: PinnedTabBarDelegate(
                          _tabBarRow(detail, replyTitle, rowKey: _tabRowKey),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverMainAxisGroup(
                          slivers: _tabContentSlivers(context, detail, visible),
                        ),
                      ),
                    ],
                  ),
                  if (_showJump)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton.extended(
                        onPressed: _atTop ? _jumpToReplies : _scrollToTop,
                        icon: Icon(_atTop ? Icons.arrow_downward : Icons.arrow_upward),
                        label: Text(_atTop ? '跳到回应' : '回到顶部'),
                      ),
                    ),
                ],
              );
            }
            // The split itself is capped at 1440 so neither column
            // stretches across an ultrawide window. The right
            // column is ~34% of the split width, clamped to
            // 360–460: at 900 wide that is 360 (not 440), so the
            // left column keeps ~540 for the body. The split
            // threshold stays 900 (paneSplit is shared with the
            // subject page, so it is not raised here).
            final rowWidth = constraints.maxWidth.clamp(0.0, Breakpoints.gridMaxWidth);
            final rightWidth = (rowWidth * 0.34).clamp(360.0, 460.0);
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
                          _header(context, detail),
                          const SizedBox(height: 16),
                          ..._bodyBlocks(context, detail, blocks),
                          _topicMedia(context, detail, blocks),
                        ],
                      ),
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: rightWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: _tabBarRow(detail, replyTitle),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: CustomScrollView(
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.all(16),
                                sliver: SliverMainAxisGroup(
                                  slivers: _tabContentSlivers(context, detail, visible),
                                ),
                              ),
                            ],
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

  /// The sticky tab row: the reply count, 最新 / 热门, plus the
  /// 只看楼主 toggle, which applies to both tabs. The count used to
  /// be its own line above this row; merging it in saves a row of
  /// height. On mobile this row is pinned by a SliverPersistent-
  /// Header; on desktop it sits in the pinned header of the right
  /// column. [rowKey] is the mobile row only, so 跳到回应 can
  /// scroll it into view.
  Widget _tabBarRow(TopicDetail detail, String replyTitle, {Key? rowKey}) {
    return Row(
      key: rowKey,
      children: [
        Text(replyTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: TabBar(
            controller: _tabController,
            onTap: (i) => setState(() => _tab = i),
            tabs: const [Tab(text: '最新'), Tab(text: '热门')],
          ),
        ),
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

  /// The reply list under the active tab, as slivers. 最新 is the
  /// paged list (floors in default order) with the load-more
  /// footer; 热门 is the API's popular replies, or the most-liked
  /// loaded ones when the API sent none (labelled, and noted as
  /// loaded-only when more replies remain unloaded). Rows are a
  /// lazy SliverList so the footer only mounts when scrolled near
  /// — an eager Column would mount it at once and cascade-load the
  /// whole thread on open.
  List<Widget> _tabContentSlivers(
    BuildContext context,
    TopicDetail detail,
    List<(int, TopicComment)> visible,
  ) {
    if (_tab == 1) {
      final hot = _hotReplies(detail);
      final fromApi = detail.popularComments.isNotEmpty;
      if (hot.isEmpty) {
        return [SliverToBoxAdapter(child: EmptyState(message: _onlyAuthor ? '楼主在已加载的回应中暂无发言' : '暂无热门回应'))];
      }
      return [
        if (!fromApi)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('已加载中最赞', style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        SliverList.builder(
          itemCount: hot.length,
          itemBuilder: (context, i) => _commentRow(context, hot[i].$2, null, detail.topic.authorId),
        ),
        if (!fromApi && _comments.length < _total)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '仅按已加载的 ${_comments.length} 条回应排序，切换到最新加载更多后更新',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
      ];
    }
    return [
      if (visible.isEmpty)
        SliverToBoxAdapter(child: EmptyState(message: _onlyAuthor ? '楼主在已加载的回应中暂无发言' : '暂无回复'))
      else
        SliverList.builder(
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final (floor, c) = visible[i];
            return _commentRow(context, c, floor, detail.topic.authorId);
          },
        ),
      if (visible.isNotEmpty || _total > 0) SliverToBoxAdapter(child: _commentsFooter()),
    ];
  }

  /// Flat header, no Card: the title, then the author row split
  /// into two lines (name, then "时间 · IP属地"), then the source
  /// group as a tappable capsule. The old single-line "name ·
  /// IP属地 · time" string wrapped irregularly on narrow screens,
  /// and the group row was a 16px icon line.
  Widget _header(BuildContext context, TopicDetail detail) {
    final topic = detail.topic;
    final meta = [
      if (topic.createTime.isNotEmpty) topic.createTime,
      if (detail.ipLocation != null && detail.ipLocation!.isNotEmpty) 'IP属地：${detail.ipLocation}',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(topic.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            _authorAvatar(topic.authorAvatar),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.authorName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(meta, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (detail.groupName.isNotEmpty) ...[
          const SizedBox(height: 12),
          _groupCapsule(context, detail),
        ],
      ],
    );
  }

  /// Source group as a tappable pill, at least 40dp tall so the
  /// touch target is big enough. No group id means no page to open,
  /// so the capsule is shown without a tap handler.
  Widget _groupCapsule(BuildContext context, TopicDetail detail) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.group_outlined, size: 16),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            detail.groupName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (detail.groupId.isNotEmpty) const Icon(Icons.chevron_right, size: 16),
      ],
    );
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: content,
    );
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: detail.groupId.isEmpty
          ? pill
          : InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupTopicsPage(repository: widget.repository, groupId: detail.groupId),
                  ),
                );
              },
              child: pill,
            ),
    );
  }

  /// The body as paragraph/image blocks in original order, with
  /// links tappable. Falls back to the plain text when the HTML
  /// is empty (or unparseable).
  List<Widget> _bodyBlocks(BuildContext context, TopicDetail detail, List<ContentBlock> blocks) {
    if (blocks.isEmpty) {
      return [
        SelectableText(detail.content, style: const TextStyle(fontSize: 15, height: 1.6)),
        const SizedBox(height: 8),
      ];
    }
    final imageUrls = blocks.where((b) => b.isImage).map((b) => b.imageUrl!).toList();
    return [
      for (final block in blocks)
        if (block.isImage)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _bodyImage(context, block.imageUrl!, imageUrls, detail),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText.rich(
              TextSpan(
                style: const TextStyle(fontSize: 15, height: 1.6),
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

  /// Body image: full width at its natural aspect ratio, from the
  /// structured photo's pixel size (the photos array and the
  /// content's <img> URLs are the same images). The aspect ratio
  /// reserves the height before the image loads, so the body does
  /// not jump; the image fades in. A very tall image (height over
  /// ~2.5x the width) is capped at 420 tall with a 点击查看全图 hint
  /// instead of dominating the page. Decoded at the display size.
  /// Falls back to 4:3 (the feed card's fallback) when the photo
  /// cannot be matched.
  Widget _bodyImage(BuildContext context, String url, List<String> allUrls, TopicDetail detail) {
    final photo = _photoForUrl(detail, url);
    final aspect = (photo?.width != null && photo?.height != null && photo!.width! > 0 && photo.height! > 0)
        ? photo.width! / photo.height!
        : 4 / 3;
    final isTall = aspect < 0.4;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ImagePreviewPage(urls: allUrls, initialIndex: allUrls.indexOf(url))),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cacheWidth =
                (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round();
            final image = CachedNetworkImage(
              imageUrl: url,
              httpHeaders: doubanImageHeaders,
              memCacheWidth: cacheWidth,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 200),
              placeholder: (context, url) => Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
            );
            if (isTall) {
              return Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 420,
                    child: image,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '点击查看全图',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              );
            }
            return AspectRatio(aspectRatio: aspect, child: image);
          },
        ),
      ),
    );
  }

  /// Match a body <img> URL to its structured photo, for the pixel
  /// size. Exact match on any URL variant first, then the photo id
  /// embedded in the filename (p<id>.jpg).
  Photo? _photoForUrl(TopicDetail detail, String url) {
    for (final p in detail.photos) {
      if (p.url == url || p.urlLarge == url || p.urlSmall == url) return p;
    }
    final m = RegExp(r'/p(\d+)\.').firstMatch(url);
    if (m != null) {
      final id = m.group(1);
      for (final p in detail.photos) {
        if (p.id == id) return p;
      }
    }
    return null;
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
