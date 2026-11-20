import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/settings.dart';
import '../models/models.dart';
import 'breakpoints.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Rankings (排行榜) shell page: one board category at a time
/// (影视 / 音乐 / 图书 / 游戏, numeric tag ids from the boards API),
/// each board opening a paged, ranked item list.
class RankingsPage extends StatefulWidget {
  const RankingsPage({super.key, required this.repository});

  final DoubanRepository repository;

  @override
  State<RankingsPage> createState() => _RankingsPageState();
}

class _RankingsPageState extends State<RankingsPage> {
  String _tagId = '49';
  List<RankBoard> _boards = const [];
  bool _loading = true;
  Object? _error;

  /// Sequence of the currently valid request: switching categories
  /// quickly must not let a slow old response overwrite the new one.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await widget.repository.fetchRankBoards(_tagId);
      if (!mounted || seq != _seq) return;
      setState(() {
        _boards = boards;
        _loading = false;
      });
    } catch (e) {
      debugPrint('rank boards failed: $e');
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _selectCategory(String tagId) {
    if (tagId == _tagId) return;
    setState(() => _tagId = tagId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return CenteredWidth(
      maxWidth: Breakpoints.gridMaxWidth,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final e in rankBoardCategories.entries)
                      ButtonSegment(value: e.key, label: Text(e.value)),
                  ],
                  selected: {_tagId},
                  onSelectionChanged: (s) => _selectCategory(s.first),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingList()
                : _error != null
                    ? RetryState(message: '榜单加载失败', onRetry: _load)
                    : _boards.isEmpty
                        ? const Center(child: Text('该分类暂无榜单'))
                        : CustomScrollView(slivers: [
                            SliverLayoutBuilder(builder: (context, c) {
                              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                              final spec = _BoardGridSpec.fit(c.crossAxisExtent - 32, scale);
                              final unit = rankBoardUnits[_tagId] ?? '个';
                              return SliverPadding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                                sliver: SliverGrid.builder(
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: spec.columns,
                                    mainAxisSpacing: 12,
                                    crossAxisSpacing: 12,
                                    mainAxisExtent: spec.cardHeight,
                                  ),
                                  itemCount: _boards.length,
                                  itemBuilder: (context, i) => _BoardCard(
                                    board: _boards[i],
                                    unit: unit,
                                    posterWidth: spec.posterWidth,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => BoardDetailPage(
                                            repository: widget.repository,
                                            board: _boards[i],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            }),
                          ]),
          ),
        ],
      ),
    );
  }
}

class _BoardGridSpec {
  const _BoardGridSpec(this.columns, this.posterWidth, this.cardHeight);
  final int columns;
  final double posterWidth;
  final double cardHeight;

  factory _BoardGridSpec.fit(double available, double textScale) {
    const gap = 12.0, target = 320.0, inner = 12.0;
    final cols = ((available + gap) / (target + gap)).floor().clamp(1, 4);
    final cardW = (available - gap * (cols - 1)) / cols;
    final pw = ((cardW - inner * 2 - 16) / 3).clamp(56.0, 112.0); // 3 posters, 8 apart
    final h = inner + 22 * textScale + 8 + pw * 1.5 + 8 + 2 * 16 * textScale + inner;
    return _BoardGridSpec(cols, pw, h);
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge(this.rank);
  final int rank;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: rank <= 3 ? const Color(0xFFE8A33D) : Colors.black54,
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(6), bottomRight: Radius.circular(6)),
        ),
        child: Text('$rank',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
      );
}

class _PreviewPoster extends StatelessWidget {
  const _PreviewPoster({required this.subject, required this.width, this.rank});
  final Subject subject;
  final double width;
  final int? rank;
  @override
  Widget build(BuildContext context) {
    final pic = subjectImageUrl(subject, SettingsStore.instance.imageQuality);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: width,
      height: width * 1.5,
      child: Stack(fit: StackFit.expand, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: pic == null
              ? ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest)
              : CachedNetworkImage(
                  imageUrl: pic,
                  httpHeaders: doubanImageHeaders,
                  memCacheWidth: (width * dpr).round(),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest),
                ),
        ),
        if (rank != null) Positioned(left: 0, top: 0, child: _RankBadge(rank!)),
      ]),
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({
    required this.board,
    required this.unit,
    required this.posterWidth,
    required this.onTap,
  });
  final RankBoard board;
  final String unit;
  final double posterWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previews = board.previewSubjects.take(3).toList();
    final small = Theme.of(context).textTheme.bodySmall;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(board.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (board.subjectCount > 0) Text('${board.subjectCount}$unit', style: small),
              const Icon(Icons.chevron_right, size: 18),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < previews.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                _PreviewPoster(
                  subject: previews[i],
                  width: posterWidth,
                  rank: board.showRank ? (previews[i].rank ?? i + 1) : null,
                ),
              ],
            ]),
            const SizedBox(height: 8),
            if (board.description.isNotEmpty)
              Text(board.description,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: small),
          ]),
        ),
      ),
    );
  }
}

