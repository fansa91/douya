import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'breakpoints.dart';
import 'celebrity_photos_page.dart';
import 'image_preview_page.dart';
import 'subject_page.dart';
import 'widgets.dart';

/// Celebrity page. The id must come from the subject's celebrities
/// endpoint, because the subject detail itself only carries names.
///
/// Stateful so the detail future is created once in initState: the
/// old StatelessWidget built it in build(), so every rebuild (e.g.
/// dragging the window) re-fetched and flashed, and the photo
/// strip's state was lost with it. _CelebrityPhotos already keeps
/// its own future in state, so it is not the same bug.
///
/// Mobile (<900) is one scrolling column: a compact header, the
/// first four bio rows behind 更多资料， a photo preview (at most 8)
/// with an 全部 N 张 entry to the photo wall, then a pinned works
/// title + role filter and a lazy works list. Desktop (>=900) is
/// two columns inside 1440: the left one (320–360, independently
/// scrolling) holds a big avatar, the full bio and a photo
/// mini-grid; the right one holds the works title, the role filter
/// and a poster grid. Works stay in rating order — never grouped
/// by year, never re-sorted client-side.
class CelebrityPage extends StatefulWidget {
  const CelebrityPage({super.key, required this.repository, required this.id});

  final DoubanRepository repository;
  final String id;

  @override
  State<CelebrityPage> createState() => _CelebrityPageState();
}

class _CelebrityPageState extends State<CelebrityPage> {
  late Future<CelebrityDetail> _future;

  /// The celebrity id the works below were seeded from. Seeding
  /// happens in the FutureBuilder (direct assignment, no setState)
  /// so a rebuild after load-more does not reset the list.
  String _seededId = '';

  /// Celebrity name, for the AppBar title once scrolled past the
  /// header.
  String _celebrityName = '';

  /// Show the name in the AppBar (scrolled past the header).
  bool _showTitle = false;

  /// 更多资料 expanded (all bio rows, not just the first four).
  bool _showAllInfo = false;

  /// Role filter; null means 全部 (no filter).
  String? _roleFilter;

