import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:url_launcher/url_launcher.dart';

import 'breakpoints.dart';
import '../data/local_lists.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'topic_detail_view.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Discover page: the real home recommend feed only. The
/// guest-assembled recommendation sections that used to sit below
/// the feed now live in Browse under the 推荐 category.
///
/// The feed is Frodo /elendil/recommend_feed with for_mobile=1
/// (without that param the guest call returns 200 but 0 items;
/// verified 2026-10-31). It carries no total, and `start` is
/// ignored: every request returns a fresh rotated batch (verified
/// 2026-11-21: five batches, zero id overlap), so paging repeats
/// start=0 and drops ids already seen instead of offsetting.
/// Feed cards are topic/review posts, NOT subject posters: they
/// render as text cards, topic taps open the topic detail, review
/// taps open the review detail, and any other type falls back to
/// the share link in a browser.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.repository, this.refreshListenable});

  final DoubanRepository repository;

  /// Ticked by the desktop top-bar refresh button; the feed listens
  /// and re-fetches the first page. Null on mobile (pull-to-refresh
  /// only) and in any caller that does not offer a refresh button.
  final ValueNotifier<int>? refreshListenable;

  @override
  Widget build(BuildContext context) {
    // Mobile (<600): single reading column, centered at 720.
    // Desktop (>=600, the shell's rail breakpoint): waterfall
    // (masonry) feed, c001apk's adaptive_card_list pattern — column
    // count from a fixed card width, shortest-column placement.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (Breakpoints.of(constraints.maxWidth) == WindowSize.compact) {
          return CenteredWidth(
            child: _FeedList(repository: repository, refreshListenable: refreshListenable),
          );
        }
        return _FeedList(repository: repository, masonry: true, refreshListenable: refreshListenable);
      },
    );
  }
}

/// Paged recommend-feed list. Mobile builds a Column (not its own
/// scroll view) because it lives inside the Discover ListView;
/// desktop builds its own CustomScrollView with a masonry sliver.
class _FeedList extends StatefulWidget {
  const _FeedList({required this.repository, this.masonry = false, this.refreshListenable});

  final DoubanRepository repository;
  final bool masonry;
  final ValueNotifier<int>? refreshListenable;

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  List<FeedItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _loadFailed = false;
  bool _loadMoreFailed = false;

  /// Ids seen in this session. The feed rotates, so a repeated
  /// request can return items already on screen; they are dropped.
  final _seenIds = <String>{};

  /// Type filter: all / topic (讨论) / review (长评). It filters
  /// only the loaded items, and fetches more when too few match.
  String _filter = 'all';
  int _filterAutoLoads = 0;

