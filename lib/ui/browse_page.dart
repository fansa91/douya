import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

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
  static const _categories = ['movie', 'tv', 'book', 'music'];

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
    _category = _categories.contains(widget.initialCategory) ? widget.initialCategory! : 'movie';
    final filters = browseFilters[_category]!;
    _filter = filters.any((f) => f.id == widget.initialFilter) ? widget.initialFilter! : filters.first.id;
    _load();
  }

  Future<void> _load() async {
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
      _filter = browseFilters[category]!.first.id;
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
          child: _loading
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
