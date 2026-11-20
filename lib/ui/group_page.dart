import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'topic_detail_view.dart';
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

  /// Detail-page header data (name, member count, description,
  /// avatars). Null while loading or when the detail fetch fails —
  /// the header then falls back to the group id and topics still load.
  SearchGroup? _groupDetail;
  bool _groupDetailLoading = false;
  bool _descExpanded = false;

  @override
  void initState() {
    super.initState();
    _groupId = _groupController.text.trim();
    if (widget.initialGroupId != null) {
      // Opened from search with a group id: go straight to its topics.
      _selectedGroupId = _groupId;
      _load();
      _loadGroupDetail();
    }
    // Always load the hot list too: the in-page "热门小组" back
    // button returns to it, and without this the hot view spins
    // forever (_hotLoading starts true and nothing clears it).
    // Step 4's embedded flag will drop this prefetch when the
    // in-page back button goes away.
    _loadHotGroups();
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
    _loadGroupDetail();
  }

  /// Header data is independent of the topic sort, so it loads once
  /// per group (not on every sort change). A failure only drops the
  /// header, never the topics; a stale response for a previous group
  /// is ignored when the user has already moved on.
  Future<void> _loadGroupDetail() async {
    final groupId = _groupId;
    setState(() {
      _groupDetail = null;
      _groupDetailLoading = true;
      _descExpanded = false;
    });
    try {
      final group = await widget.repository.fetchGroupDetail(groupId);
      if (!mounted || _groupId != groupId) return;
      setState(() {
        _groupDetail = group;
        _groupDetailLoading = false;
      });
    } catch (_) {
      if (!mounted || _groupId != groupId) return;
      setState(() => _groupDetailLoading = false);
    }
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

  Widget _topicCard(GroupTopic topic, {required bool isDesktop}) {
    final meta = [
      if (topic.authorName.isNotEmpty) topic.authorName,
      if (topic.createTime.isNotEmpty) topic.createTime,
      '回应 ${topic.commentsCount}',
    ].join(' · ');
    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isDesktop && _selectedTopicId == topic.id ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () => _openTopic(topic, isDesktop: isDesktop),
        hoverColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        mouseCursor: SystemMouseCursors.click,
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
                  child: CachedNetworkImage(imageUrl: topic.coverUrl!, httpHeaders: doubanImageHeaders, width: 72, height: 72, fit: BoxFit.cover, errorWidget: (context, url, error) => const SizedBox(width: 72, height: 72)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) => showLinkMenu(
        context,
        details.globalPosition,
        topicWebUrl(topic.id),
      ),
      child: card,
    );
  }

  Widget _topicList({required bool isDesktop}) {
    final hasMore = _total > 0 && _topics.length < _total;
    return ListView.builder(
      itemCount: _topics.length + 1,
      itemBuilder: (_, i) {
        if (i >= _topics.length) {
          return LoadMoreFooter(
            countText: _total > 0 ? '已加载 ${_topics.length} / $_total' : null,
            canLoadMore: () => !_loadingMore && hasMore,
            onLoadMore: _loadMore,
          );
        }
        return _topicCard(_topics[i], isDesktop: isDesktop);
      },
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
                    : CachedNetworkImage(imageUrl: group.avatar!, httpHeaders: doubanImageHeaders, width: 48, height: 48, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.group_outlined)),
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

  /// Detail-page header: group avatar, name, member count and
  /// description. The id input used to sit here; it now lives only
  /// on the hot-groups view, and this view is reached from it (or
  /// from a topic's group row). Long descriptions collapse to two
  /// lines with an expand toggle.
  Widget _groupHeader() {
    final group = _groupDetail;
    if (_groupDetailLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: LinearProgressIndicator(),
      );
    }
    if (group == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('小组 ${_selectedGroupId ?? _groupId}', style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    }
    final avatarUrl = group.largeAvatar ?? group.avatar;
    final description = group.description;
    final collapsible = description.length > 80;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? const SizedBox(width: 52, height: 52, child: Icon(Icons.group_outlined))
                  : CachedNetworkImage(imageUrl: avatarUrl, httpHeaders: doubanImageHeaders, width: 52, height: 52, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.group_outlined)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${group.memberCount} 个成员', style: Theme.of(context).textTheme.bodySmall),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: _descExpanded ? null : 2,
                      overflow: _descExpanded ? null : TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (collapsible)
                      InkWell(
                        onTap: () => setState(() => _descExpanded = !_descExpanded),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(_descExpanded ? '收起' : '展开', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
        _groupHeader(),
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
                            // Split once the pane reaches 900 (new
                            // plan, task 6 — replaces the 840 from the
                            // 7-task plan and the original 1024).
                            // List is 340 wide until the pane reaches
                            // 1280, then 420. The detail pane keeps
                            // its own 720 split, so 1000–1280 is
                            // "list 340 + single-column detail" and
                            // 1280+ is "list 420 + two-column detail".
                            if (constraints.maxWidth < Breakpoints.paneSplit) {
                              return _topicList(isDesktop: false);
                            }
                            final listWidth = constraints.maxWidth >=
                                    Breakpoints.groupListWide
                                ? 420.0
                                : 340.0;
                            final selected = _selectedTopicId ?? _topics.first.id;
                            return Row(
                              children: [
                                SizedBox(width: listWidth, child: _topicList(isDesktop: true)),
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
    final body = _selectedGroupId == null ? _hotView() : _topicView();
    // System back in the tab first returns to the hot list; only
    // then does it leave the tab/app. A pushed page (initialGroupId
    // set) keeps its AppBar back working: its route can always pop.
    return PopScope(
      canPop: _selectedGroupId == null || widget.initialGroupId != null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedGroupId != null) {
          setState(() => _selectedGroupId = null);
        }
      },
      child: body,
    );
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

