import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Celebrity page. The id must come from the subject's celebrities
/// endpoint, because the subject detail itself only carries names.
class CelebrityPage extends StatelessWidget {
  const CelebrityPage({super.key, required this.repository, required this.id});

  final DoubanRepository repository;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('影人')),
      body: FutureBuilder<CelebrityDetail>(
        future: repository.fetchCelebrity(id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
          final detail = snapshot.data;
          if (detail == null) return const EmptyState(message: '暂无影人信息');
          final celebrity = detail.celebrity;
          return CenteredWidth(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(context, celebrity),
                if (celebrity.info.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ..._infoRows(context, celebrity),
                ],
                const SizedBox(height: 16),
                Text(
                  '作品${detail.worksTotal > 0 ? '（${detail.worksTotal}）' : ''}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _PagedWorks(
                  repository: repository,
                  id: id,
                  initialItems: detail.works,
                  total: detail.worksTotal,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Photo avatar (not the name's first letter), name, English
  /// name, short info line, and follower count when known.
  Widget _header(BuildContext context, Celebrity celebrity) {
    final avatarUrl = celebrity.avatar;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 40,
          backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl, headers: doubanImageHeaders) : null,
          child: avatarUrl == null
              ? Text(celebrity.name.isEmpty ? '?' : celebrity.name[0], style: const TextStyle(fontSize: 32))
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(celebrity.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (celebrity.latinTitle != null && celebrity.latinTitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(celebrity.latinTitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (celebrity.shortInfo != null && celebrity.shortInfo!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(celebrity.shortInfo!, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (celebrity.followedCount > 0) ...[
                const SizedBox(height: 4),
                Text('关注 ${celebrity.followedCount}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Bio key/value rows from extra.info (gender, birthday,
  /// birthplace, ...).
  List<Widget> _infoRows(BuildContext context, Celebrity celebrity) {
    return [
      for (final (label, value) in celebrity.info)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              Expanded(child: Text(value)),
            ],
          ),
        ),
    ];
  }
}

/// Paged works list: starts from the detail's first page and loads
/// more through fetchCelebrityWorks, deduping by subject id (the
/// endpoint's pages overlap by one entry, probed 2026-11-21). The
/// inner list is a shrink-wrapped builder so the footer only mounts
/// when scrolled near, instead of auto-loading at once.
class _PagedWorks extends StatefulWidget {
  const _PagedWorks({required this.repository, required this.id, required this.initialItems, required this.total});

  final DoubanRepository repository;
  final String id;
  final List<CelebrityWork> initialItems;
  final int total;

  @override
  State<_PagedWorks> createState() => _PagedWorksState();
}

class _PagedWorksState extends State<_PagedWorks> {
  late List<CelebrityWork> _items = widget.initialItems;
  late int _total = widget.total;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchCelebrityWorks(widget.id, start: _items.length, count: 20);
      if (!mounted) return;
      final seen = _items.map((w) => w.subject.id).toSet();
      setState(() {
        _items = [..._items, ...result.works.where((w) => seen.add(w.subject.id))];
        if (result.total > 0) _total = result.total;
        if (result.works.isEmpty) _total = _items.length;
        _loadMoreFailed = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const EmptyState(message: '暂无作品');
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i == _items.length) {
          return LoadMoreFooter(
            key: const ValueKey('celebrity-works-footer'),
            canLoadMore: () => !_loadingMore && _items.length < _total,
            onLoadMore: _loadMore,
            failed: _loadMoreFailed,
            countText: _total > 0 ? '已加载 ${_items.length} / $_total' : null,
          );
        }
        final work = _items[i];
        final subtitleParts = [
          ...work.roles,
          if (work.subject.year != null && work.subject.year!.isNotEmpty) work.subject.year!,
        ];
        return SubjectRow(
          subject: work.subject,
          subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' · ') : null,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SubjectPage(repository: widget.repository, type: work.subject.type, id: work.subject.id),
              ),
            );
          },
        );
      },
    );
  }
}
