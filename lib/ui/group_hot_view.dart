import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/local_lists.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'widgets.dart';

/// The group tab: 发现 | 热门榜 | 已收藏, plus an overflow menu to open
/// a group by id (the old id input sat at the top of the hot list; it
/// now lives behind ⋮). Tapping a group pushes the detail page;
/// this view owns no detail state. The 发现 tab shows only the
/// "更多小组" list: the category tags and themed sets have no second
/// hop in the /group/explore response, so they stay hidden until
/// their list API is found.
class GroupHotView extends StatefulWidget {
  const GroupHotView({super.key, required this.repository, required this.onOpenGroup});

  final DoubanRepository repository;

  /// (groupId, groupName) — the name is shown in the detail page's
  /// AppBar before its own detail fetch returns.
  final void Function(String groupId, String? groupName) onOpenGroup;

  @override
  State<GroupHotView> createState() => _GroupHotViewState();
}

class _GroupHotViewState extends State<GroupHotView> {
  String _segment = 'discover';
  List<SearchGroup> _hotGroups = [];
  bool _hotLoading = true;
  String? _hotError;

  /// "更多小组" list (discover tab): paged, deduped by group id.
  List<RecommendedGroup> _recommended = [];
  int _recommendedTotal = 0;
  bool _discoverLoading = true;
  bool _discoverLoadingMore = false;
  bool _discoverExhausted = false;
  bool _discoverMoreFailed = false;
  String? _discoverError;

  final _idController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHotGroups();
    _loadDiscover();
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _loadHotGroups() async {
    setState(() {
      _hotLoading = true;
      _hotError = null;
    });
    try {
      final groups = await widget.repository.fetchHotGroups();
      if (mounted) setState(() => _hotGroups = groups);
    } catch (e) {
      if (mounted) setState(() => _hotError = '$e');
    } finally {
      if (mounted) setState(() => _hotLoading = false);
    }
  }