  /// Works, lifted from the old _PagedWorks so the page can filter
  /// them and the role chips can read the loaded roles. Seeded
  /// from the detail's first page, then extended by _loadMoreWorks.
  /// The endpoint's pages overlap by one entry, so loads dedupe by
  /// subject id (probed 2026-11-21).
  List<CelebrityWork> _works = [];
  int _worksTotal = 0;
  bool _worksLoadingMore = false;
  bool _worksLoadMoreFailed = false;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchCelebrity(widget.id);
  }

  @override
  void didUpdateWidget(CelebrityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _future = widget.repository.fetchCelebrity(widget.id);
      _seededId = '';
      _showTitle = false;
      _showAllInfo = false;
      _roleFilter = null;
    }
  }

  Future<void> _loadMoreWorks() async {
    if (_worksLoadingMore) return;
    setState(() => _worksLoadingMore = true);
    try {
      final result = await widget.repository.fetchCelebrityWorks(widget.id, start: _works.length, count: 20);
      if (!mounted) return;
      final seen = _works.map((w) => w.subject.id).toSet();
      setState(() {
        _works = [..._works, ...result.works.where((w) => seen.add(w.subject.id))];
        if (result.total > 0) _worksTotal = result.total;
        if (result.works.isEmpty) _worksTotal = _works.length;
        _worksLoadMoreFailed = false;
      });
      _maybeLoadMoreForFilter();
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _worksLoadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _worksLoadingMore = false);
    }
  }

  /// A role filter can leave too little to show: keep loading the
  /// next page until there is content or the total is reached.
  /// "Too little" is under 10 filtered works. Each load grows the
  /// list, so this terminates when everything is loaded.
  void _maybeLoadMoreForFilter() {
    if (_roleFilter == null) return;
    if (_filteredWorks.length >= 10) return;
    if (_works.length >= _worksTotal || _worksLoadingMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMoreWorks();
    });
  }

  void _setRoleFilter(String? role) {
    setState(() => _roleFilter = role);
    _maybeLoadMoreForFilter();
  }

  /// Works matching the role filter. Roles are matched by their
  /// base name ('演员 (饰 …)' counts as 演员）.
  List<CelebrityWork> get _filteredWorks {
    final role = _roleFilter;
    if (role == null) return _works;
    return _works.where((w) => w.roles.any((r) => _baseRole(r) == role)).toList();
  }

  /// Distinct base roles across the loaded works, in first-seen
  /// order. The filter chips are 全部 plus these.
  List<String> get _availableRoles {
    final seen = <String>[];
    for (final w in _works) {
      for (final r in w.roles) {
        final base = _baseRole(r);
        if (base.isNotEmpty && !seen.contains(base)) seen.add(base);
      }
    }
    return seen;
  }

  /// '演员 (饰 安迪·杜佛兰)' → '演员'. A role without a paren
  /// stays as it is.
  static String _baseRole(String role) => role.split(' (').first.trim();

  /// Scroll past the header shows the name in the AppBar. Only
  /// vertical scrolls count (the photo strip scrolls horizontally).
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification && notification.metrics.axis == Axis.vertical) {
      final show = notification.metrics.pixels > 120;
      if (show != _showTitle) setState(() => _showTitle = show);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_showTitle && _celebrityName.isNotEmpty ? _celebrityName : '影人')),
      body: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: FutureBuilder<CelebrityDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingList();
            }
            if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
            final detail = snapshot.data;
            if (detail == null) return const EmptyState(message: '暂无影人信息');
            if (_seededId != detail.celebrity.id) {
              _seededId = detail.celebrity.id;
              _celebrityName = detail.celebrity.name;
              _works = List.of(detail.works);
              _worksTotal = detail.worksTotal;
              _roleFilter = null;
              _showAllInfo = false;
              _worksLoadingMore = false;
              _worksLoadMoreFailed = false;
            }
            final celebrity = detail.celebrity;
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < Breakpoints.paneSplit) {
                  return _mobileBody(context, celebrity);
                }
                return _desktopBody(context, constraints, celebrity);
              },
            );
          },
        ),
      ),
    );
  }

  /// Mobile: one column. Compact header (avatar 72, name, English
  /// name, at most two lines of short info, "N 人关注"), the first
  /// four bio rows with the rest behind 更多资料， the photo preview,
  /// then a pinned works title + role filter and the lazy works
  /// list. The header used to show every bio row, so the works
  /// (the main content) were pushed far down the first screen.
  Widget _mobileBody(BuildContext context, Celebrity celebrity) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _header(context, celebrity, avatarRadius: 36),
              if (celebrity.info.isNotEmpty) ...[
                const SizedBox(height: 16),
                ..._infoRows(context, celebrity, foldLongText: true),
              ],
              _CelebrityPhotos(repository: widget.repository, id: widget.id, name: celebrity.name),
            ]),
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          // The delegate's extent is 48: the row is wrapped in a
          // 48-tall box so the child fills it (a shorter child
          // makes the sliver geometry invalid).
          delegate: PinnedTabBarDelegate(
            SizedBox(height: 48, child: _worksTitleRow(context)),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: _worksListSliver(),
        ),
      ],
    );
  }

  /// Desktop: two columns inside 1440. The left one (320–360,
  /// independently scrolling) holds a big avatar, the name, the
  /// English name, the FULL bio (no folding) and a photo mini-grid
  /// (first 9) with an 全部 entry. The right one holds the works
  /// title, the role filter and a poster grid. The old layout was
  /// a single 720-wide column, so wide screens were mostly empty.
  Widget _desktopBody(BuildContext context, BoxConstraints constraints, Celebrity celebrity) {
    final capped = constraints.maxWidth.clamp(0.0, Breakpoints.gridMaxWidth);
    final leftWidth = (capped * 0.25).clamp(320.0, 360.0);
    return CenteredWidth(
      maxWidth: Breakpoints.gridMaxWidth,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: leftWidth,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(context, celebrity, avatarRadius: 48),
                if (celebrity.info.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  ..._infoRows(context, celebrity, foldLongText: false),
                ],
                _CelebrityPhotos(repository: widget.repository, id: widget.id, name: celebrity.name, grid: true),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _worksTitleRow(context),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        sliver: _worksGridSliver(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Header: photo avatar, name, English name, short info (at most
  /// two lines on mobile), and "N 人关注" when known. The old text
  /// read "关注 N".
  Widget _header(BuildContext context, Celebrity celebrity, {required double avatarRadius}) {
    final avatarUrl = celebrity.avatar;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: avatarRadius,
          backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl, headers: doubanImageHeaders) : null,
          child: avatarUrl == null
              ? Text(celebrity.name.isEmpty ? '?' : celebrity.name[0], style: TextStyle(fontSize: avatarRadius * 0.8))
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(celebrity.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (celebrity.latinTitle != null && celebrity.latinTitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(celebrity.latinTitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
              if (celebrity.shortInfo != null && celebrity.shortInfo!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  celebrity.shortInfo!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (celebrity.followedCount > 0) ...[
                const SizedBox(height: 4),
                Text('${celebrity.followedCount} 人关注', style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Bio key/value rows from extra.info (gender, birthday,
  /// birthplace, ...). Mobile shows the first four and folds the
  /// rest behind 更多资料； long values fold to two lines. Desktop
  /// shows everything, unfolded.
  List<Widget> _infoRows(BuildContext context, Celebrity celebrity, {required bool foldLongText}) {
    final rows = celebrity.info;
    final shown = !foldLongText || _showAllInfo ? rows : rows.take(4).toList();
    final hidden = rows.length - shown.length;
    return [
      for (final (label, value) in shown)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(
                  value,
                  maxLines: foldLongText ? 2 : null,
                  overflow: foldLongText ? TextOverflow.ellipsis : null,
                ),
              ),
            ],
          ),
        ),
      if (foldLongText && hidden > 0)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAllInfo = true),
            child: Text('更多资料（$hidden）'),
          ),
        ),
      if (foldLongText && _showAllInfo && rows.length > 4)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _showAllInfo = false),
            child: const Text('收起'),
          ),
        ),
    ];
  }

  /// Works title + role filter chips. The title shows the filtered
  /// count while a filter is active, else the total.
  Widget _worksTitleRow(BuildContext context) {
    final count = _roleFilter == null ? _worksTotal : _filteredWorks.length;
    final roles = _availableRoles;
    return Row(
      children: [
        Text(
          '作品${count > 0 ? '（$count）' : ''}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 8),
        if (roles.isNotEmpty)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _roleChip(null, '全部'),
                  for (final role in roles) ...[
                    const SizedBox(width: 8),
                    _roleChip(role, role),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _roleChip(String? role, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _roleFilter == role,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => _setRoleFilter(role),
    );
  }

  /// Mobile works list: lazy rows (SubjectRow), in rating order.
  /// A lazy SliverList, so the footer only mounts when scrolled
  /// near: the old shrink-wrapped inner list laid out every child
  /// at once, so the footer mounted on page load and auto-loaded
  /// all works (113 ≈ 6 requests) on mobile, where the footer
  /// never pauses.
  Widget _worksListSliver() {
    final filtered = _filteredWorks;
    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          message: _roleFilter == null ? '暂无作品' : '该角色暂无已加载的作品',
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i == filtered.length) {
            return LoadMoreFooter(
              key: const ValueKey('celebrity-works-footer'),
              canLoadMore: () => !_worksLoadingMore && _works.length < _worksTotal,
              onLoadMore: _loadMoreWorks,
              failed: _worksLoadMoreFailed,
              countText: _worksTotal > 0 ? '已加载 ${_works.length} / $_worksTotal' : null,
            );
          }
          final work = filtered[i];
          final subtitleParts = [
            ...work.roles,
            if (work.subject.year != null && work.subject.year!.isNotEmpty) work.subject.year!,
          ];
          return SubjectRow(
            subject: work.subject,
            subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' · ') : null,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SubjectPage(repository: widget.repository, type: work.subject.type, id: work.subject.id),
                ),
              );
            },
          );
        },
        childCount: filtered.length + 1,
      ),
    );
  }

  /// Desktop works grid: poster cards, in rating order. Cards show
  /// "年份 · 角色" under the title instead of the rating.
  Widget _worksGridSliver() {
    final filtered = _filteredWorks;
    if (filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: EmptyState(
          message: _roleFilter == null ? '暂无作品' : '该角色暂无已加载的作品',
        ),
      );
    }
    return SliverMainAxisGroup(
      slivers: [
        SliverLayoutBuilder(
          builder: (context, sc) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final spec = PosterGridSpec.fit(sc.crossAxisExtent, scale);
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: spec.columns,
                mainAxisSpacing: PosterGridSpec.gap,
                crossAxisSpacing: PosterGridSpec.gap,
                mainAxisExtent: spec.cellHeight,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final work = filtered[i];
                final baseRoles = work.roles.map(_baseRole).where((r) => r.isNotEmpty).toSet().toList();
                final subtitleParts = [
                  if (work.subject.year != null && work.subject.year!.isNotEmpty) work.subject.year!,
                  ...baseRoles,
                ];
                return SubjectPosterCard(
                  subject: work.subject,
                  subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' · ') : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SubjectPage(repository: widget.repository, type: work.subject.type, id: work.subject.id),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        SliverToBoxAdapter(
          child: LoadMoreFooter(
            key: const ValueKey('celebrity-works-footer'),
            canLoadMore: () => !_worksLoadingMore && _works.length < _worksTotal,
            onLoadMore: _loadMoreWorks,
            failed: _worksLoadMoreFailed,
            countText: _worksTotal > 0 ? '已加载 ${_works.length} / $_worksTotal' : null,
          ),
        ),
      ],
    );
  }
}

