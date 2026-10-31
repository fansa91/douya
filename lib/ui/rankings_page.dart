import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await widget.repository.fetchRankBoards(_tagId);
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              for (final entry in rankBoardCategories.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: entry.key == _tagId,
                    onSelected: (_) => _selectCategory(entry.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('榜单加载失败'),
                          const SizedBox(height: 8),
                          OutlinedButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    )
                  : _boards.isEmpty
                      ? const Center(child: Text('该分类暂无榜单'))
                      : CenteredWidth(
                          child: ListView.builder(
                            itemCount: _boards.length,
                          itemBuilder: (context, i) {
                            final board = _boards[i];
                            return Card(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: ListTile(
                                title: Text(board.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: board.description.isEmpty
                                    ? Text('${board.subjectCount} 部作品')
                                    : Text(
                                        board.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (board.subjectCount > 0) Text('${board.subjectCount}部'),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BoardDetailPage(
                                        repository: widget.repository,
                                        board: board,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          ),
                        ),
        ),
      ],
    );
  }
}

/// Paged items of one board. Rows show the board rank (when the
/// board carries one) next to the rating; tapping a row opens the
/// existing subject detail page.
class BoardDetailPage extends StatefulWidget {
  const BoardDetailPage({super.key, required this.repository, required this.board});

  final DoubanRepository repository;
  final RankBoard board;

  @override
  State<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends State<BoardDetailPage> {
  final _items = <Subject>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final result = await widget.repository.fetchBoardItems(
        widget.board.id,
        start: _items.length,
        count: 20,
      );
      if (!mounted) return;
      setState(() {
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
      if (_items.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载更多失败')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.board.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('榜单加载失败'),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _loadMore, child: const Text('重试')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? const Center(child: Text('该榜单暂无内容'))
                  : CenteredWidth(
                      child: ListView.builder(
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
                                          onPressed: _loadMore,
                                          child: Text('加载更多（${_items.length} / $_total）'),
                                        ),
                            ),
                          );
                        }
                        final subject = _items[i];
                        final showRank = widget.board.showRank && subject.rank != null;
                        return SubjectRow(
                          subject: subject,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showRank)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    '#${subject.rank}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFE8A33D),
                                    ),
                                  ),
                                ),
                              if (subject.rating != null && subject.rating!.value > 0)
                                RatingText(rating: subject.rating!),
                            ],
                          ),
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
    );
  }
}
