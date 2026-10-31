import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'faceted_view.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// The 推荐 category view: the recommendation sections that used to
/// live on the Discover page, stacked vertically. Each section is a
/// horizontal poster row; its 更多 button switches Browse itself to
/// that section's category/filter (no extra page is pushed).
class _RecommendSections extends StatelessWidget {
  const _RecommendSections({
    required this.repository,
    required this.onOpenSection,
    required this.onOpenSubject,
  });

  final DoubanRepository repository;
  final void Function(HomeSection section) onOpenSection;
  final void Function(Subject subject) onOpenSubject;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<HomeSection>>(
      future: repository.fetchHomeSections(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingList();
        }
        if (snapshot.hasError) {
          return EmptyState(message: '加载失败：${snapshot.error}');
        }
        final sections = snapshot.data ?? const [];
        if (sections.isEmpty) return const EmptyState(message: '暂无推荐内容');
        return ListView(
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
                    onPressed: () => onOpenSection(section),
                    child: const Text('更多 >'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: section.items.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(
                    width: 120,
                    child: SubjectPosterCard(
                      subject: section.items[i],
                      onTap: () => onOpenSubject(section.items[i]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        );
      },
    );
  }
}

/// Browse by category + filter, paged. "正在热映" is a movie filter here,
/// not on the home page. Switching category/filter resets the list;
/// "加载更多" appends until items reach the API total.
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
  String? _error;

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
    // The 推荐 category and the 多维筛选 filter do not use
    // fetchBrowse at all; they render their own views, which drive
    // their own searches.
    if (_category == 'recommend') {
      setState(() {
        _loading = false;
        _error = null;
        _items = [];
        _total = 0;
      });
      return;
    }
    if (_filter == 'filter') {
      setState(() {
        _loading = false;
        _error = null;
        _items = [];
        _total = 0;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
      _total = 0;
    });
    try {
      final result = await widget.repository.fetchBrowse(_category, _filter, start: 0, count: 20);
      if (mounted) {
        setState(() {
          _items = result.items;
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
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchBrowse(_category, _filter, start: _items.length, count: 20);
      if (mounted) {
        setState(() {
          _items = [..._items, ...result.items];
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
          child: Wrap(
            spacing: 8,
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
            child: Wrap(
              spacing: 8,
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
                            final isGrid = constraints.maxWidth >= 600;
                            final columns = constraints.maxWidth >= 1440 ? 5 : 4;
                            return Column(
                              children: [
                                Expanded(
                                  child: isGrid
                                      ? GridView.builder(
                                          padding: const EdgeInsets.all(24),
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
                                        )
                                      : ListView.builder(
                                          itemCount: _items.length,
                                          itemBuilder: (_, i) => SubjectRow(
                                            subject: _items[i],
                                            onTap: () => _openSubject(_items[i]),
                                          ),
                                        ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      if (_total > 0) Text('已加载 ${_items.length} / $_total'),
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
                          },
                        ),
        ),
      ],
    );
  }
}
