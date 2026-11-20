import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/local_lists.dart';
import '../data/repository.dart';
import '../data/settings.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Type/status labels in Chinese. The API keys are book/movie/music
/// and done/doing/mark; the status verb follows the type (读/看/听).
String userTypeLabel(String type) => switch (type) {
      'book' => '图书',
      'movie' => '电影',
      'music' => '音乐',
      _ => type,
    };

String userStatusLabel(String type, String status) {
  final verb = switch (type) { 'book' => '读', 'music' => '听', _ => '看' };
  return switch (status) { 'mark' => '想$verb', 'doing' => '在$verb', _ => '$verb过' };
}

/// One cached page of interests for a (type, status) pair.
class _InterestPage {
  List<Interest> items = [];
  int total = 0;
  bool loading = false;
}

/// "我的公开收藏": guest mode has no login, so the user binds their
/// public Douban id once (stored in LocalLists) and the page opens
/// straight to their own public interests. Viewing someone else goes
/// through the search page's user search (initialUserId), which
/// never changes the binding.
class UserPage extends StatefulWidget {
  const UserPage({super.key, required this.repository, this.initialUserId});

  final DoubanRepository repository;
  final String? initialUserId;

  @override
  State<UserPage> createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  final _bindController = TextEditingController();
  String? _userId;
  String _type = 'book';
  String _status = 'done';
  UserProfile? _profile;
  bool _profileLoading = false;
  String? _profileError;
  String? _interestsError;
  final _pages = <String, _InterestPage>{};
  bool _listView = false; // desktop only: list vs poster grid

