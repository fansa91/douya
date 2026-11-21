import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/deep_link.dart';
import '../data/repository.dart';
import '../models/models.dart';
import 'faceted_view.dart';
import 'rankings_page.dart';
import 'widgets.dart';

/// Find-movie / find-tv landing page ("找片"): the Rexxar
/// /{movie|tv}/landing groups, sectioned by their returned titles.
/// Board links (专题) render as a horizontal card row; tag links
/// (类型/地区/特色/播出平台) render as wrapping chips. Items whose
/// deep link does not parse, or parses to a shape this page has no
/// use for, are hidden instead of a dead button.
class LandingPage extends StatefulWidget {
  const LandingPage({super.key, required this.repository, required this.endpoint});

  final DoubanRepository repository;

  /// 'movie' or 'tv'.
  final String endpoint;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  List<LandingGroup> _groups = const [];
  bool _loading = true;
  String? _error;

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
      final groups = await widget.repository.fetchLanding(widget.endpoint);
      if (mounted) setState(() => _groups = groups);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openTag(TagSearchLink link, String groupName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FacetedPage(
          repository: widget.repository,
          endpoint: link.endpoint,
          initialSelection: {groupName: link.query},
        ),
      ),
    );
  }

  void _openBoard(BoardLink link, String name) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BoardDetailPage(
          repository: widget.repository,
          board: RankBoard(id: link.boardId, name: name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.endpoint == 'tv' ? '找电视' : '找电影')),
      body: _loading
          ? const LoadingList()
          : _error != null
              ? RetryState(message: '加载失败', onRetry: _load)
              : _groups.isEmpty
                  ? const EmptyState(message: '暂无找片内容')
                  : ListView(
                      children: [for (final group in _groups) _section(group)],
                    ),
    );
  }

  Widget _section(LandingGroup group) {
    final boards = <(LandingItem, BoardLink)>[];
    final tags = <(LandingItem, TagSearchLink)>[];
    for (final item in group.items) {
      final link = parseDeepLink(item.uri, groupType: group.name);
      if (link is BoardLink) {
        boards.add((item, link));
      } else if (link is TagSearchLink) {
        tags.add((item, link));
      }
      // Anything else (search, subject, unknown) has no place on
      // this page and is hidden.
    }
    if (boards.isEmpty && tags.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        if (boards.isNotEmpty)
          SizedBox(
            height: 120,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: boards.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final (item, link) = boards[i];
                return _boardCard(item, link);
              },
            ),
          ),
        if (tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (item, link) in tags)
                  ActionChip(
                    label: Text(item.name),
                    onPressed: () => _openTag(link, group.name),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _boardCard(LandingItem item, BoardLink link) {
    final fallback = item.headerBgColor?.primaryLight != null ? _hexColor(item.headerBgColor!.primaryLight!) : null;
    return SizedBox(
      width: 160,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: fallback,
        child: InkWell(
          onTap: () => _openBoard(link, item.name),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.headerBgImage != null)
                CachedNetworkImage(
                  imageUrl: item.headerBgImage!,
                  httpHeaders: doubanImageHeaders,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                    stops: [0.5, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 6-digit hex colour ("8491a5") to a [Color]; null when malformed.
Color? _hexColor(String hex) {
  final clean = hex.replaceAll('#', '');
  if (clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

/// A pushed multi-dim filter page: a Scaffold around FacetedView, so
/// a landing chip can open the filter with a tag preselected.
class _FacetedPage extends StatelessWidget {
  const _FacetedPage({required this.repository, required this.endpoint, required this.initialSelection});

  final DoubanRepository repository;
  final String endpoint;
  final Map<String, String> initialSelection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('多维筛选')),
      body: FacetedView(repository: repository, endpoint: endpoint, initialSelection: initialSelection),
    );
  }
}
