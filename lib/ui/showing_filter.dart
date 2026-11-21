import 'package:flutter/material.dart';

import '../data/cities.dart';
import 'widgets.dart';

/// Filter values for the movie/showing list. The server filters
/// (sort/playable/scoreRange) go to fetchMovieShowing; the area
/// filter runs client-side (subjectMatchesArea) because the Rexxar
/// endpoint ignores the area parameter (verified 2026-11-21).
class ShowingFilters {
  const ShowingFilters({
    this.cityId,
    this.area = '全部',
    this.sort = 'recommend',
    this.playable = false,
    this.scoreMin = 0,
  });

  /// Null = no city chosen: the existing national list is shown
  /// with a prompt to pick a city.
  final int? cityId;
  final String area;
  final String sort;
  final bool playable;

  /// Minimum score (0 = 全部, else 6/7/8/9); the max is always 10.
  final int scoreMin;

  ShowingFilters copyWith({
    int? cityId,
    bool clearCity = false,
    String? area,
    String? sort,
    bool? playable,
    int? scoreMin,
  }) =>
      ShowingFilters(
        cityId: clearCity ? null : (cityId ?? this.cityId),
        area: area ?? this.area,
        sort: sort ?? this.sort,
        playable: playable ?? this.playable,
        scoreMin: scoreMin ?? this.scoreMin,
      );

  /// The server score_range ("min,10"), or null for the full range.
  String? get scoreRange => scoreMin > 0 ? '$scoreMin,10' : null;

  String get cityName =>
      cityId == null ? '选择城市' : (showingCityById(cityId!)?.name ?? '未知城市');
}

const showingAreas = <String>['全部', '华语', '欧美', '韩国', '日本'];
const showingSorts = <(String, String)>[
  ('recommend', '热度'),
  ('time', '最新'),
  ('rank', '评分'),
];
const showingScoreOptions = <(int, String)>[
  (0, '全部'),
  (9, '9分以上'),
  (8, '8分以上'),
  (7, '7分以上'),
  (6, '6分以上'),
];

/// The showing filter bar. Wide layout: the four dropdown chips
/// and the playable chip in one horizontal row, with the filtered
/// count ("共 N 部") at the end. Compact layout: a single 筛选
/// button (labelled with the current city) that opens a bottom
/// sheet; selections are staged in the sheet and applied on 应用.
class ShowingFilterBar extends StatelessWidget {
  const ShowingFilterBar({
    super.key,
    required this.filters,
    required this.compact,
    required this.total,
    required this.onChanged,
  });

  final ShowingFilters filters;
  final bool compact;
  final int total;
  final ValueChanged<ShowingFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final button = OutlinedButton.icon(
        onPressed: () => _openSheet(context),
        icon: const Icon(Icons.tune, size: 18),
        label: Text('筛选 · ${filters.cityName}'),
      );
      return Row(children: [
        button,
        const SizedBox(width: 12),
        if (filters.cityId != null)
          Text('共 $total 部', style: const TextStyle(fontWeight: FontWeight.bold)),
      ]);
    }
    return HScrollRow(children: [
      _dropdownChip(context, '城市', filters.cityId, [
        const MapEntry<int?, String>(null, '不选城市'),
        for (final city in showingCities) MapEntry<int?, String>(city.locId, city.name),
      ], (value) => onChanged(filters.copyWith(cityId: value, clearCity: value == null))),
      _dropdownChip(context, '地区', filters.area, [
        for (final area in showingAreas) MapEntry<String, String>(area, area),
      ], (value) => onChanged(filters.copyWith(area: value))),
      _dropdownChip(context, '排序', filters.sort, [
        for (final sort in showingSorts) MapEntry<String, String>(sort.$1, sort.$2),
      ], (value) => onChanged(filters.copyWith(sort: value))),
      _dropdownChip(context, '评分', filters.scoreMin, [
        for (final option in showingScoreOptions) MapEntry<int, String>(option.$1, option.$2),
      ], (value) => onChanged(filters.copyWith(scoreMin: value))),
      FilterChip(
        label: const Text('仅看可播放'),
        selected: filters.playable,
        onSelected: (value) => onChanged(filters.copyWith(playable: value)),
      ),
      if (filters.cityId != null) ...[
        const SizedBox(width: 12),
        Text('共 $total 部', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ]);
  }

  /// One filter as a compact dropdown chip: bold label + the
  /// current value, bordered like a chip (same shape as the
  /// faceted view's dropdown chips).
  Widget _dropdownChip<T>(BuildContext context, String label, T value, List<MapEntry<T, String>> options, ValueChanged<T> onChanged) {
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
            child: DropdownButton<T>(
              value: options.any((o) => o.key == value) ? value : options.first.key,
              items: [
                for (final option in options)
                  DropdownMenuItem<T>(
                    value: option.key,
                    child: Text(option.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSheet(BuildContext context) async {
    final result = await showModalBottomSheet<ShowingFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: _ShowingFilterSheet(initial: filters),
      ),
    );
    if (result == null) return;
    onChanged(result);
  }
}

/// Bottom-sheet filter picker for narrow screens: one section per
/// dimension, each as a row of ChoiceChips. Changes stay in local
/// state until 应用; 重置 restores the defaults.
class _ShowingFilterSheet extends StatefulWidget {
  const _ShowingFilterSheet({required this.initial});

  final ShowingFilters initial;

  @override
  State<_ShowingFilterSheet> createState() => _ShowingFilterSheetState();
}

class _ShowingFilterSheetState extends State<_ShowingFilterSheet> {
  late ShowingFilters _staged;

  @override
  void initState() {
    super.initState();
    _staged = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      AppBar(
        title: const Text('筛选'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => setState(() => _staged = const ShowingFilters()),
            child: const Text('重置'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_staged),
            child: const Text('应用'),
          ),
        ],
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _section('城市', [
            ChoiceChip(
              label: const Text('不选城市'),
              selected: _staged.cityId == null,
              onSelected: (_) => setState(() => _staged = _staged.copyWith(clearCity: true)),
            ),
            for (final city in showingCities)
              ChoiceChip(
                label: Text(city.name),
                selected: _staged.cityId == city.locId,
                onSelected: (_) => setState(() => _staged = _staged.copyWith(cityId: city.locId)),
              ),
          ]),
          _section('地区', [
            for (final area in showingAreas)
              ChoiceChip(
                label: Text(area),
                selected: _staged.area == area,
                onSelected: (_) => setState(() => _staged = _staged.copyWith(area: area)),
              ),
          ]),
          _section('排序', [
            for (final sort in showingSorts)
              ChoiceChip(
                label: Text(sort.$2),
                selected: _staged.sort == sort.$1,
                onSelected: (_) => setState(() => _staged = _staged.copyWith(sort: sort.$1)),
              ),
          ]),
          _section('评分', [
            for (final option in showingScoreOptions)
              ChoiceChip(
                label: Text(option.$2),
                selected: _staged.scoreMin == option.$1,
                onSelected: (_) => setState(() => _staged = _staged.copyWith(scoreMin: option.$1)),
              ),
          ]),
          _section('播放', [
            FilterChip(
              label: const Text('仅看可播放'),
              selected: _staged.playable,
              onSelected: (value) => setState(() => _staged = _staged.copyWith(playable: value)),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _section(String title, List<Widget> chips) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ]),
    );
  }
}
