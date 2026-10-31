import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../data/settings.dart';
import '../models/models.dart';
import 'celebrity_page.dart';
import 'image_preview_page.dart';
import 'video_preview_page.dart';
import 'widgets.dart';

/// TV episodes line, or null when the detail carries neither field
/// (movie/book/music). episodes_info is a status string, not an
/// episode list, so this is a single summary line, not a list.
String? _episodesText(SubjectDetail detail) {
  final parts = <String>[];
  if (detail.episodesInfo.isNotEmpty) parts.add(detail.episodesInfo);
  if (detail.episodesCount > 0) parts.add('共${detail.episodesCount}集');
  if (parts.isEmpty) return null;
  return '集数：${parts.join(' · ')}';
}

void _openImagePreview(BuildContext context, List<String> urls, int index) {
  if (urls.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ImagePreviewPage(urls: urls, initialIndex: index),
    ),
  );
}

Widget _trailerSection(BuildContext context, List<Trailer> trailers) {
  if (trailers.isEmpty) return const SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      const Text('预告片', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      for (var i = 0; i < trailers.length; i++)
        ListTile(
          leading: trailers[i].coverUrl == null
              ? const Icon(Icons.play_circle_outlined)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: trailers[i].coverUrl!,
                    httpHeaders: doubanImageHeaders,
                    width: 72,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => const Icon(Icons.play_circle_outlined),
                  ),
                ),
          title: Text(trailers[i].title.isNotEmpty ? trailers[i].title : '预告片'),
          subtitle: trailers[i].runtime.isNotEmpty ? Text(trailers[i].runtime) : null,
          trailing: const Icon(Icons.play_arrow),
          onTap: trailers[i].videoUrl == null || trailers[i].videoUrl!.isEmpty
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VideoPreviewPage(trailers: trailers, initialIndex: i),
                    ),
                  );
                },
        ),
    ],
  );
}

/// Subject detail. Mobile: tabs. Desktop: two/three columns without
/// tab switching. Both share the same SubjectDetail view model.
class SubjectPage extends StatelessWidget {
  const SubjectPage({super.key, required this.repository, required this.type, required this.id});

  final DoubanRepository repository;
  final String type;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('条目详情')),
      body: FutureBuilder<SubjectDetail>(
        future: repository.fetchSubject(type, id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
          final detail = snapshot.data;
          if (detail == null) return const EmptyState(message: '暂无详情');
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 1024) return _MobileDetail(detail: detail, repository: repository);
              return _DesktopDetail(detail: detail, repository: repository, wide: constraints.maxWidth >= 1440);
            },
          );
        },
      ),
    );
  }
}

Widget _header(SubjectDetail detail) {
  final s = detail.subject;
  // Display follows the image-quality setting; the preview opened
  // on tap always uses the parsed (large-first) URL.
  final displayPic = subjectImageUrl(s, SettingsStore.instance.imageQuality);
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) => GestureDetector(
            onTap: s.pic == null ? null : () => _openImagePreview(context, [s.pic!], 0),
            child: Container(
              width: 110,
              height: 150,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
              child: displayPic == null
                  ? const Icon(Icons.book_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: displayPic, httpHeaders: doubanImageHeaders, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.book_outlined)),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (s.year != null) Text(s.year!),
              if (detail.genres.isNotEmpty) Text(detail.genres.join(' / ')),
              if (detail.directors.isNotEmpty) Text('导演：${detail.directors.join(' / ')}'),
              if (detail.actors.isNotEmpty) Text('主演：${detail.actors.join(' / ')}'),
              if (detail.authors.isNotEmpty) Text('${s.type == 'music' ? '歌手' : '作者'}：${detail.authors.join(' / ')}'),
              if (_episodesText(detail) != null) Text(_episodesText(detail)!),
              const SizedBox(height: 12),
              if (s.rating != null) RatingText(rating: s.rating!),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One short comment row. Tap toggles between the 3-line preview
/// and the full text (the API already returns the full text; only
/// the UI truncated it). Vote count and time come from the same
/// item; the UI previously showed neither.
class _CommentTile extends StatefulWidget {
  const _CommentTile({required this.comment});

  final ShortComment comment;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final meta = [
      if (c.voteCount > 0) '赞 ${c.voteCount}',
      if (c.createTime.isNotEmpty) c.createTime,
    ].join(' · ');
    return ListTile(
      title: Text(c.userName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c.text, maxLines: _expanded ? null : 3, overflow: _expanded ? null : TextOverflow.ellipsis),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(meta, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
      trailing: c.rating != null ? RatingText(rating: c.rating!, community: false) : null,
      onTap: () => setState(() => _expanded = !_expanded),
    );
  }
}

/// Paged short comments. Starts from the first page fetchSubject
/// already loaded and pages by the API total, same pattern as the
/// group topic list. Used on both mobile (inside a ListView tab)
/// and desktop (inside the scrolling detail column), so it builds
/// a Column, not its own scroll view.
class _PagedComments extends StatefulWidget {
  const _PagedComments({
    required this.repository,
    required this.type,
    required this.id,
    required this.initialItems,
    required this.total,
  });

  final DoubanRepository repository;
  final String type;
  final String id;
  final List<ShortComment> initialItems;
  final int total;

  @override
  State<_PagedComments> createState() => _PagedCommentsState();
}

class _PagedCommentsState extends State<_PagedComments> {
  late List<ShortComment> _items = widget.initialItems;
  late int _total = widget.total;
  bool _loadingMore = false;

  Future<void> _loadMore() async {
    if (_loadingMore || (_total > 0 && _items.length >= _total)) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchSubjectComments(widget.type, widget.id, start: _items.length, count: 20);
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

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const EmptyState(message: '暂无短评');
    final hasMore = _total > 0 && _items.length < _total;
    return Column(
      children: [
        for (final c in _items) _CommentTile(comment: c),
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
  }
}

/// Mobile celebrity tab content. Celebrities are already fetched
/// by fetchSubject (desktop already shows them); mobile previously
/// had no celebrity section at all.
Widget _celebrityList(List<Celebrity> celebrities, DoubanRepository repository) {
  if (celebrities.isEmpty) return const EmptyState(message: '暂无影人');
  return Column(
    children: [
      for (final c in celebrities)
        Builder(
          builder: (context) => ListTile(
            title: Text(c.name),
            subtitle: c.character == null || c.character!.isEmpty ? null : Text(c.character!),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CelebrityPage(repository: repository, id: c.id)),
              );
            },
          ),
        ),
    ],
  );
}