  String get _pageKey => '$_type|$_status';
  _InterestPage get _page => _pages.putIfAbsent(_pageKey, _InterestPage.new);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUserId ?? LocalLists.instance.myUserId;
    if (initial != null && initial.isNotEmpty) {
      _userId = initial;
      _loadProfile(initial);
      _loadInterests(reset: true);
    }
  }

  @override
  void dispose() {
    _bindController.dispose();
    super.dispose();
  }

  /// The profile is fetched once per id change, never on a type or
  /// status switch. A failed load clears the old profile: showing
  /// another user's data under the current id would mislead.
  Future<void> _loadProfile(String userId) async {
    setState(() {
      _profileLoading = true;
      _profileError = null;
    });
    try {
      final profile = await widget.repository.fetchUser(userId);
      if (!mounted || _userId != userId) return;
      setState(() => _profile = profile);
      unawaited(LocalLists.instance.addRecentUser(
        id: profile.id,
        name: profile.name,
        avatar: profile.avatar,
      ));
    } catch (e) {
      if (!mounted || _userId != userId) return;
      setState(() {
        _profile = null;
        _profileError = '$e';
      });
    } finally {
      if (mounted && _userId == userId) {
        setState(() => _profileLoading = false);
      }
    }
  }

  Future<void> _loadInterests({bool reset = false}) async {
    final userId = _userId;
    if (userId == null) return;
    final page = _page;
    if (page.loading) return;
    if (reset) {
      page.items = [];
      page.total = 0;
    }
    if (page.total > 0 && page.items.length >= page.total) return;
    page.loading = true;
    _interestsError = null;
    if (mounted) setState(() {});
    try {
      final result = await widget.repository.fetchInterests(
        userId,
        _type,
        _status,
        start: page.items.length,
        count: 50,
      );
      if (!mounted || _userId != userId) return;
      setState(() {
        page.items = [...page.items, ...result.items];
        page.total = result.total;
        if (result.items.isEmpty) page.total = page.items.length;
      });
    } catch (e) {
      if (!mounted) return;
      _interestsError = '$e';
      if (page.items.isEmpty) {
        // Nothing to keep: the content area shows the error state.
        setState(() {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载更多失败：$e')),
        );
      }
    } finally {
      page.loading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _viewUser(String id, {bool bind = false}) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    if (bind) await LocalLists.instance.setMyUserId(trimmed);
    if (_userId == trimmed && _profile != null) return;
    setState(() {
      _userId = trimmed;
      _profile = null;
      _profileError = null;
      _interestsError = null;
      _pages.clear();
    });
    _loadProfile(trimmed);
    _loadInterests(reset: true);
  }

  void _retryAll() {
    final userId = _userId;
    if (userId == null) return;
    _loadProfile(userId);
    _loadInterests(reset: true);
  }

  void _openSubject(Interest interest) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectPage(
          repository: widget.repository,
          type: interest.subject.type,
          id: interest.subject.id,
        ),
      ),
    );
  }

  Future<void> _showSwitchUserDialog() async {
    _bindController.text = _userId ?? '';
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换用户'),
        content: TextField(
          controller: _bindController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入公开用户 id，例如 2870956',
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
            onPressed: () => Navigator.of(context).pop(_bindController.text),
            child: const Text('绑定'),
          ),
        ],
      ),
    );
    if (id != null) _viewUser(id, bind: true);
  }

  void _selectType(String type) {
    if (_type == type) return;
    setState(() => _type = type);
    _loadInterests();
  }

  void _selectStatus(String status) {
    if (_status == status) return;
    setState(() => _status = status);
    _loadInterests();
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) return _guideView();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (Breakpoints.of(constraints.maxWidth) == WindowSize.compact) {
          return _mobileView();
        }
        return _desktopView();
      },
    );
  }

  /// Unbound state: explain how to find the id, bind it, and offer
  /// recently viewed users.
  Widget _guideView() {
    return CenteredWidth(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.person_outline, size: 48),
            const SizedBox(height: 12),
            const Text('我的公开收藏', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('访客模式不能登录。在豆瓣个人主页地址 douban.com/people/<ID>/ 里找到你的 id，绑定后每次打开直接看到自己的收藏；只能查看公开收藏。'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bindController,
                    decoration: const InputDecoration(
                      hintText: '输入公开用户 id，例如 2870956',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(999))),
                    ),
                    onSubmitted: (value) => _viewUser(value, bind: true),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _viewUser(_bindController.text, bind: true),
                  child: const Text('绑定并查看'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _recentUsersSection(),
          ],
        ),
      ),
    );
  }

  Widget _recentUsersSection() {
    return ListenableBuilder(
      listenable: LocalLists.instance,
      builder: (context, _) {
        final recents = LocalLists.instance.recentUsers;
        if (recents.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('最近查看', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () => LocalLists.instance.clearRecentUsers(),
                  child: const Text('清空'),
                ),
              ],
            ),
            for (final u in recents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundImage: u.avatar != null ? doubanImageProvider(u.avatar!) : null,
                  child: u.avatar == null ? Text(u.name.isEmpty ? '?' : u.name[0]) : null,
                ),
                title: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('@${u.id}'),
                onTap: () => _viewUser(u.id),
              ),
          ],
        );
      },
    );
  }

  /// Avatar, name, @id, 粉丝/关注， and a switch button. Loading
  /// shows a thin progress bar; a failed profile shows nothing here
  /// — the error state lives in the content area.
  Widget _profileHeader() {
    if (_profileLoading && _profile == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final profile = _profile;
    if (profile == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 28,
          backgroundImage: profile.avatar != null ? doubanImageProvider(profile.avatar!) : null,
          child: profile.avatar == null ? Text(profile.name.isEmpty ? '?' : profile.name[0]) : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  OutlinedButton(
                    onPressed: _showSwitchUserDialog,
                    child: const Text('切换'),
                  ),
                ],
              ),
              Text('@${profile.id}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text('粉丝 ${profile.followersCount} · 关注 ${profile.followingCount}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typeSegmentedButton() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'book', label: Text('图书')),
        ButtonSegment(value: 'movie', label: Text('电影')),
        ButtonSegment(value: 'music', label: Text('音乐')),
      ],
      selected: {_type},
      onSelectionChanged: (selection) => _selectType(selection.first),
    );
  }

  Widget _statusChips() {
    return Wrap(
      spacing: 8,
      children: [
        for (final s in ['mark', 'doing', 'done'])
          ChoiceChip(
            label: Text(userStatusLabel(_type, s)),
            selected: _status == s,
            onSelected: (_) => _selectStatus(s),
          ),
      ],
    );
  }

  /// The content area below the filters: loading, error, empty, or
  /// the list. `footer` is appended after the last item.
  Widget _contentState({required Widget Function() listBuilder}) {
    final page = _page;
    if (_profileError != null && _profile == null) {
      return _errorContent('加载失败：$_profileError', _retryAll);
    }
    if (page.loading && page.items.isEmpty) return const LoadingList();
    if (page.items.isEmpty && _interestsError != null) {
      return _errorContent('加载收藏失败：$_interestsError', () => _loadInterests());
    }
    if (page.items.isEmpty) {
      return EmptyState(message: '该用户没有公开的${userStatusLabel(_type, _status)}条目');
    }
    return listBuilder();
  }

  Widget _errorContent(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(message: message),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _mobileView() {
    final page = _page;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _profileHeader(),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyHeaderDelegate(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _typeSegmentedButton(),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: _statusChips(),
          ),
        ),
        if (page.loading && page.items.isNotEmpty)
          const SliverToBoxAdapter(child: LinearProgressIndicator()),
        if (_profileError != null && _profile == null)
          SliverFillRemaining(child: _errorContent('加载失败：$_profileError', _retryAll))
        else if (page.loading && page.items.isEmpty)
          const SliverFillRemaining(child: LoadingList())
        else if (page.items.isEmpty && _interestsError != null)
          SliverFillRemaining(child: _errorContent('加载收藏失败：$_interestsError', () => _loadInterests()))
        else if (page.items.isEmpty)
          SliverFillRemaining(child: EmptyState(message: '该用户没有公开的${userStatusLabel(_type, _status)}条目'))
        else
          SliverList.builder(
            itemCount: page.items.length + 1,
            itemBuilder: (_, i) {
              if (i >= page.items.length) {
                return LoadMoreFooter(
                  countText: page.total > 0 ? '已加载 ${page.items.length} / ${page.total}' : null,
                  canLoadMore: () => !page.loading && page.items.length < page.total,
                  onLoadMore: () => _loadInterests(),
                );
              }
              return _interestRow(page.items[i]);
            },
          ),
      ],
    );
  }

  Widget _desktopView() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 320, child: _desktopSidebar()),
        const VerticalDivider(width: 1),
        Expanded(child: _desktopContent()),
      ],
    );
  }

  Widget _desktopSidebar() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _profileHeader(),
          const SizedBox(height: 20),
          const Text('类型', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            direction: Axis.vertical,
            segments: const [
              ButtonSegment(value: 'book', label: Text('图书')),
              ButtonSegment(value: 'movie', label: Text('电影')),
              ButtonSegment(value: 'music', label: Text('音乐')),
            ],
            selected: {_type},
            onSelectionChanged: (selection) => _selectType(selection.first),
          ),
          const SizedBox(height: 20),
          const Text('状态', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in ['mark', 'doing', 'done'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ChoiceChip(
                    label: Text(userStatusLabel(_type, s)),
                    selected: _status == s,
                    onSelected: (_) => _selectStatus(s),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _recentUsersSection(),
        ],
      ),
    );
  }

  Widget _desktopContent() {
    final page = _page;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                page.total > 0 ? '已加载 ${page.items.length} / ${page.total}' : '收藏',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.grid_view)),
                  ButtonSegment(value: true, icon: Icon(Icons.list)),
                ],
                selected: {_listView},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() => _listView = selection.first),
              ),
            ],
          ),
        ),
        if (page.loading && page.items.isNotEmpty) const LinearProgressIndicator(),
        Expanded(
          child: _contentState(
            listBuilder: () => _listView ? _desktopList(page) : _desktopGrid(page),
          ),
        ),
      ],
    );
  }

  Widget _desktopList(_InterestPage page) {
    return ListView.builder(
      itemCount: page.items.length + 1,
      itemBuilder: (_, i) {
        if (i >= page.items.length) {
          return LoadMoreFooter(
            countText: page.total > 0 ? '已加载 ${page.items.length} / ${page.total}' : null,
            canLoadMore: () => !page.loading && page.items.length < page.total,
            onLoadMore: () => _loadInterests(),
          );
        }
        return _interestRow(page.items[i]);
      },
    );
  }

  Widget _desktopGrid(_InterestPage page) {
    // Same poster-grid rule as Browse: row capped at 1440, columns
    // from a ~240 poster width, measured on the grid's own width
    // (it sits beside the 320 sidebar, so the window width would
    // over-count columns).
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth > Breakpoints.gridMaxWidth ? Breakpoints.gridMaxWidth : constraints.maxWidth;
        return CenteredWidth(
          maxWidth: Breakpoints.gridMaxWidth,
          child: GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: Breakpoints.posterColumns(contentWidth),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.68,
            ),
            itemCount: page.items.length + 1,
            itemBuilder: (_, i) {
              if (i >= page.items.length) {
                return LoadMoreFooter(
                  countText: page.total > 0 ? '已加载 ${page.items.length} / ${page.total}' : null,
                  canLoadMore: () => !page.loading && page.items.length < page.total,
                  onLoadMore: () => _loadInterests(),
                );
              }
              return SubjectPosterCard(
                subject: page.items[i].subject,
                onTap: () => _openSubject(page.items[i]),
              );
            },
          ),
        );
      },
    );
  }

  /// One interest row: cover, title, the user's own rating and date,
  /// and their comment (up to 2 lines). The plan's mobile mockup.
  Widget _interestRow(Interest interest) {
    final date = interest.createTime.length > 10 ? interest.createTime.substring(0, 10) : interest.createTime;
    final pic = subjectImageUrl(interest.subject, SettingsStore.instance.imageQuality);
    return Column(
      children: [
        InkWell(
          onTap: () => _openSubject(interest),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: pic == null || pic.isEmpty
                      ? Container(width: 56, height: 80, color: Theme.of(context).colorScheme.surfaceContainerHighest)
                      : CachedNetworkImage(
                          imageUrl: pic,
                          httpHeaders: doubanImageHeaders,
                          width: 56,
                          height: 80,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(width: 56, height: 80, color: Theme.of(context).colorScheme.surfaceContainerHighest),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(interest.subject.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (interest.rating != null) RatingText(rating: interest.rating!, community: false),
                          if (interest.rating != null && date.isNotEmpty) const SizedBox(width: 8),
                          if (date.isNotEmpty) Text(date, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      if (interest.comment.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(interest.comment, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Pinned header for the mobile type switch (SegmentedButton, 40
/// tall + 16 of vertical padding).
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: 56, child: child);
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) => oldDelegate.child != child;
}