  Future<void> _loadDiscover() async {
    setState(() {
      _discoverLoading = true;
      _discoverError = null;
    });
    try {
      // One /group/explore request; the hot tab's fetchHotGroups
      // shares the cached response.
      final explore = await widget.repository.fetchGroupExplore();
      if (mounted) {
        setState(() {
          _recommended = explore.recommendedGroups;
          _recommendedTotal = explore.recommendedTotal;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _discoverError = '$e');
    } finally {
      if (mounted) setState(() => _discoverLoading = false);
    }
  }

  Future<void> _loadMoreDiscover() async {
    if (_discoverLoadingMore) return;
    setState(() {
      _discoverLoadingMore = true;
      _discoverMoreFailed = false;
    });
    try {
      final page = await widget.repository.fetchRecommendedGroups(start: _recommended.length, count: 20);
      if (mounted) {
        setState(() {
          final seen = _recommended.map((e) => e.group.id).toSet();
          final fresh = page.groups.where((e) => seen.add(e.group.id)).toList();
          if (fresh.isEmpty) _discoverExhausted = true;
          _recommended = [..._recommended, ...fresh];
          _recommendedTotal = page.total;
        });
      }
    } catch (_) {
      // Load-more failure is non-fatal: the footer retry stays.
      if (mounted) setState(() => _discoverMoreFailed = true);
    } finally {
      if (mounted) setState(() => _discoverLoadingMore = false);
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
    if (id != null && id.trim().isNotEmpty) widget.onOpenGroup(id.trim(), null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'discover', label: Text('发现')),
                        ButtonSegment(value: 'hot', label: Text('热门榜')),
                        ButtonSegment(value: 'favorites', label: Text('已收藏')),
                      ],
                      selected: {_segment},
                      onSelectionChanged: (selection) => setState(() => _segment = selection.first),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: '按 id 打开',
                onPressed: _showOpenByIdDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _segment == 'discover'
              ? _discoverView()
              : _segment == 'hot'
                  ? _hotGrid()
                  : _favoritesGrid(),
        ),
      ],
    );
  }

  /// Discover tab: the "更多小组" paged grid, reusing the hot grid's
  /// cards (tap opens the detail page, where the favorite star
  /// lives). Categories and themed sets are not rendered: their
  /// second hop is unconfirmed, so only this list ships.
  Widget _discoverView() {
    if (_discoverLoading) return const LoadingList();
    if (_discoverError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(message: '加载失败：$_discoverError'),
            FilledButton(onPressed: _loadDiscover, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_recommended.isEmpty) return const EmptyState(message: '暂无更多小组');
    return Column(
      children: [
        Expanded(
          child: _groupGrid(
            itemCount: _recommended.length,
            itemBuilder: (_, i) {
              final group = _recommended[i].group;
              return _groupCard(
                avatar: group.avatar,
                name: group.name,
                subtitle: '${group.memberCount} 个成员',
                onTap: () => widget.onOpenGroup(group.id, group.name),
              );
            },
          ),
        ),
        _discoverFooter(),
      ],
    );
  }

  Widget _discoverFooter() {
    final hasMore = !_discoverExhausted && _recommended.length < _recommendedTotal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('已加载 ${_recommended.length} / $_recommendedTotal', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (_discoverLoadingMore)
            const CircularProgressIndicator()
          else if (_discoverMoreFailed)
            FilledButton(onPressed: _loadMoreDiscover, child: const Text('加载失败，重试'))
          else if (hasMore)
            FilledButton(onPressed: _loadMoreDiscover, child: const Text('加载更多'))
          else
            const Text('已全部加载'),
        ],
      ),
    );
  }

  Widget _hotGrid() {
    if (_hotLoading) return const LoadingList();
    if (_hotError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(message: '加载失败：$_hotError'),
            FilledButton(onPressed: _loadHotGroups, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_hotGroups.isEmpty) return const EmptyState(message: '暂无热门小组');
    return _groupGrid(
      itemCount: _hotGroups.length,
      itemBuilder: (_, i) {
        final group = _hotGroups[i];
        return _groupCard(
          avatar: group.avatar,
          name: group.name,
          subtitle: '${group.memberCount} 个成员',
          onTap: () => widget.onOpenGroup(group.id, group.name),
        );
      },
    );
  }

  Widget _favoritesGrid() {
    return ListenableBuilder(
      listenable: LocalLists.instance,
      builder: (context, _) {
        final favorites = LocalLists.instance.favoriteGroups;
        if (favorites.isEmpty) {
          return const EmptyState(message: '还没有收藏的小组，在小组页点右上角的星标收藏。');
        }
        return _groupGrid(
          itemCount: favorites.length,
          itemBuilder: (_, i) {
            final group = favorites[i];
            return _groupCard(
              avatar: group.avatar,
              name: group.name,
              subtitle: '已收藏',
              onTap: () => widget.onOpenGroup(group.id, group.name),
            );
          },
        );
      },
    );
  }

  /// Grid of ~300-wide cards: 1 column on a phone, up to 4 on a
  /// wide desktop, capped at 1440.
  Widget _groupGrid({required int itemCount, required IndexedWidgetBuilder itemBuilder}) {
    return CenteredWidth(
      maxWidth: Breakpoints.gridMaxWidth,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = ((constraints.maxWidth - 32) / 300).floor().clamp(1, 4);
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.3,
            ),
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          );
        },
      ),
    );
  }

  Widget _groupCard({required String? avatar, required String name, required String subtitle, required VoidCallback onTap}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: avatar == null || avatar.isEmpty
                    ? const SizedBox(width: 48, height: 48, child: Icon(Icons.group_outlined))
                    : CachedNetworkImage(imageUrl: avatar, httpHeaders: doubanImageHeaders, width: 48, height: 48, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.group_outlined)),
              ),
              const SizedBox(height: 8),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
