import 'package:flutter/material.dart';

import 'breakpoints.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'faceted_view.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// The 推荐 category view: the recommendation sections that used to
/// live on the Discover page, stacked vertically. Each section is a
/// horizontal poster row; its 更多 button switches Browse itself to
/// that section's category/filter (no extra page is pushed).
///
/// Stateful so the sections future is created once in initState:
/// as a StatelessWidget it was created in build, and the shell's
/// LayoutBuilder rebuilds the whole tab on every resize, so every
/// window drag re-fetched the sections and flashed the spinner.
class _RecommendSections extends StatefulWidget {
  const _RecommendSections({
    required this.repository,
    required this.onOpenSection,
    required this.onOpenSubject,
  });

  final DoubanRepository repository;
  final void Function(HomeSection section) onOpenSection;
  final void Function(Subject subject) onOpenSubject;

  @override
  State<_RecommendSections> createState() => _RecommendSectionsState();
}

class _RecommendSectionsState extends State<_RecommendSections> {
  late Future<List<HomeSection>> _future = widget.repository.fetchHomeSections();

  @override
  void didUpdateWidget(covariant _RecommendSections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _future = widget.repository.fetchHomeSections();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HomeSection>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingList();
        }
        if (snapshot.hasError) {
          return EmptyState(message: '加载失败：${snapshot.error}');
        }
        final sections = snapshot.data ?? const [];
        if (sections.isEmpty) return const EmptyState(message: '暂无推荐内容');
        return CenteredWidth(
          maxWidth: Breakpoints.gridMaxWidth,
          child: ListView(
            padding: const EdgeInsets.all(16),
          children: [
            for (final section in sections) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onOpenSection(section),
                    child: const Text('更多 >'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                // HScrollRow: mouse drag + desktop scrollbar + arrows.
                // The global scroll behavior (main.dart) covers drag
                // for plain rows too, but the arrows and scrollbar
                // live here. No own padding: the outer ListView
                // already pads 16.
                child: HScrollRow(
                  spacing: 12,
                  children: [
                    for (final item in section.items)
                      SizedBox(
                        width: 120,
                        child: SubjectPosterCard(
                          subject: item,
                          onTap: () => widget.onOpenSubject(item),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        )
        );
      },
    );
  }
}

/// Browse by category + filter, paged. "正在热映" is a movie filter here,
/// not on the home page. Switching category/filter resets the list;
/// scrolling near the bottom auto-loads more until items reach the
/// API total (LoadMoreFooter, no button).
class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key, required this.repository, this.initialCategory, this.initialFilter});

  final DoubanRepository repository;
  final String? initialCategory;
  final String? initialFilter;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  static const _categories = ['recommend', 'movie', 'tv', 'book', 'music', 'show'];

  late String _category;
  late String _filter;
  List<Subject> _items = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  String? _error;