/// Celebrity photos, as a horizontal strip (mobile) or a mini-grid
/// (desktop). Fetched once from /celebrity/{id}/photos (verified
/// 2026-11-21, total 120 for Tim Robbins). Hidden when there are
/// no photos. The strip shows at most 8 thumbnails, the mini-grid
/// the first 9; a trailing 全部 N 张 tile opens the photo wall
/// page, which pages through the rest. Tapping a photo opens the
/// existing image preview. Thumbnails keep their original aspect:
/// the strip sizes each one from the photo's pixel size (no more
/// fixed 110×150 portrait crop), and the grid contains the photo
/// instead of cropping it.
class _CelebrityPhotos extends StatefulWidget {
  const _CelebrityPhotos({required this.repository, required this.id, required this.name, this.grid = false});

  final DoubanRepository repository;
  final String id;

  /// Celebrity name, for the photo wall page title.
  final String name;

  /// True for the desktop mini-grid, false for the mobile strip.
  final bool grid;

  @override
  State<_CelebrityPhotos> createState() => _CelebrityPhotosState();
}

class _CelebrityPhotosState extends State<_CelebrityPhotos> {
  late final Future<CelebrityPhotosResult> _firstPage =
      widget.repository.fetchCelebrityPhotos(widget.id);

  void _openWall(BuildContext context, int total) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CelebrityPhotosPage(
          repository: widget.repository,
          id: widget.id,
          name: widget.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CelebrityPhotosResult>(
      future: _firstPage,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final first = snapshot.data;
        if (first == null) return const SizedBox.shrink();
        final photos = first.photos;
        if (photos.isEmpty) return const SizedBox.shrink();
        final total = first.total;
        final urls = photos.map((p) => p.imageUrl).whereType<String>().toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 16),
          Text(
            '剧照${total > 0 ? '（$total）' : ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (widget.grid) _miniGrid(context, photos, total, urls) else _strip(context, photos, total, urls),
        ]);
      },
    );
  }

  /// Mobile strip: at most 8 thumbnails, each sized from the
  /// photo's own aspect ratio (height 150), then the 全部 tile.
  Widget _strip(BuildContext context, List<CelebrityPhoto> photos, int total, List<String> urls) {
    final shown = photos.take(8).toList();
    return SizedBox(
      height: 150,
      child: HScrollRow(children: [
        for (var i = 0; i < shown.length; i++) _photoThumb(context, shown[i], urls, i, height: 150),
        if (total > shown.length)
          SizedBox(
            width: 90,
            height: 150,
            child: OutlinedButton(
              onPressed: () => _openWall(context, total),
              child: Text('全部 $total 张'),
            ),
          ),
      ]),
    );
  }

  /// Desktop mini-grid: the first 9 photos in 3 columns, each
  /// contained (not cropped), then the 全部 tile when there are
  /// more. A plain GridView, shrink-wrapped inside the left
  /// column's ListView.
  Widget _miniGrid(BuildContext context, List<CelebrityPhoto> photos, int total, List<String> urls) {
    final shown = photos.take(9).toList();
    final hasAll = total > shown.length;
    final itemCount = shown.length + (hasAll ? 1 : 0);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: itemCount,
      itemBuilder: (context, i) {
        if (i == shown.length) {
          return OutlinedButton(
            onPressed: () => _openWall(context, total),
            child: Text('全部\n$total 张', textAlign: TextAlign.center),
          );
        }
        return _photoThumb(context, shown[i], urls, i, grid: true);
      },
    );
  }

  Widget _photoThumb(BuildContext context, CelebrityPhoto photo, List<String> urls, int index, {double height = 150, bool grid = false}) {
    final url = photo.imageUrl;
    if (url == null) return const SizedBox.shrink();
    final previewIndex = urls.indexOf(url);
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: doubanImageHeaders,
        fit: grid ? BoxFit.contain : BoxFit.cover,
        errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
      ),
    );
    final sized = grid
        ? Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: thumb,
          )
        : SizedBox(width: _stripWidth(photo, height), height: height, child: thumb);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImagePreviewPage(urls: urls, initialIndex: previewIndex < 0 ? 0 : previewIndex),
        ),
      ),
      child: sized,
    );
  }

  /// Strip thumbnail width from the photo's pixel size (height is
  /// fixed at 150): a landscape photo is wider than a portrait
  /// one, so neither is cropped. Unknown size falls back to the
  /// old 110 width, clamped to 80–240.
  double _stripWidth(CelebrityPhoto photo, double height) {
    final aspect = photo.width != null && photo.height != null && photo.height! > 0
        ? photo.width! / photo.height!
        : 110 / 150;
    return (height * aspect).clamp(80.0, 240.0);
  }
}
