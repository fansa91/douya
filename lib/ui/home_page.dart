import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'group_page.dart';
import 'subject_page.dart';

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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('推荐动态', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _FeedList(repository: repository),
      ],
    );
  }
}

/// Paged recommend-feed list. Builds a Column (not its own scroll
/// view) because it lives inside the Discover ListView.
class _FeedList extends StatefulWidget {
  const _FeedList({required this.repository});

  final DoubanRepository repository;

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Column(
        children: [
          Text('推荐动态加载失败：$_error'),
          const SizedBox(height: 8),
          FilledButton(onPressed: _loadInitial, child: const Text('重试')),
        ],
      );
    }
    if (_items.isEmpty) return const Text('暂无推荐动态');
    return Column(
      children: [
        for (final item in _items) _FeedCard(item: item, onTap: () => _openItem(item)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _hasMore
              ? FilledButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: Text(_loadingMore ? '加载中…' : '加载更多'),
                )
              : const Text('已全部加载'),
        ),
      ],
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item, required this.onTap});

  final FeedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                      backgroundImage: NetworkImage(item.authorAvatar!),
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
                  child: Image.network(
                    item.photoUrls.first,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_outlined),
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