/// Paged long reviews. Tap a review to open its full text page.
/// Same Column-based paging pattern as _PagedComments.
class _PagedReviews extends StatefulWidget {
  const _PagedReviews({
    required this.repository,
    required this.type,
    required this.id,
    required this.initialItems,
    required this.total,
  });

  final DoubanRepository repository;
  final String type;
  final String id;
  final List<Review> initialItems;
  final int total;

  @override
  State<_PagedReviews> createState() => _PagedReviewsState();
}

class _PagedReviewsState extends State<_PagedReviews> {
  late List<Review> _items = widget.initialItems;
  late int _total = widget.total;
  bool _loadingMore = false;

  Future<void> _loadMore() async {
    if (_loadingMore || (_total > 0 && _items.length >= _total)) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchSubjectReviews(widget.type, widget.id, start: _items.length, count: 20);
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

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const EmptyState(message: '暂无长评');
    final hasMore = _total > 0 && _items.length < _total;
    return Column(
      children: [
        for (final r in _items)
          ListTile(
            title: Text(r.title),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.abstract, maxLines: 3, overflow: TextOverflow.ellipsis),
                if (r.userName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(r.userName, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
            trailing: Text('有用 ${r.usefulCount}'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ReviewDetailPage(repository: widget.repository, reviewId: r.id)),
              );
            },
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
  }
}

/// Paged photo grid. Starts from the first page fetchSubject
/// already loaded and pages by the API total (photos support
/// start/count, verified 2026-10-31). [fillViewport] is true for
/// the mobile tab (the grid fills the tab, footer below it) and
/// false for the desktop column (shrink-wrapped grid inside the
/// scrolling detail column). Preview URLs always come from the
/// full loaded list, not just the first page.
class _PagedPhotos extends StatefulWidget {
  const _PagedPhotos({
    required this.repository,
    required this.type,
    required this.id,
    required this.initialItems,
    required this.total,
    required this.fillViewport,
  });

  final DoubanRepository repository;
  final String type;
  final String id;
  final List<Photo> initialItems;
  final int total;
  final bool fillViewport;

  @override
  State<_PagedPhotos> createState() => _PagedPhotosState();
}

class _PagedPhotosState extends State<_PagedPhotos> {
  late List<Photo> _items = widget.initialItems;
  late int _total = widget.total;
  bool _loadingMore = false;

  Future<void> _loadMore() async {
    if (_loadingMore || (_total > 0 && _items.length >= _total)) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchSubjectPhotos(widget.type, widget.id, start: _items.length, count: 20);
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

  @override
  Widget build(BuildContext context) {
    final urls = _items.map((p) => p.url).whereType<String>().toList();
    final grid = GridView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: !widget.fillViewport,
      physics: widget.fillViewport ? null : const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final p = _items[i];
        final displayUrl = photoImageUrl(p, SettingsStore.instance.imageQuality);
        if (displayUrl == null) return const Icon(Icons.image_outlined);
        final index = urls.indexOf(p.url!);
        return GestureDetector(
          onTap: () => _openImagePreview(context, urls, index < 0 ? 0 : index),
          child: Hero(
            tag: p.url!,
            child: CachedNetworkImage(imageUrl: displayUrl, httpHeaders: doubanImageHeaders, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.image_outlined)),
          ),
        );
      },
    );
    final hasMore = _total > 0 && _items.length < _total;
    final footer = Padding(
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
    );
    if (widget.fillViewport) {
      return Column(children: [Expanded(child: grid), footer]);
    }
    return Column(children: [grid, footer]);
  }
}

