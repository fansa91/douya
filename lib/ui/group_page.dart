import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'widgets.dart';

/// Group browsing, modeled on c001apk's topic page patterns: a sort
/// menu (最新 / 热门), card-style topic rows, and a detail view with
/// selectable body text and card-style replies (read-only: no reply,
/// like or follow actions in guest mode).
/// There is deliberately no "my groups" list here, because
/// group/user/{id}/joined_groups returns 403 for guest signatures.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key, required this.repository, this.initialGroupId});

  final DoubanRepository repository;
  final String? initialGroupId;

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  late final _groupController = TextEditingController(text: widget.initialGroupId ?? '146409');
  String _sort = 'new';
  String _groupId = '';
  List<GroupTopic> _topics = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _selectedTopicId;

  /// null = hot groups list (the default view); otherwise the topic
  /// browser for that group id. Discussion featured (讨论精选) is
  /// deliberately not a view here: it has no JSON API, only
  /// server-rendered web HTML, and is shelved (2026-10-31).
  String? _selectedGroupId;
  List<SearchGroup> _hotGroups = [];
  bool _hotLoading = true;
  String? _hotError;

  @override
  void initState() {
    super.initState();
    _groupId = _groupController.text.trim();
    if (widget.initialGroupId != null) {
      // Opened from search with a group id: go straight to its topics.
      _selectedGroupId = _groupId;
      _load();
    } else {
      _loadHotGroups();
    }
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

  void _openGroup(String groupId) {
    _groupController.text = groupId;
    _groupId = groupId;
    _selectedGroupId = groupId;
    _load();
  }

  @override
  void dispose() {
    _groupController.dispose();
    super.dispose();
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

  Widget _topicCard(GroupTopic topic, {required bool isDesktop}) {
    final meta = [
      if (topic.authorName.isNotEmpty) topic.authorName,
      if (topic.createTime.isNotEmpty) topic.createTime,
      '回应 ${topic.commentsCount}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isDesktop && _selectedTopicId == topic.id ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () => _openTopic(topic, isDesktop: isDesktop),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topic.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(meta, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (topic.coverUrl != null && topic.coverUrl!.isNotEmpty) ...[
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(topic.coverUrl!, width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const SizedBox(width: 72, height: 72)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _topicList({required bool isDesktop}) {
    final hasMore = _total > 0 && _topics.length < _total;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _topics.length,
            itemBuilder: (_, i) => _topicCard(_topics[i], isDesktop: isDesktop),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_total > 0) Text('已加载 ${_topics.length} / $_total'),
              const SizedBox(height: 8),
              if (hasMore)
                FilledButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: Text(_loadingMore ? '加载中…' : '加载更多'),
                )
              else
                const Text('已全部加载'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _idInputRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _groupController,
              decoration: const InputDecoration(
                hintText: '输入小组 id，例如 146409',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999))),
              ),
              onSubmitted: (_) => _openGroup(_groupController.text.trim()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _openGroup(_groupController.text.trim()),
            child: const Text('查看'),
          ),
        ],
      ),
    );
  }

  Widget _hotGroupCard(SearchGroup group) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => _openGroup(group.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: group.avatar == null || group.avatar!.isEmpty
                    ? const SizedBox(width: 48, height: 48, child: Icon(Icons.group_outlined))
                    : Image.network(group.avatar!, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.group_outlined)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${group.memberCount} 个成员', style: Theme.of(context).textTheme.bodySmall),
                    if (group.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(group.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hotView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _idInputRow(),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('热门小组 · 本周热门趋势榜Top20', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: _hotLoading
              ? const LoadingList()
              : _hotError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          EmptyState(message: '加载失败：$_hotError'),
                          FilledButton(onPressed: _loadHotGroups, child: const Text('重试')),
                        ],
                      ),
                    )
                  : _hotGroups.isEmpty
                      ? const EmptyState(message: '暂无热门小组')
                      : CenteredWidth(
                          child: ListView.builder(
                            itemCount: _hotGroups.length,
                            itemBuilder: (_, i) => _hotGroupCard(_hotGroups[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _topicView() {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _selectedGroupId = null),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('热门小组'),
          ),
        ),
        _idInputRow(),
        Padding(
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
        ),
        Expanded(
          child: _loading
              ? const LoadingList()
              : _error != null
                  ? EmptyState(message: '加载失败：$_error')
                  : _topics.isEmpty
                      ? const EmptyState(message: '该小组暂无话题')
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 1024) {
                              return _topicList(isDesktop: false);
                            }
                            final selected = _selectedTopicId ?? _topics.first.id;
                            return Row(
                              children: [
                                SizedBox(width: 420, child: _topicList(isDesktop: true)),
                                const VerticalDivider(width: 1),
                                Expanded(child: TopicDetailView(repository: widget.repository, topicId: selected)),
                              ],
                            );
                          },
                        ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedGroupId == null) return _hotView();
    return _topicView();
  }
}

/// A group's topic browser as a pushed page (used by the topic
/// detail's group row). GroupPage itself has no Scaffold because
/// it normally lives in the shell's tab body.
class GroupTopicsPage extends StatelessWidget {
  const GroupTopicsPage({super.key, required this.repository, required this.groupId});

  final DoubanRepository repository;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('小组话题')),
      body: GroupPage(repository: repository, initialGroupId: groupId),
    );
  }
}

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

class TopicDetailView extends StatelessWidget {
  const TopicDetailView({super.key, required this.repository, required this.topicId});

  final DoubanRepository repository;
  final String topicId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TopicDetail>(
      future: repository.fetchTopic(topicId),
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
        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 720) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _headerCard(context, detail),
                  const SizedBox(height: 16),
                  SelectableText(detail.content),
                  const Divider(height: 32),
                  Text('回复 (${detail.comments.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (detail.comments.isEmpty) const EmptyState(message: '暂无回复'),
                  for (final c in detail.comments) _commentCard(c),
                ],
              );
            }
            // The split itself is capped at 1440 so neither column
            // stretches across an ultrawide window.
            return CenteredWidth(
              maxWidth: 1440,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _headerCard(context, detail),
                        const SizedBox(height: 16),
                        SelectableText(detail.content),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text('回复 (${detail.comments.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (detail.comments.isEmpty) const EmptyState(message: '暂无回复'),
                        for (final c in detail.comments) _commentCard(c),
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
            Text(detail.topic.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${detail.topic.authorName} · ${detail.topic.createTime} · 回应 ${detail.topic.commentsCount}'),
            if (detail.groupName.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: detail.groupId.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GroupTopicsPage(repository: repository, groupId: detail.groupId),
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

  Widget _commentCard(TopicComment c) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(c.authorName),
        subtitle: SelectableText(c.text),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.thumb_up_outlined, size: 16),
            const SizedBox(width: 4),
            Text('${c.voteCount}'),
          ],
        ),
      ),
    );
  }
}
