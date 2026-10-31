import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'group_page.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Discover page: the real home recommend feed only. The
/// guest-assembled recommendation sections that used to sit below
/// the feed now live in Browse under the 推荐 category.
///
/// The feed is Frodo /elendil/recommend_feed with for_mobile=1
/// (without that param the guest call returns 200 but 0 items;
/// verified 2026-10-31). It carries no total, so paging stops on
/// a short page. Feed cards are topic/review posts, NOT subject
/// posters: they render as text cards, topic taps open the topic
/// detail, review taps open the review detail, and any other type
/// falls back to the share link in a browser.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.repository});

  final DoubanRepository repository;

  @override
  Widget build(BuildContext context) {
    // Mobile (<600): single reading column, centered at 720.
    // Desktop (>=600, the shell's rail breakpoint): waterfall
    // (masonry) feed, c001apk's adaptive_card_list pattern — column
    // count from a fixed card width, shortest-column placement.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return CenteredWidth(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('推荐动态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _FeedList(repository: repository),
              ],
            ),
          );
        }
        return _FeedList(repository: repository, masonry: true);
      },
    );
  }
}

/// Paged recommend-feed list. Mobile builds a Column (not its own
/// scroll view) because it lives inside the Discover ListView;
/// desktop builds its own CustomScrollView with a masonry sliver.
class _FeedList extends StatefulWidget {
  const _FeedList({required this.repository, this.masonry = false});

  final DoubanRepository repository;
  final bool masonry;

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  List<FeedItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.fetchRecommendFeed(start: 0, count: 20);
      if (mounted) {
        setState(() {
          _items = result.items;
          _hasMore = result.hasMore;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchRecommendFeed(start: _items.length, count: 20);
      if (mounted) {
        setState(() {
          _items = [..._items, ...result.items];
          _hasMore = result.hasMore;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载更多失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openItem(FeedItem item) {
    if (item.type == 'topic') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TopicDetailPage(repository: widget.repository, topicId: item.id),
        ),
      );
    } else if (item.type == 'review') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewDetailPage(repository: widget.repository, reviewId: item.id),
        ),
      );
    } else if (item.sharingUrl.isNotEmpty) {
      launchUrl(Uri.parse(item.sharingUrl), mode: LaunchMode.externalApplication);
    }
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _hasMore
          ? FilledButton(
              onPressed: _loadingMore ? null : _loadMore,
              child: Text(_loadingMore ? '加载中…' : '加载更多'),
            )
          : const Text('已全部加载'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const spinner = Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
      if (!widget.masonry) return spinner;
      return const CustomScrollView(
        slivers: [SliverToBoxAdapter(child: spinner)],
      );
    }
    if (_error != null && _items.isEmpty) {
      final errorView = Column(
        children: [
          Text('推荐动态加载失败：$_error'),
          const SizedBox(height: 8),
          FilledButton(onPressed: _loadInitial, child: const Text('重试')),
        ],
      );
      if (!widget.masonry) return errorView;
      return CustomScrollView(
        slivers: [SliverToBoxAdapter(child: errorView)],
      );
    }
    if (_items.isEmpty) {
      const empty = Text('暂无推荐动态');
      if (!widget.masonry) return empty;
      return const CustomScrollView(
        slivers: [SliverToBoxAdapter(child: empty)],
      );
    }
    if (!widget.masonry) {
      return Column(
        children: [
          for (final item in _items) _FeedCard(item: item, onTap: () => _openItem(item)),
          _footer(),
        ],
      );
    }
    // Desktop masonry: column count from c001apk's formula
    // (card width ~360 + 12 spacing, 1-4 columns). The LayoutBuilder
    // width here is already minus the navigation rail.
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth - 32 + 12) / 372).floor().clamp(1, 4);
        return CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text('推荐动态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childCount: _items.length,
                itemBuilder: (context, i) => _FeedCard(
                  item: _items[i],
                  onTap: () => _openItem(_items[i]),
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
        );
      },
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item, required this.onTap, this.margin = const EdgeInsets.only(bottom: 12)});

  final FeedItem item;
  final VoidCallback onTap;

  /// Mobile list spacing; masonry passes zero because the grid's
  /// mainAxisSpacing already separates rows.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margin,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
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
                    ),
                  ),
                  if (item.typeCn.isNotEmpty)
                    Chip(label: Text(item.typeCn), visualDensity: VisualDensity.compact),
                ],
              ),
              if (item.title.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
              if (item.abstract.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item.abstract, maxLines: 5, overflow: TextOverflow.ellipsis),
              ],
              if (item.photoUrls.isNotEmpty) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: item.photoUrls.first,
                    httpHeaders: doubanImageHeaders,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('评论 ${item.commentsCount}'),
                  if (item.resharesCount > 0) Text(' · 转发 ${item.resharesCount}'),
                  if (item.createdTime.isNotEmpty) ...[
                    const Spacer(),
                    Text(item.createdTime, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
