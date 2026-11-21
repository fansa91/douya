import 'package:flutter/material.dart';

import 'breakpoints.dart';
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
  const FacetedView({super.key, required this.repository, required this.endpoint, this.initialSelection = const {}});

  final DoubanRepository repository;

  /// 'movie' or 'tv'.
  final String endpoint;

  /// Preselected dimension values (group type -> value), e.g. from a
  /// landing chip: {'类型': '喜剧'}. A key need not match a tag-search
  /// dimension (播出平台 has none); such a value still goes into the
  /// query and renders as its own dropdown / deletable chip.
  final Map<String, String> initialSelection;

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
    _selected.addAll(widget.initialSelection);
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
        if (!reset && result.items.isEmpty) _total = _items.length;
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

  /// One filter as a compact dropdown chip for the horizontal
  /// filter row: bold label + the current value, bordered like a
  /// chip. [options] are (value, display) pairs; a null value
  /// means 全部. (Previously each filter was a full-width labeled
  /// row; the rows stacked to a full screen before the results.)
  Widget _dropdownChip(String label, String? value, List<MapEntry<String?, String>> options, ValueChanged<String?> onChanged) {
    // No outer padding: the HScrollRow supplies the 8 gap between chips.
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: options.any((o) => o.key == value) ? value : null,
              hint: const Text('全部'),
              items: [
                for (final option in options)
                  DropdownMenuItem<String?>(
                    value: option.key,
                    child: Text(option.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// Wide layout: the sort + dimension dropdown chips and the
  /// playable switch in one horizontal row (HScrollRow gives it mouse
  /// drag, scrollbar and arrows on desktop).
  Widget _horizontalFilters() {
    return HScrollRow(
      children: [
        _dropdownChip(
          '排序',
          _sort,
          [for (final sort in _sorts) MapEntry(sort.name, sort.text)],
          (value) {
            if (value == null || value == _sort) return;
            setState(() => _sort = value);
            _search(reset: true);
          },
        ),
        for (final group in _selectableGroups)
          _dropdownChip(
            group.type,
            _selected[group.type],
            [
              const MapEntry<String?, String>(null, '全部'),
              for (final value in group.values)
                if (!value.startsWith('全部')) MapEntry<String?, String>(value, value),
            ],
            (value) => _select(group.type, value),
          ),
        // Selected keys the tag search has no dimension for (e.g.
        // 播出平台 from a landing chip): they still filter the query,
        // so they get their own dropdown (全部 clears them). Gated on
        // _groups so real groups are not doubled before the first
        // search returns.
        if (_groups.isNotEmpty)
          for (final entry in _selected.entries)
            if (!_groups.any((g) => g.type == entry.key))
              _dropdownChip(
                entry.key,
                entry.value,
                [const MapEntry<String?, String>(null, '全部'), MapEntry<String?, String>(entry.value, entry.value)],
                (value) => _select(entry.key, value),
              ),
        Row(
          mainAxisSize: MainAxisSize.min,
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Narrow content (<600, the shell's mobile split) gets the
        // bottom-sheet filter UI; wider content keeps the horizontal
        // dropdown-chip row. Measured on this view's own width, not
        // the window, because the shell rail takes 72/240 off it.
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = Breakpoints.of(constraints.maxWidth) == WindowSize.compact;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact) _compactFilters() else _horizontalFilters(),
                  Text(
                    '注：筛选结果可能混有电影与剧集形式，形式维度暂不支持单选。',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          },
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
                      : CenteredWidth(
                          child: ListView.builder(
                            itemCount: _items.length + 1,
                          itemBuilder: (context, i) {
                            if (i == _items.length) {
                              final done = _total > 0 && _items.length >= _total;
                              return LoadMoreFooter(
                                countText: '已加载 ${_items.length} / $_total',
                                canLoadMore: () => !_loadingMore && !done,
                                onLoadMore: () => _search(reset: false),
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
        ),
      ],
    );
  }

  /// Narrow layout: one row with the filter button (badged with the
  /// number of active conditions), the playable switch, and the
  /// selected conditions as deletable chips underneath. The five
  /// dropdowns move into a bottom sheet instead of crowding this row.
  Widget _compactFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _filterButton(),
            const Spacer(),
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
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _selected.entries)
                Chip(
                  label: Text('${entry.key}：${entry.value}'),
                  onDeleted: () => _select(entry.key, null),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _filterButton() {
    final count = _selected.length + (_sort != 'U' ? 1 : 0);
    final button = OutlinedButton.icon(
      onPressed: _openFilterSheet,
      icon: const Icon(Icons.tune, size: 18),
      label: const Text('筛选'),
    );
    if (count == 0) return button;
    return Badge(label: Text('$count'), child: button);
  }

  /// Opens the filter sheet. Selections are staged inside the sheet
  /// and only applied (and refetched) when the user taps 应用;
  /// dismissing the sheet discards them.
  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: _FilterSheet(
          sorts: _sorts,
          groups: _selectableGroups,
          initialSelected: _selected,
          initialSort: _sort,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(result.selected);
      _sort = result.sort;
    });
    _search(reset: true);
  }
}

/// What the filter sheet returns when the user taps 应用; null when
/// the sheet is dismissed without applying.
class _FilterResult {
  const _FilterResult({required this.selected, required this.sort});

  final Map<String, String> selected;
  final String sort;
}

/// Bottom-sheet filter picker for narrow screens: sort + one section
/// per dimension, each as a row of ChoiceChips (全部 + values).
/// Changes stay in local state until 应用; 重置 only clears the
/// staged state, it does not refetch by itself.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.sorts,
    required this.groups,
    required this.initialSelected,
    required this.initialSort,
  });

  final List<TagSort> sorts;
  final List<TagGroup> groups;
  final Map<String, String> initialSelected;
  final String initialSort;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Map<String, String> _selected;
  late String _sort;

  @override
  void initState() {
    super.initState();
    _selected = Map.of(widget.initialSelected);
    _sort = widget.initialSort;
  }

  void _reset() {
    setState(() {
      _selected.clear();
      _sort = 'U';
    });
  }

  Widget _section(String label, List<MapEntry<String?, String>> options, String? value, ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option.value),
                  selected: value == option.key,
                  onSelected: (_) => onChanged(option.key),
                ),
            ],
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Text('筛选', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section(
                '排序',
                [for (final sort in widget.sorts) MapEntry(sort.name, sort.text)],
                _sort,
                (value) {
                  if (value == null) return;
                  setState(() => _sort = value);
                },
              ),
              for (final group in widget.groups)
                _section(
                  group.type,
                  [
                    const MapEntry<String?, String>(null, '全部'),
                    for (final value in group.values)
                      if (!value.startsWith('全部')) MapEntry<String?, String>(value, value),
                  ],
                  _selected[group.type],
                  (value) {
                    setState(() {
                      if (value == null) {
                        _selected.remove(group.type);
                      } else {
                        _selected[group.type] = value;
                      }
                    });
                  },
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              TextButton(onPressed: _reset, child: const Text('重置')),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(
                  _FilterResult(selected: _selected, sort: _sort),
                ),
                child: const Text('应用'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