  /// "有 N 条新内容" banner after a refresh whose list is mostly
  /// new. 0 hides it.
  int _newBannerCount = 0;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.refreshListenable?.addListener(_onRefreshTick);
    _loadInitial();
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_onRefreshTick);
    _scrollController.dispose();
    super.dispose();
  }

  void _onRefreshTick() => _refresh();

  /// Re-fetch the first page and replace the list (the recommend
  /// feed rotates per request, verified 2026-10-31, so a refresh
  /// does bring new items). Triggered by pull-to-refresh and by
  /// the desktop top-bar refresh button; tapping the Discover
  /// destination is deliberately not a refresh (2026-10-31).
  /// Unlike the initial load it keeps the current items on
  /// screen; a failure with items shown only toasts, and with
  /// an empty list it restores the error view.
  Future<void> _refresh() async {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    try {
      final oldIds = _items.map((it) => it.id).toSet();
      final result = await widget.repository.fetchRecommendFeed(start: 0, count: 20);
      if (!mounted) return;
      final newInList = result.items.where((it) => !oldIds.contains(it.id)).toList();
      setState(() {
        _items = result.items;
        for (final it in result.items) {
          _seenIds.add(it.id);
        }
        _hasMore = result.items.isNotEmpty;
        _loadFailed = false;
        _loadMoreFailed = false;
        // Most of the refreshed list is new: flag it at the top.
        _newBannerCount = result.items.isNotEmpty && newInList.length > result.items.length / 2
            ? newInList.length
            : 0;
      });
    } catch (e) {
      debugPrint('$e');
      if (!mounted) return;
      if (_items.isEmpty) {
        setState(() => _loadFailed = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('刷新失败，请稍后重试')));
      }
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final result = await widget.repository.fetchRecommendFeed(start: 0, count: 20);
      if (mounted) {
        setState(() {
          _items = result.items;
          for (final it in result.items) {
            _seenIds.add(it.id);
          }
          _hasMore = result.items.isNotEmpty;
        });
      }
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    var added = 0;
    try {
      // The feed ignores `start` and rotates (verified
      // 2026-11-21), so paging repeats start=0 and drops ids
      // already seen. A batch that is entirely seen is retried a
      // few times before the list is declared done.
      for (var attempt = 0; attempt < 3 && added == 0; attempt++) {
        final result = await widget.repository.fetchRecommendFeed(start: 0, count: 20);
        final fresh = result.items.where((it) => !_seenIds.contains(it.id)).toList();
        if (fresh.isEmpty) continue;
        if (!mounted) return;
        setState(() {
          _items = [..._items, ...fresh];
          for (final it in fresh) {
            _seenIds.add(it.id);
          }
          _loadMoreFailed = false;
        });
        added = fresh.length;
      }
      if (added == 0 && mounted) setState(() => _hasMore = false);
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  List<FeedItem> _visibleItems() {
    if (_filter == 'all') return _items;
    return _items.where((it) => it.type == _filter).toList();
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _filterAutoLoads = 0;
    });
    _ensureFilterCoverage();
  }

  /// When the filter leaves too few items on screen, fetch more
  /// pages until there are enough (or the feed runs dry).
  Future<void> _ensureFilterCoverage() async {
    final filter = _filter;
    while (mounted && _filter == filter && _visibleItems().length < 5 && _hasMore && _filterAutoLoads < 3) {
      _filterAutoLoads++;
      await _loadMore();
    }
  }

  void _openItem(FeedItem item) {
    // Opening a card marks it read (its title turns muted).
    unawaited(LocalLists.instance.markFeedRead(item.id));
    if (item.type == 'topic') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TopicDetailPage(
            repository: widget.repository,
            topicId: item.id,
            // The card already knows the title, author, and cover:
            // the detail header renders from them at once.
            initialTopic: GroupTopic(
              id: item.id,
              title: item.title,
              authorName: item.authorName,
              authorAvatar: item.authorAvatar,
              commentsCount: item.commentsCount,
              createTime: item.createdTime,
              coverUrl: item.photoUrls.isNotEmpty ? item.photoUrls.first : null,
            ),
          ),
        ),
      );
    } else if (item.type == 'review') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewDetailPage(
            repository: widget.repository,
            reviewId: item.id,
            initialItem: item,
          ),
        ),
      );
    } else if (item.sharingUrl.isNotEmpty) {
      launchUrl(Uri.parse(item.sharingUrl), mode: LaunchMode.externalApplication);
    }
  }

  Widget _footer() {
    return LoadMoreFooter(
      canLoadMore: () => !_loadingMore && _hasMore,
      onLoadMore: _loadMore,
      failed: _loadMoreFailed,
    );
  }

  /// Title, "有新内容" banner, and the 全部 / 讨论 / 长评 filter.
  /// Shared by the mobile header item and the desktop sliver.
  Widget _headerContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_newBannerCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => setState(() => _newBannerCount = 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text('有 $_newBannerCount 条新内容')),
                    const Icon(Icons.close, size: 16),
                  ],
                ),
              ),
            ),
          ),
        const Text('推荐动态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('全部')),
            ButtonSegment(value: 'topic', label: Text('讨论')),
            ButtonSegment(value: 'review', label: Text('长评')),
          ],
          selected: {_filter},
          onSelectionChanged: (s) => _setFilter(s.first),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // The read state lives in LocalLists; rebuild the list when
    // a card is marked read (its title turns muted).
    return ListenableBuilder(
      listenable: LocalLists.instance,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      const skeleton = FeedSkeleton();
      // The skeleton is taller than one phone screen; it must
      // scroll instead of overflowing the Scaffold body.
      if (!widget.masonry) return const SingleChildScrollView(child: skeleton);
      return const CustomScrollView(
        slivers: [SliverToBoxAdapter(child: skeleton)],
      );
    }
    if (_loadFailed && _items.isEmpty) {
      final errorView = RetryState(message: '推荐动态加载失败', onRetry: _loadInitial);
      if (!widget.masonry) return errorView;
      return CustomScrollView(
        slivers: [SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(32), child: errorView))],
      );
    }
    if (_items.isEmpty) {
      const empty = Text('暂无推荐动态');
      if (!widget.masonry) return empty;
      return const CustomScrollView(
        slivers: [SliverToBoxAdapter(child: empty)],
      );
    }
    final visible = _visibleItems();
    if (!widget.masonry) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: visible.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return _headerContent();
            if (i <= visible.length) {
              final item = visible[i - 1];
              return _FeedCard(item: item, onTap: () => _openItem(item), flat: true);
            }
            return _footer();
          },
        ),
      );
    }
    // Desktop masonry: column count from c001apk's formula
    // (card width ~360 + 12 spacing, 1-4 columns). The LayoutBuilder
    // width here is already minus the navigation rail.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth - 32 + 12) / 372).floor().clamp(1, 4);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _headerContent(),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childCount: visible.length,
                  itemBuilder: (context, i) => _FeedCard(
                    item: visible[i],
                    onTap: () => _openItem(visible[i]),
                    margin: EdgeInsets.zero,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Center(child: _footer()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item, required this.onTap, this.margin = const EdgeInsets.only(bottom: 12), this.flat = false});

  final FeedItem item;
  final VoidCallback onTap;

  /// Mobile list spacing; masonry passes zero because the grid's
  /// mainAxisSpacing already separates rows.
  final EdgeInsetsGeometry margin;

  /// Mobile: flat rows with a divider instead of a Card.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    // Desktop right-click menu (copy link / open in browser). No
    // menu when no URL can be determined for this card.
    final url = feedItemWebUrl(item);
    final read = LocalLists.instance.isFeedRead(item.id);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (item.authorAvatar != null && item.authorAvatar!.isNotEmpty)
              CircleAvatar(
                radius: 16,
                backgroundImage: doubanImageProvider(item.authorAvatar!),
              )
            else
              const CircleAvatar(radius: 16, child: Icon(Icons.person, size: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.authorName.isNotEmpty ? item.authorName : '豆瓣用户',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (item.createdTime.isNotEmpty)
              Text(item.createdTime, style: Theme.of(context).textTheme.bodySmall),
            if (item.typeCn.isNotEmpty) ...[
              const SizedBox(width: 8),
              Chip(label: Text(item.typeCn), visualDensity: VisualDensity.compact),
            ],
          ],
        ),
        if (item.title.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            item.title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: read ? Theme.of(context).colorScheme.onSurfaceVariant : null,
            ),
          ),
        ],
        if (item.abstract.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(item.abstract, maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
        if (item.photos.isNotEmpty) ...[
          const SizedBox(height: 8),
          _photoRow(item),
        ],
        if (_hasCounts(item)) ...[
          const SizedBox(height: 8),
          _countRow(context, item),
        ],
      ],
    );
    final Widget body;
    if (flat) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [content, const Divider(height: 24)],
        ),
      );
    } else {
      body = Card(
        margin: margin,
        child: InkWell(
          onTap: onTap,
          hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: content,
          ),
        ),
      );
    }
    final Widget tappable = flat ? InkWell(onTap: onTap, child: body) : body;
    if (url == null) return tappable;
    return GestureDetector(
      onSecondaryTapUp: (details) => showLinkMenu(context, details.globalPosition, url),
      child: tappable,
    );
  }

  /// Up to three thumbnails, each at its photo's own aspect ratio
  /// (4:3 when the payload carries no size). The row is capped so
  /// a very tall photo does not dominate the card.
  Widget _photoRow(FeedItem item) {
    final photos = item.photos.take(3).toList();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 240),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < photos.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: _photoAspect(photos[i]),
                  child: CachedNetworkImage(
                    imageUrl: photos[i].url!,
                    httpHeaders: doubanImageHeaders,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _photoAspect(Photo photo) {
    if (photo.width != null && photo.height != null && photo.width! > 0 && photo.height! > 0) {
      return photo.width! / photo.height!;
    }
    return 4 / 3;
  }

  bool _hasCounts(FeedItem item) =>
      item.reactionsCount > 0 || item.commentsCount > 0 || item.resharesCount > 0;

  /// 赞 / 评论 / 转发, only the non-zero ones.
  Widget _countRow(BuildContext context, FeedItem item) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      children: [
        if (item.reactionsCount > 0) ...[
          const Icon(Icons.thumb_up_outlined, size: 16),
          const SizedBox(width: 4),
          Text('${item.reactionsCount}', style: style),
          const SizedBox(width: 16),
        ],
        if (item.commentsCount > 0) ...[
          const Icon(Icons.comment_outlined, size: 16),
          const SizedBox(width: 4),
          Text('${item.commentsCount}', style: style),
          const SizedBox(width: 16),
        ],
        if (item.resharesCount > 0) ...[
          const Icon(Icons.share_outlined, size: 16),
          const SizedBox(width: 4),
          Text('${item.resharesCount}', style: style),
        ],
      ],
    );
  }
}
