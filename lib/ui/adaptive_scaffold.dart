import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/repository.dart';
import 'browse_page.dart';
import 'group_page.dart';
import 'home_page.dart';
import 'rankings_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'user_page.dart';

/// Navigator key for the whole app (main.dart passes it to
/// MaterialApp). Global shortcuts need it because their Actions run
/// above the Navigator, where Navigator.of(context) cannot see it.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Which tab the shell is showing (0 = Discover). Kept in sync by
/// the shell; Ctrl/Cmd+R only refreshes when it is 0.
final currentTab = ValueNotifier<int>(0);

/// Ticked to refresh the Discover feed: the desktop top-bar button,
/// Ctrl/Cmd+R, and HomePage's feed all use this one notifier. It
/// lives for the app's lifetime, so it is never disposed.
final discoverRefresh = ValueNotifier<int>(0);

bool _searchOpen = false;

/// Opens the search page, unless one is already open (the '/' key
/// would otherwise stack a second search page on top).
void openSearchPage(DoubanRepository repository) {
  if (_searchOpen) return;
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  _searchOpen = true;
  navigator
      .push(
        MaterialPageRoute(
          builder: (_) => SearchPage(repository: repository),
        ),
      )
      .then((_) => _searchOpen = false);
}

/// Ctrl/Cmd+R: refreshes the Discover feed, but only while Discover
/// is the current tab (other tabs have nothing to refresh this way).
void requestDiscoverRefresh() {
  if (currentTab.value == 0) discoverRefresh.value++;
}

/// One shell for both form factors:
///   width < 600  -> bottom navigation
///   width >= 600 -> NavigationRail (72 narrow, 240 extended on desktop)
/// Pages themselves only receive the repository; they do not branch
/// on width except for grid density / master-detail, which is local.
class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({super.key, required this.repository});

  final DoubanRepository repository;

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  int _index = 0;

  void _selectDestination(int i) {
    setState(() => _index = i);
    currentTab.value = i;
  }

  static const _labels = ['发现', '书影音', '排行榜', '小组', '我的'];
  static const _icons = [
    Icons.explore_outlined,
    Icons.movie_outlined,
    Icons.leaderboard_outlined,
    Icons.group_outlined,
    Icons.person_outlined,
  ];

  Widget _pageFor(int index) {
    switch (index) {
      case 1:
        return BrowsePage(repository: widget.repository);
      case 2:
        return RankingsPage(repository: widget.repository);
      case 3:
        return GroupPage(repository: widget.repository);
      case 4:
        return UserPage(repository: widget.repository);
      case 0:
      default:
        return HomePage(repository: widget.repository, refreshListenable: discoverRefresh);
    }
  }

  /// One page per tab, created on first visit and kept alive: the
  /// old `_pageFor(_index)` rebuilt the page on every tab switch,
  /// losing scroll position and all loaded content. Note the pages
  /// still rebuild when the width crosses 600 (the mobile Scaffold
  /// and the desktop Row are different subtrees); keeping state
  /// across that would need a KeyedSubtree with a GlobalKey, which
  /// the plan marks optional and is not done here.
  final List<Widget?> _pages = List.filled(5, null);

  Widget _body() {
    _pages[_index] ??= _pageFor(_index);
    return IndexedStack(
      index: _index,
      children: [for (final p in _pages) p ?? const SizedBox.shrink()],
    );
  }

  void _openSearch() {
    openSearchPage(widget.repository);
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = Breakpoints.of(constraints.maxWidth) == WindowSize.compact;
        final body = _body();
        if (isMobile) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('douya · 访客'),
              actions: [
                IconButton(icon: const Icon(Icons.search), onPressed: _openSearch),
                IconButton(icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
              ],
            ),
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectDestination,
              destinations: [
                for (var i = 0; i < _labels.length; i++)
                  NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
              ],
            ),
          );
        }
        final extended = constraints.maxWidth >= Breakpoints.extendedRail;
        // Short windows (landscape phones, ~360 high): five labelled
        // destinations plus the leading title overflow the rail by
        // ~28px, so show icons only. Found by the layout tests
        // (task 7); this is task 6's rail-height step, done early.
        // The leading's own vertical padding is also dropped at
        // short heights (new plan, task 8) to give the icons room.
        final shortHeight = constraints.maxHeight < 480;
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                extended: extended,
                selectedIndex: _index,
                onDestinationSelected: _selectDestination,
                labelType: extended || shortHeight ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                leading: shortHeight
                    ? const Text('douya', style: TextStyle(fontWeight: FontWeight.bold))
                    : const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text('douya', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                destinations: [
                  for (var i = 0; i < _labels.length; i++)
                    NavigationRailDestination(icon: Icon(_icons[i]), label: Text(_labels[i])),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: TextField(
                                readOnly: true,
                                onTap: _openSearch,
                                decoration: const InputDecoration(
                                  hintText: '搜索电影、图书、音乐、小组…',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.all(Radius.circular(999)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Chip(label: Text('访客模式')),
                          if (_index == 0) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.refresh),
                              tooltip: '刷新',
                              onPressed: () => discoverRefresh.value++,
                            ),
                          ],
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.settings_outlined),
                            tooltip: '设置',
                            onPressed: _openSettings,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
