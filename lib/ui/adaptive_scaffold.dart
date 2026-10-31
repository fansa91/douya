import 'package:flutter/material.dart';

import '../data/repository.dart';
import 'browse_page.dart';
import 'group_page.dart';
import 'home_page.dart';
import 'rankings_page.dart';
import 'search_page.dart';
import 'settings_page.dart';
import 'user_page.dart';

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
        return HomePage(repository: widget.repository);
    }
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SearchPage(repository: widget.repository)),
    );
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
        final isMobile = constraints.maxWidth < 600;
        final body = _pageFor(_index);
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
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (var i = 0; i < _labels.length; i++)
                  NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
              ],
            ),
          );
        }
        final extended = constraints.maxWidth >= 1024;
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                extended: extended,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                leading: const Padding(
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