/// Paged items of one board. The board's preview subjects show
/// immediately; the full list loads in the background and replaces
/// them when it arrives. The numeric boards' items endpoint 404s on
/// both Rexxar and Frodo (verified 2026-10-31), so when it fails the
/// page keeps the previews and says so at the bottom instead of an
/// error state that cannot be retried into working.
class BoardDetailPage extends StatefulWidget {
  const BoardDetailPage({super.key, required this.repository, required this.board});

  final DoubanRepository repository;
  final RankBoard board;

  @override
  State<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends State<BoardDetailPage> {
  /// Board ids whose full list failed this run: reopening one skips
  /// the request and goes straight to previews.
  static final _fullUnavailable = <String>{};

  final _items = <Subject>[];
  int _total = 0;
  bool _loadingMore = false;
  bool _gotFull = false; // whether the full list's first page arrived
  bool _previewOnly = false; // full list unavailable, previews only
  bool _loadMoreFailed = false;

  @override
  void initState() {
    super.initState();
    _items.addAll(widget.board.previewSubjects); // visible immediately
    _total = _items.length;
    if (_fullUnavailable.contains(widget.board.id)) {
      _previewOnly = true;
      return;
    }
    _fetch();
  }

  Future<void> _fetch() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final result = await widget.repository.fetchBoardItems(
        widget.board.id,
        start: _gotFull ? _items.length : 0,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
        if (!_gotFull) {
          if (result.items.isNotEmpty) {
            _items
              ..clear()
              ..addAll(result.items); // the full list replaces the previews
            _gotFull = true;
            _previewOnly = false;
          } else {
            _previewOnly = true;
          }
        } else {
          _items.addAll(result.items);
        }
        _total = result.items.isEmpty
            ? _items.length
            : (result.total > 0 ? result.total : _items.length);
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('board items failed: $e');
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        if (!_gotFull) {
          _previewOnly = true;
          _fullUnavailable.add(widget.board.id);
        } else {
          _loadMoreFailed = true;
        }
      });
    }
  }

  void _openSubject(Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectPage(
          repository: widget.repository,
          type: subject.type,
          id: subject.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.board.name)),
      body: _items.isEmpty
          ? (_previewOnly
              // No previews and the full list failed: the only
              // thing left is a retry.
              ? RetryState(message: '榜单加载失败', onRetry: _fetch)
              : const Center(child: CircularProgressIndicator()))
          : CenteredWidth(
              maxWidth: Breakpoints.gridMaxWidth,
              child: Column(
                children: [
                  // The full list is still loading: a thin bar on
                  // top while the previews are already visible.
                  if (!_gotFull && _loadingMore) const LinearProgressIndicator(),
                  Expanded(child: _listBody()),
                ],
              ),
            ),
    );
  }

  Widget _listBody() {
    final done = _total > 0 && _items.length >= _total;
    final tail = _previewOnly
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('完整榜单暂时无法获取，仅显示榜单提供的 ${_items.length} 条预览',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          )
        : LoadMoreFooter(
            countText: '已加载 ${_items.length} / $_total',
            failed: _loadMoreFailed,
            canLoadMore: () => _gotFull && !_loadingMore && !done, // no auto-load before the full list
            onLoadMore: _fetch,
          );
    return LayoutBuilder(builder: (context, c) {
      // Desktop, once the full list arrived: poster grid. The
      // preview-only mode stays a list either way.
      if (_gotFull && Breakpoints.of(c.maxWidth) != WindowSize.compact) {
        return CustomScrollView(slivers: [
          SliverLayoutBuilder(builder: (context, sc) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final spec = PosterGridSpec.fit(sc.crossAxisExtent - 32, scale);
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: spec.columns,
                  mainAxisSpacing: PosterGridSpec.gap,
                  crossAxisSpacing: PosterGridSpec.gap,
                  mainAxisExtent: spec.cellHeight,
                ),
                itemCount: _items.length,
                itemBuilder: (_, i) => Stack(fit: StackFit.expand, children: [
                  SubjectPosterCard(subject: _items[i], onTap: () => _openSubject(_items[i])),
                  if (widget.board.showRank)
                    Positioned(left: 0, top: 0, child: _RankBadge(_items[i].rank ?? i + 1)),
                ]),
              ),
            );
          }),
          SliverToBoxAdapter(child: tail),
        ]);
      }
      return ListView.builder(
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == _items.length) return tail;
          final subject = _items[i];
          final showRank = widget.board.showRank;
          final rank = subject.rank ?? (i + 1);
          return Row(children: [
            if (showRank)
              SizedBox(
                width: 44,
                child: Center(
                  child: Text('$rank',
                      style: rank <= 3
                          ? const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFE8A33D))
                          : Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ),
            Expanded(
              // No trailing: SubjectRow shows the rating by default.
              child: SubjectRow(
                subject: subject,
                onTap: () => _openSubject(subject),
              ),
            ),
          ]);
        },
      );
    });
  }
}