/// Long review full text page. Content arrives as plain text
/// (ReviewDetail.fromJson strips the API's HTML); photos from the
/// review detail are not shown yet.
class ReviewDetailPage extends StatelessWidget {
  const ReviewDetailPage({super.key, required this.repository, required this.reviewId});

  final DoubanRepository repository;
  final String reviewId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('长评详情')),
      body: FutureBuilder<ReviewDetail>(
        future: repository.fetchReview(reviewId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snapshot.hasError) return EmptyState(message: '加载失败：${snapshot.error}');
          final detail = snapshot.data;
          if (detail == null) return const EmptyState(message: '暂无长评');
          return CenteredWidth(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(detail.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                [
                  if (detail.userName.isNotEmpty) detail.userName,
                  if (detail.createTime.isNotEmpty) detail.createTime,
                  '有用 ${detail.usefulCount}',
                  '回应 ${detail.commentsCount}',
                ].join(' · '),
              ),
              const Divider(height: 32),
              SelectableText(detail.content),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MobileDetail extends StatelessWidget {
  const _MobileDetail({required this.detail, required this.repository});

  final SubjectDetail detail;
  final DoubanRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          _header(detail),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(detail.summary),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _trailerSection(context, detail.trailers),
          ),
          const TabBar(tabs: [Tab(text: '短评'), Tab(text: '长评'), Tab(text: '剧照'), Tab(text: '影人'), Tab(text: '相关')]),
          Expanded(
            child: TabBarView(
              children: [
                ListView(children: [
                  _PagedComments(repository: repository, type: detail.subject.type, id: detail.subject.id, initialItems: detail.comments, total: detail.commentsTotal),
                ]),
                ListView(children: [
                  _PagedReviews(repository: repository, type: detail.subject.type, id: detail.subject.id, initialItems: detail.reviews, total: detail.reviewsTotal),
                ]),
                detail.photos.isEmpty
                    ? const EmptyState(message: '暂无剧照')
                    : _PagedPhotos(
                        repository: repository,
                        type: detail.subject.type,
                        id: detail.subject.id,
                        initialItems: detail.photos,
                        total: detail.photosTotal,
                        fillViewport: true,
                      ),
                ListView(children: [_celebrityList(detail.celebrities, repository)]),
                ListView(
                  children: [
                    for (final s in detail.recommendations)
                      SubjectRow(subject: s, onTap: () {}),
                    for (final s in detail.doulists)
                      ListTile(title: Text(s.title), subtitle: Text('豆列 · ${s.doulistCount ?? ''} 条')),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopDetail extends StatelessWidget {
  const _DesktopDetail({required this.detail, required this.repository, required this.wide});

  final SubjectDetail detail;
  final DoubanRepository repository;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (detail.subject.pic != null)
                  GestureDetector(
                    onTap: () => _openImagePreview(context, [detail.subject.pic!], 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(imageUrl: subjectImageUrl(detail.subject, SettingsStore.instance.imageQuality) ?? detail.subject.pic!, httpHeaders: doubanImageHeaders, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.book_outlined)),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(detail.subject.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (detail.subject.rating != null) RatingText(rating: detail.subject.rating!),
                if (detail.genres.isNotEmpty) Text(detail.genres.join(' / ')),
                if (detail.directors.isNotEmpty) Text('导演：${detail.directors.join(' / ')}'),
                if (detail.actors.isNotEmpty) Text('主演：${detail.actors.join(' / ')}'),
                if (detail.authors.isNotEmpty) Text('${detail.subject.type == 'music' ? '歌手' : '作者'}：${detail.authors.join(' / ')}'),
                if (_episodesText(detail) != null) Text(_episodesText(detail)!),
                const Divider(),
                const Text('影人', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                for (final c in detail.celebrities)
                  ListTile(
                    title: Text(c.name),
                    subtitle: Text(c.character ?? ''),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CelebrityPage(repository: repository, id: c.id)),
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            // Reading column capped at 720 (same CenteredWidth used
            // elsewhere); the left info column and the right
            // recommendations column keep their fixed widths.
            child: CenteredWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail.summary),
                _trailerSection(context, detail.trailers),
                const SizedBox(height: 24),
                const Text('短评', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                _PagedComments(repository: repository, type: detail.subject.type, id: detail.subject.id, initialItems: detail.comments, total: detail.commentsTotal),
                const SizedBox(height: 24),
                const Text('长评', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                _PagedReviews(repository: repository, type: detail.subject.type, id: detail.subject.id, initialItems: detail.reviews, total: detail.reviewsTotal),
                if (detail.photos.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('剧照', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _PagedPhotos(
                    repository: repository,
                    type: detail.subject.type,
                    id: detail.subject.id,
                    initialItems: detail.photos,
                    total: detail.photosTotal,
                    fillViewport: false,
                  ),
                ],
                ],
              ),
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 24),
            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('同类推荐', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final s in detail.recommendations) SubjectRow(subject: s, onTap: () {}),
                  const SizedBox(height: 24),
                  const Text('相关豆列', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final s in detail.doulists)
                    ListTile(title: Text(s.title), subtitle: Text('豆列 · ${s.doulistCount ?? ''} 条')),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