  /// Sequence of the currently valid request: bumping it in _load
  /// invalidates every in-flight request, so a slow old response
  /// can never overwrite a newer list.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _category = _categories.contains(widget.initialCategory) ? widget.initialCategory! : 'recommend';
    if (_category == 'recommend') {
      // The 推荐 category renders the sections view, which drives
      // its own fetchHomeSections; there is no filter or list load.
      _filter = '';
      _loading = false;
      return;
    }
    final filters = browseFilters[_category]!;
    _filter = filters.any((f) => f.id == widget.initialFilter) ? widget.initialFilter! : filters.first.id;
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq; // any older request is invalid from here on
    // The 推荐 category and the 多维筛选 filter do not use
    // fetchBrowse at all; they render their own views, which drive
    // their own searches.
    if (_category == 'recommend' || _filter == 'filter') {
      setState(() {
        _loading = false;
        _error = null;
        _items = [];
        _total = 0;
        _loadingMore = false;
        _loadMoreFailed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
      _total = 0;
      _loadingMore = false;
      _loadMoreFailed = false;
    });
    try {
      final result = await widget.repository.fetchBrowse(_category, _filter, start: 0, count: 20);
      if (!mounted || seq != _seq) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _loading = false;
      });
    } catch (e) {
      debugPrint('browse load failed: $e');
      if (!mounted || seq != _seq) return;
      // No finally block: an old request must not be able to turn
      // _loading back off after a newer one started.
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    final seq = _seq;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final result = await widget.repository.fetchBrowse(_category, _filter, start: _items.length, count: 20);
      if (!mounted || seq != _seq) return; // category changed meanwhile: drop it
      setState(() {
        _items = [..._items, ...result.items];
        if (result.total > 0) _total = result.total;
        // An empty page with items still outstanding means the
        // list is exhausted; without this the auto-load footer
        // below would re-trigger forever.
        if (result.items.isEmpty) _total = _items.length;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('browse loadMore failed: $e');
      if (!mounted || seq != _seq) return;
      // No SnackBar: the footer's retry button takes over.
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  void _selectCategory(String category) {
    if (category == _category) return;
    setState(() {
      _category = category;
      _filter = category == 'recommend' ? '' : browseFilters[category]!.first.id;
    });
    _load();
  }

  /// A section's 更多 button: switch Browse itself to that section's
  /// category/filter instead of pushing another page.
  void _openSection(HomeSection section) {
    setState(() {
      _category = section.category;
      _filter = section.filter;
    });
    _load();
  }

  void _selectFilter(String filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _load();
  }

  void _openSubject(Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectPage(repository: widget.repository, type: subject.type, id: subject.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filters = browseFilters[_category]!;
    final hasMore = _total > 0 && _items.length < _total;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: HScrollRow(
            children: [
              for (final c in _categories)
                ChoiceChip(
                  label: Text(browseCategoryLabels[c]!),
                  selected: _category == c,
                  onSelected: (_) => _selectCategory(c),
                ),
            ],
          ),
        ),
        if (_category != 'recommend')
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: HScrollRow(
              children: [
                for (final f in filters)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f.id,
                    onSelected: (_) => _selectFilter(f.id),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _category == 'recommend'
              ? _RecommendSections(
                  repository: widget.repository,
                  onOpenSection: _openSection,
                  onOpenSubject: _openSubject,
                )
              : _filter == 'filter'
              ? FacetedView(
                  key: ValueKey(_category),
                  repository: widget.repository,
                  endpoint: _category,
                )
              : _loading
                  ? const LoadingList()
                  : _error != null
                      ? EmptyState(message: '加载失败：$_error')
                      : _items.isEmpty
                          ? const EmptyState(message: '该分类暂无内容')
                          : LayoutBuilder(
                          builder: (context, constraints) {
                            final isGrid = Breakpoints.of(constraints.maxWidth) != WindowSize.compact;
                            // Desktop poster grid: cap the row at 1440 and
                            // derive the column count from a ~240 poster
                            // width (c001apk's card columns derive from a
                            // fixed card width the same way), instead of
                            // stretching 4-5 posters across any window.
                            final contentWidth = constraints.maxWidth > Breakpoints.gridMaxWidth ? Breakpoints.gridMaxWidth : constraints.maxWidth;
                            final columns = Breakpoints.posterColumns(contentWidth);
                            final footer = LoadMoreFooter(
                              countText: _total > 0 ? '已加载 ${_items.length} / $_total' : null,
                              failed: _loadMoreFailed,
                              canLoadMore: () => !_loadingMore && hasMore,
                              onLoadMore: _loadMore,
                            );
                            return CenteredWidth(
                              maxWidth: Breakpoints.gridMaxWidth,
                              child: isGrid
                                  ? CustomScrollView(
                                      slivers: [
                                        SliverPadding(
                                          padding: const EdgeInsets.all(24),
                                          sliver: SliverGrid.builder(
                                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: columns,
                                              mainAxisSpacing: 16,
                                              crossAxisSpacing: 16,
                                              childAspectRatio: 0.68,
                                            ),
                                            itemCount: _items.length,
                                            itemBuilder: (_, i) => SubjectPosterCard(
                                              subject: _items[i],
                                              onTap: () => _openSubject(_items[i]),
                                            ),
                                          ),
                                        ),
                                        SliverToBoxAdapter(child: footer),
                                      ],
                                    )
                                  : ListView.builder(
                                      itemCount: _items.length + 1,
                                      itemBuilder: (_, i) {
                                        if (i >= _items.length) return footer;
                                        return SubjectRow(
                                          subject: _items[i],
                                          onTap: () => _openSubject(_items[i]),
                                        );
                                      },
                                    ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
