import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/local_lists.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'widgets.dart';

/// The group tab: 热门 | 已收藏, plus an overflow menu to open a
/// group by id (the old id input sat at the top of the hot list; it
/// now lives behind ⋮). Tapping a group pushes the detail page;
/// this view owns no detail state.
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
  String _segment = 'hot';
  List<SearchGroup> _hotGroups = [];
  bool _hotLoading = true;
  String? _hotError;
  final _idController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHotGroups();
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
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'hot', label: Text('热门')),
                  ButtonSegment(value: 'favorites', label: Text('已收藏')),
                ],
                selected: {_segment},
                onSelectionChanged: (selection) => setState(() => _segment = selection.first),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: '按 id 打开',
                onPressed: _showOpenByIdDialog,
              ),
            ],
          ),
        ),
        Expanded(
          child: _segment == 'hot' ? _hotGrid() : _favoritesGrid(),
        ),
      ],
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
