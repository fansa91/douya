import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/local_lists.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'group_header.dart';
import 'topic_detail_view.dart';
import 'widgets.dart';

/// A group's topic browser as a pushed page (from the hot list, a
/// favorite, search, or a topic's group row). Entering a group is a
/// real route now, so the system back key works and there is no
/// in-page back button. The AppBar carries the group name, the
/// favorite star, and the ⋮ menu (open by id).
class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({super.key, required this.repository, required this.groupId, this.groupName});

  final DoubanRepository repository;
  final String groupId;
  final String? groupName;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final _idController = TextEditingController();
  String _sort = 'new';
  List<GroupTopic> _topics = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _selectedTopicId;

  /// Detail-page header data (name, member count, description,
  /// avatars). Null while loading or when the detail fetch fails —
  /// the header then falls back to the group id and topics still load.
  SearchGroup? _groupDetail;
  bool _groupDetailLoading = false;

  String get _groupId => widget.groupId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadGroupDetail();
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  /// Header data is independent of the topic sort, so it loads once
  /// per group (not on every sort change). A failure only drops the
  /// header, never the topics.
  Future<void> _loadGroupDetail() async {
    setState(() {
      _groupDetail = null;
      _groupDetailLoading = true;
    });
    try {
      final group = await widget.repository.fetchGroupDetail(_groupId);
      if (!mounted) return;
      setState(() {
        _groupDetail = group;
        _groupDetailLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _groupDetailLoading = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _topics = [];
      _total = 0;
      _selectedTopicId = null;
    });
    try {
      final result = await widget.repository.fetchGroupTopicsPaged(_groupId, _sort, start: 0, count: 20);
      if (mounted) {
        setState(() {
          _topics = result.items;
          _total = result.total;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _topics.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchGroupTopicsPaged(_groupId, _sort, start: _topics.length, count: 20);
      if (mounted) {
        setState(() {
          _topics = [..._topics, ...result.items];
          if (result.total > 0) _total = result.total;
          if (result.items.isEmpty) _total = _topics.length;
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

  void _openTopic(GroupTopic topic, {required bool isDesktop}) {
    if (isDesktop) {
      setState(() => _selectedTopicId = topic.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TopicDetailPage(repository: widget.repository, topicId: topic.id)),
      );
    }
  }

  Future<void> _showOpenByIdDialog() async {
    _idController.clear();
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('按 id 打开'),
        content: TextField(
          controller: _idController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入小组 id，例如 146409',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_idController.text),
            child: const Text('打开'),
          ),
        ],
      ),
    );
    if (id != null && id.trim().isNotEmpty && id.trim() != _groupId) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupTopicsPage(repository: widget.repository, groupId: id.trim()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_groupDetail?.name ?? widget.groupName ?? '小组'),
        actions: [
          ListenableBuilder(
            listenable: LocalLists.instance,
            builder: (context, _) {
              final favorited = LocalLists.instance.isFavoriteGroup(_groupId);
              return IconButton(
                icon: Icon(favorited ? Icons.star : Icons.star_border),
                tooltip: favorited ? '取消收藏' : '收藏小组',
                onPressed: () {
                  final detail = _groupDetail;
                  LocalLists.instance.toggleFavoriteGroup(
                    id: _groupId,
                    name: detail?.name ?? widget.groupName ?? _groupId,
                    avatar: detail?.largeAvatar ?? detail?.avatar,
                  );
                },
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'open_by_id') _showOpenByIdDialog();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'open_by_id', child: Text('按 id 打开')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < Breakpoints.paneSplit) return _mobileDetail();
          return _desktopDetail();
        },
      ),
    );
  }

  /// Mobile: the header scrolls away with the list and the sort row
  /// pins to the top.
  Widget _mobileDetail() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: GroupHeader(detail: _groupDetail, loading: _groupDetailLoading, groupId: _groupId),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _SortHeaderDelegate(child: _sortRow()),
        ),
        if (_loading)
          const SliverFillRemaining(child: LoadingList())
        else if (_error != null)
          SliverFillRemaining(child: EmptyState(message: '加载失败：$_error'))
        else if (_topics.isEmpty)
          const SliverFillRemaining(child: EmptyState(message: '该小组暂无话题'))
        else
          SliverList.builder(
            itemCount: _topics.length + 1,
            itemBuilder: (_, i) {
              if (i >= _topics.length) return _loadMoreFooter();
              return _topicRow(_topics[i], isDesktop: false);
            },
          ),
      ],
    );
  }

  /// Desktop: the header is one full-width row above the split, so
  /// it takes no vertical space from the topic list. The right pane
  /// shows a placeholder until a topic is picked — no auto-request
  /// for the first topic.
  Widget _desktopDetail() {
    return Column(
      children: [
        GroupHeader(detail: _groupDetail, loading: _groupDetailLoading, groupId: _groupId),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Split once the pane reaches 900 (new plan, task 6 —
              // replaces the 840 from the 7-task plan and the
              // original 1024). List is 340 wide until the pane
              // reaches 1280, then 420.
              final listWidth = constraints.maxWidth >= Breakpoints.groupListWide ? 420.0 : 340.0;
              return Row(
                children: [
                  SizedBox(
                    width: listWidth,
                    child: Column(
                      children: [
                        _sortRow(),
                        Expanded(child: _topicListView(isDesktop: true)),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: _selectedTopicId == null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.forum_outlined, size: 48),
                                SizedBox(height: 12),
                                Text('选择左侧话题'),
                              ],
                            ),
                          )
                        : TopicDetailView(repository: widget.repository, topicId: _selectedTopicId!),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _topicListView({required bool isDesktop}) {
    if (_loading) return const LoadingList();
    if (_error != null) return EmptyState(message: '加载失败：$_error');
    if (_topics.isEmpty) return const EmptyState(message: '该小组暂无话题');
    return ListView.builder(
      itemCount: _topics.length + 1,
      itemBuilder: (_, i) {
        if (i >= _topics.length) return _loadMoreFooter();
        return _topicRow(_topics[i], isDesktop: isDesktop);
      },
    );
  }

  Widget _loadMoreFooter() {
    return LoadMoreFooter(
      countText: _total > 0 ? '已加载 ${_topics.length} / $_total' : null,
      canLoadMore: () => !_loadingMore && _total > 0 && _topics.length < _total,
      onLoadMore: _loadMore,
    );
  }

  Widget _sortRow() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (final entry in groupTopicSorts.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: _sort == entry.key,
                onSelected: (_) {
                  if (_sort == entry.key) return;
                  setState(() => _sort = entry.key);
                  _load();
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Flat row (no Card): title, author · time, and the reply count
  /// as a small badge at the bottom right. A selected row on
  /// desktop keeps the primary-container highlight.
  Widget _topicRow(GroupTopic topic, {required bool isDesktop}) {
    final meta = [
      if (topic.authorName.isNotEmpty) topic.authorName,
      if (topic.createTime.isNotEmpty) topic.createTime,
    ].join(' · ');
    final selected = isDesktop && _selectedTopicId == topic.id;
    final row = InkWell(
      onTap: () => _openTopic(topic, isDesktop: isDesktop),
      hoverColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      mouseCursor: SystemMouseCursors.click,
      child: Container(
        color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        // IntrinsicHeight gives the Row a definite height (the
        // tallest child) so the stretch below is valid inside a
        // scrolling list, and the badge can sit at the bottom right.
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(topic.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(meta, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (topic.coverUrl != null && topic.coverUrl!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(imageUrl: topic.coverUrl!, httpHeaders: doubanImageHeaders, width: 72, height: 72, fit: BoxFit.cover, errorWidget: (context, url, error) => const SizedBox(width: 72, height: 72)),
                  ),
                  const SizedBox(height: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('回应 ${topic.commentsCount}', style: Theme.of(context).textTheme.bodySmall),
                ),
              ],
            ),
            ],
          ),
        ),
      ),
    );
    return Column(
      children: [
        GestureDetector(
          onSecondaryTapUp: (details) => showLinkMenu(
            context,
            details.globalPosition,
            topicWebUrl(topic.id),
          ),
          child: row,
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// A group's topic browser as a pushed page (used by search and by
/// the topic detail's group row). GroupPage itself has no Scaffold
/// because it normally lives in the shell's tab body.
class GroupTopicsPage extends StatelessWidget {
  const GroupTopicsPage({super.key, required this.repository, required this.groupId, this.groupName});

  final DoubanRepository repository;
  final String groupId;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    return GroupDetailPage(repository: repository, groupId: groupId, groupName: groupName);
  }
}

/// Pinned header for the mobile sort row (ChoiceChips, 32 tall +
/// 12 of vertical padding).
class _SortHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SortHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: 44, child: child);
  }

  @override
  bool shouldRebuild(_SortHeaderDelegate oldDelegate) => oldDelegate.child != child;
}
