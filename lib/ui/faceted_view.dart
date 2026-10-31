import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Multi-dimensional tag search (多维筛选) for the movie / tv browse
/// filters, backed by Rexxar /{movie|tv}/tag.
///
/// One value per dimension (地区 / 类型 / 年代 / 特色) is joined
/// with commas into q; an empty q returns everything. The 形式
/// dimension is deliberately NOT offered: form values are not tags,
/// and sending one (e.g. 电视剧) returns 0 items (verified
/// 2026-10-31). The endpoint does not separate movie from tv
/// either (movie/tag and tv/tag return identical totals for the
/// same q), so results may mix forms; the browse category only
/// decides which endpoint path is called.
class FacetedView extends StatefulWidget {
  const FacetedView({super.key, required this.repository, required this.endpoint});

  final DoubanRepository repository;

  /// 'movie' or 'tv'.
  final String endpoint;

  @override
  State<FacetedView> createState() => _FacetedViewState();
}

class _FacetedViewState extends State<FacetedView> {
  List<TagGroup> _groups = const [];
  List<TagSort> _sorts = const [];
  final _selected = <String, String>{};
  String _sort = 'U';
  bool _playable = false;
  final _items = <Subject>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _search(reset: true);
  }

  String get _q => _selected.values.join(',');

  List<TagGroup> get _selectableGroups =>
      _groups.where((g) => g.type != '形式').toList();

  Future<void> _search({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _items.clear();
        _total = 0;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final result = await widget.repository.fetchTagSearch(
        widget.endpoint,
        q: _q,
        sort: _sort,
        playable: _playable,
        start: reset ? 0 : _items.length,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        if (_groups.isEmpty) _groups = result.groups;
        if (_sorts.isEmpty) _sorts = result.sorts;
        if (reset) {
          _items.clear();
        }
        _items.addAll(result.items);
        _total = result.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
        _loadingMore = false;
      });
      if (!reset && _items.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载更多失败')),
        );
      }
    }
  }

  void _select(String groupType, String? value) {
    setState(() {
      if (value == null) {
        _selected.remove(groupType);
      } else {
        _selected[groupType] = value;
      }
    });
    _search(reset: true);
  }

  Widget _chipRow(String label, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 44,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _chipRow(
                '排序',
                [
                  for (final sort in _sorts)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(sort.text),
                        selected: _sort == sort.name,
                        onSelected: (_) {
                          if (_sort == sort.name) return;
                          setState(() => _sort = sort.name);
                          _search(reset: true);
                        },
                      ),
                    ),
                ],
              ),
              Row(
                children: [
                  const Text('仅看可播放', style: TextStyle(fontWeight: FontWeight.bold)),
                  Switch(
                    value: _playable,
                    onChanged: (value) {
                      setState(() => _playable = value);
                      _search(reset: true);
                    },
                  ),
                ],
              ),
              for (final group in _selectableGroups)
                _chipRow(
                  group.type,
                  [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('全部'),
                        selected: !_selected.containsKey(group.type),
                        onSelected: (_) => _select(group.type, null),
                      ),
                    ),
                    for (final value in group.values)
                      if (!value.startsWith('全部'))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(value),
                            selected: _selected[group.type] == value,
                            onSelected: (_) => _select(
                              group.type,
                              _selected[group.type] == value ? null : value,
                            ),
                          ),
                        ),
                  ],
                ),
              const Text(
                '注：筛选结果可能混有电影与剧集形式，形式维度暂不支持单选。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('筛选加载失败'),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => _search(reset: true),
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : _items.isEmpty
                      ? const Center(child: Text('没有符合条件的条目'))
                      : ListView.builder(
                          itemCount: _items.length + 1,
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              final done = _total > 0 && _items.length >= _total;
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: done
                                      ? Text('已全部加载（${_items.length} / $_total）')
                                      : _loadingMore
                                          ? const CircularProgressIndicator()
                                          : OutlinedButton(
                                              onPressed: () => _search(reset: false),
                                              child: Text('加载更多（${_items.length} / $_total）'),
                                            ),
                                ),
                              );
                            }
                            final subject = _items[i];
                            return SubjectRow(
                              subject: subject,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => SubjectPage(
                                      repository: widget.repository,
                                      type: subject.type,
                                      id: subject.id,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
        ),
      ],
    );
  }
}
