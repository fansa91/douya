import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/settings.dart';
import '../models/models.dart';
import 'group_page.dart';
import 'subject_page.dart';
import 'user_page.dart';
import 'widgets.dart';

/// Search page, modeled on c001apk's search flow but with douya's
/// verified Frodo endpoints:
/// - empty query: hot search (Frodo /search/hots) + history chips
/// - typing (300 ms debounce): Frodo /search/suggestion words + cards
/// - submit: tabs for subjects / content / groups / users, subjects
///   support type filters (from types[]) and load-more pagination.
/// Never use Frodo /search: it returns 403 code 103 for guests.
/// Content items and group topics have no douya detail page yet,
/// so they are shown read-only; groups and users do navigate to
/// their (id-prefilled) pages.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.repository});

  final DoubanRepository repository;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late final _tabController = TabController(length: 4, vsync: this);
  Timer? _debounce;
  List<String> _suggestWords = const [];
  List<Subject> _suggestSubjects = const [];
  List<Subject> _hots = const [];
  bool _hotsLoaded = false;

  String? _submitted;
  int _tab = 0;
  String? _selectedType;
  SearchSubjectsResult? _subjectsResult;
  List<Subject> _subjects = const [];
  int _subjectsStart = 0;
  bool _loadingMore = false;
  bool _loading = false;
  bool _tabLoaded = false;
  List<SearchContentItem> _contents = const [];
  SearchGroupResult? _groupsResult;
  List<SearchUser> _users = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadHots();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadHots() async {
    try {
      final hots = await widget.repository.fetchSearchHots();
      if (mounted) setState(() => _hots = hots);
    } catch (_) {
      // Hot search is a nice-to-have; an empty list is fine.
    } finally {
      if (mounted) setState(() => _hotsLoaded = true);
    }
  }

  void _onScroll() {
    if (_tab != 0 || _submitted == null || _loadingMore) return;
    if (_subjectsResult == null || _subjects.length >= _subjectsResult!.total) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    _loadSubjectsPage(append: true);
  }

  Future<void> _onChanged(String value) async {
    _debounce?.cancel();
    if (value.isEmpty) {
      setState(() {
        _suggestWords = const [];
        _suggestSubjects = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await widget.repository.fetchSearchSuggestion(value);
        if (mounted) {
          setState(() {
            _suggestWords = result.words;
            _suggestSubjects = result.subjects;
          });
        }
      } catch (_) {
        // Suggest degrades silently, like the Web suggest before it.
      }
    });
  }

  Future<void> _submit(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    SettingsStore.instance.addSearchHistory(query);
    _tabController.index = 0;
    setState(() {
      _submitted = query;
      _tab = 0;
      _selectedType = null;
      _subjectsResult = null;
      _subjects = const [];
      _subjectsStart = 0;
      _tabLoaded = false;
      _contents = const [];
      _groupsResult = null;
      _users = const [];
      _error = null;
    });
    await _loadTab(0);
  }

  Future<void> _loadTab(int tab) async {
    final query = _submitted;
    if (query == null) return;
    if (_tabController.index != tab) _tabController.index = tab;
    setState(() {
      _tab = tab;
      _loading = true;
      _error = null;
    });
    try {
      switch (tab) {
        case 0:
          await _loadSubjectsPage();
        case 1:
          final items = await widget.repository.fetchSearchContent(query);
          if (mounted) setState(() => _contents = items);
        case 2:
          final result = await widget.repository.fetchSearchGroups(query);
          if (mounted) setState(() => _groupsResult = result);
        case 3:
          final users = await widget.repository.fetchSearchUsers(query);
          if (mounted) setState(() => _users = users);
      }
      if (mounted) setState(() => _tabLoaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSubjectsPage({bool append = false}) async {
    final query = _submitted;
    if (query == null) return;
    final start = append ? _subjectsStart : 0;
    if (append) setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchSearchSubjects(
        query,
        type: _selectedType,
        start: start,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        _subjectsResult = result;
        _subjects = append ? [..._subjects, ...result.items] : result.items;
        _subjectsStart = start + result.items.length;
        _tabLoaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _selectType(String? type) {
    if (type == _selectedType) return;
    setState(() {
      _selectedType = type;
      _subjects = const [];
      _subjectsStart = 0;
    });
    _loadSubjectsPage();
  }

  void _openSubject(Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectPage(repository: widget.repository, type: subject.type, id: subject.id),
      ),
    );
  }

  Widget _chipSection(String title, List<String> items, void Function(String) onTap, {Widget? trailing}) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
              if (trailing != null) trailing,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                ActionChip(label: Text(item), onPressed: () => onTap(item)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    final settings = SettingsStore.instance;
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final currentHistory = settings.searchHistoryEnabled ? settings.searchHistory : const <String>[];
        return CenteredWidth(
          child: ListView(
            children: [
              if (_hots.isNotEmpty)
              _chipSection('热搜', _hots.map((s) => s.title).where((t) => t.isNotEmpty).toList(), (title) {
                _controller.text = title;
                _submit(title);
              }),
            if (_hotsLoaded && _hots.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('热搜暂不可用，输入关键词仍可搜索。'),
              ),
            _chipSection(
              '搜索历史',
              currentHistory,
              (text) {
                _controller.text = text;
                _submit(text);
              },
              trailing: currentHistory.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除全部',
                      icon: const Icon(Icons.clear_all),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确定清除全部搜索历史？'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
                              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('确定')),
                            ],
                          ),
                        );
                        if (confirmed == true) SettingsStore.instance.clearSearchHistory();
                      },
                    ),
            ),
            if (currentHistory.isEmpty && _hots.isEmpty)
              const EmptyState(message: '输入关键词，先看联想结果；回车进入完整搜索。'),
            ],
          ),
        );
      },
    );
  }

  Widget _suggestState() {
    return CenteredWidth(
      child: ListView(
        children: [
        if (_suggestWords.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final word in _suggestWords)
                  ActionChip(
                    label: Text(word),
                    onPressed: () {
                      _controller.text = word;
                      _submit(word);
                    },
                  ),
              ],
            ),
          ),
        for (final subject in _suggestSubjects)
          SubjectRow(subject: subject, onTap: () => _openSubject(subject)),
        if (_suggestWords.isEmpty && _suggestSubjects.isEmpty)
          const EmptyState(message: '没有联想结果，回车进入完整搜索。'),
        ],
      ),
    );
  }

  Widget _subjectsTab() {
    final types = _subjectsResult?.types ?? const [];
    final total = _subjectsResult?.total ?? 0;
    return Column(
      children: [
        if (types.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _selectedType == null,
                  onSelected: (_) => _selectType(null),
                ),
                const SizedBox(width: 8),
                for (final type in types)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${type.typeName} ${type.total}'),
                      selected: _selectedType == type.type,
                      onSelected: (_) => _selectType(type.type),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _subjects.isEmpty
              ? EmptyState(message: total == 0 ? '没有找到条目' : '该类型下没有结果')
              : ListView.builder(
                  controller: _scrollController,
                  itemCount: _subjects.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i >= _subjects.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return SubjectRow(subject: _subjects[i], onTap: () => _openSubject(_subjects[i]));
                  },
                ),
        ),
      ],
    );
  }

  Widget _resultsState() {
    const tabs = ['条目', '帖子', '小组', '用户'];
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          onTap: (index) {
            if (index == _tab && _tabLoaded) return;
            _loadTab(index);
          },
          tabs: [for (final label in tabs) Tab(text: label)],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        Expanded(
          child: CenteredWidth(
            child: switch (_tab) {
            0 => _subjectsTab(),
            1 => _contents.isEmpty
                ? const EmptyState(message: '没有找到帖子内容')
                : ListView.builder(
                    itemCount: _contents.length,
                    itemBuilder: (_, i) => ListTile(
                      title: Text(_contents[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: _contents[i].subtitle.isEmpty ? null : Text(_contents[i].subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
            2 => _groupsResult == null
                ? const EmptyState(message: '没有找到小组')
                : ListView(
                    children: [
                      if (_groupsResult!.groups.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text('小组', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      for (final group in _groupsResult!.groups)
                        ListTile(
                          leading: group.avatar == null
                              ? null
                              : CircleAvatar(backgroundImage: doubanImageProvider(group.avatar!)),
                          title: Text(group.name),
                          subtitle: Text('${group.memberCount} 成员'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: Text(group.name)),
                                  body: GroupPage(repository: widget.repository, initialGroupId: group.id),
                                ),
                              ),
                            );
                          },
                        ),
                      if (_groupsResult!.topics.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text('话题', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      for (final topic in _groupsResult!.topics)
                        ListTile(
                          title: Text(topic.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: topic.subtitle.isEmpty ? null : Text(topic.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
            _ => _users.isEmpty
                ? const EmptyState(message: '没有找到用户')
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: _users[i].avatar == null
                          ? null
                          : CircleAvatar(backgroundImage: doubanImageProvider(_users[i].avatar!)),
                      title: Text(_users[i].name),
                      subtitle: _users[i].abstractText.isEmpty
                          ? null
                          : Text(_users[i].abstractText, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              appBar: AppBar(title: Text(_users[i].name)),
                              body: UserPage(repository: widget.repository, initialUserId: _users[i].id),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索电影、图书、音乐…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                          setState(() => _submitted = null);
                        },
                      ),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999))),
              ),
              onChanged: (value) {
                setState(() {});
                _onChanged(value);
              },
              onSubmitted: _submit,
            ),
          ),
          Expanded(
            child: _submitted == null
                ? (_controller.text.isEmpty ? _emptyState() : _suggestState())
                : _resultsState(),
          ),
        ],
      ),
    );
  }
}
