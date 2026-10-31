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

Widget _trailerTile(BuildContext context, List<Trailer> trailers, int i) {
  return ListTile(
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
  );
}

/// Trailers preview: first 3, with 更多 to the full list when there
/// are more (trailers are usually 1-3, so 更多 rarely appears).
Widget _trailersPreview(BuildContext context, List<Trailer> trailers) {
  if (trailers.isEmpty) return const SizedBox.shrink();
  const previewCount = 3;
  final shown = trailers.length > previewCount ? trailers.sublist(0, previewCount) : trailers;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Row(
        children: [
          const Text('预告片', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (trailers.length > previewCount)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _TrailersPage(trailers: trailers)),
                );
              },
              child: Text('更多（${trailers.length}）'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      for (var i = 0; i < shown.length; i++) _trailerTile(context, trailers, i),
    ],
  );
}

class _TrailersPage extends StatelessWidget {
  const _TrailersPage({required this.trailers});

  final List<Trailer> trailers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全部预告片')),
      body: ListView.builder(
        itemCount: trailers.length,
        itemBuilder: (context, i) => _trailerTile(context, trailers, i),
      ),
    );
  }
}

/// Subject detail. Left 3/4 holds the subject info, trailers,
/// celebrities and photos; right 1/4 holds tabbed related videos /
/// comments. Mobile stacks the same sections and switches the two
/// right-side tabs below them. Both share the same SubjectDetail
/// view model.
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
              return _DesktopDetail(detail: detail, repository: repository);
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
      leading: c.userAvatar == null || c.userAvatar!.isEmpty
          ? const CircleAvatar(radius: 20, child: Icon(Icons.person_outlined))
          : CircleAvatar(radius: 20, backgroundImage: doubanImageProvider(c.userAvatar!)),
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
/// Paged short comments. Builds its own ListView.builder (the
/// mobile tab hosts it directly); [fillViewport] is false for the
/// desktop column, where it shrink-wraps inside the outer scroll
/// view instead of owning the scroll.
class _PagedComments extends StatefulWidget {
  const _PagedComments({
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
  final List<ShortComment> initialItems;
  final int total;
  final bool fillViewport;

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
          if (result.items.isEmpty) _total = _items.length;
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
    return ListView.builder(
      shrinkWrap: !widget.fillViewport,
      physics: widget.fillViewport ? null : const NeverScrollableScrollPhysics(),
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return LoadMoreFooter(
            countText: _total > 0 ? '已加载 ${_items.length} / $_total' : null,
            canLoadMore: () => !_loadingMore && hasMore,
            onLoadMore: _loadMore,
          );
        }
        return _CommentTile(comment: _items[i]);
      },
    );
  }
}

/// Mobile celebrity tab content. Celebrities are already fetched
/// by fetchSubject (desktop already shows them); mobile previously
/// had no celebrity section at all.
Widget _celebrityAvatar(Celebrity c, double radius) {
  if (c.avatar == null || c.avatar!.isEmpty) {
    return CircleAvatar(radius: radius, child: const Icon(Icons.person_outlined));
  }
  return CircleAvatar(radius: radius, backgroundImage: doubanImageProvider(c.avatar!));
}

void _openCelebrity(BuildContext context, DoubanRepository repository, Celebrity c) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CelebrityPage(repository: repository, id: c.id)),
  );
}

/// Celebrities as a horizontal row: first 10, with a 更多 tile to
/// the full list when there are more (the endpoint caps at 14).
Widget _celebritiesRow(BuildContext context, List<Celebrity> celebrities, DoubanRepository repository) {
  if (celebrities.isEmpty) return const SizedBox.shrink();
  const previewCount = 10;
  final shown = celebrities.length > previewCount ? celebrities.sublist(0, previewCount) : celebrities;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Row(
        children: [
          const Text('影人', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (celebrities.length > previewCount)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => _CelebrityListPage(celebrities: celebrities, repository: repository)),
                );
              },
              child: Text('更多（${celebrities.length}）'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 108,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final c in shown)
              Builder(
                builder: (context) => GestureDetector(
                  onTap: () => _openCelebrity(context, repository, c),
                  child: Container(
                    width: 76,
                    margin: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        _celebrityAvatar(c, 30),
                        const SizedBox(height: 6),
                        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                        if (c.character != null && c.character!.isNotEmpty)
                          Text(c.character!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
            if (celebrities.length > previewCount)
              Builder(
                builder: (context) => GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => _CelebrityListPage(celebrities: celebrities, repository: repository)),
                    );
                  },
                  child: const SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        CircleAvatar(radius: 30, child: Icon(Icons.more_horiz)),
                        SizedBox(height: 6),
                        Text('更多', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _CelebrityListPage extends StatelessWidget {
  const _CelebrityListPage({required this.celebrities, required this.repository});

  final List<Celebrity> celebrities;
  final DoubanRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全部影人')),
      body: ListView.builder(
        itemCount: celebrities.length,
        itemBuilder: (context, i) {
          final c = celebrities[i];
          return ListTile(
            leading: _celebrityAvatar(c, 20),
            title: Text(c.name),
            subtitle: c.character == null || c.character!.isEmpty ? null : Text(c.character!),
            onTap: () => _openCelebrity(context, repository, c),
          );
        },
      ),
    );
  }
}

/// Photos preview: first 10 in a grid, with 更多 to the full
/// paged list when there are more.
Widget _photosPreview(BuildContext context, SubjectDetail detail, DoubanRepository repository) {
  if (detail.photos.isEmpty) return const SizedBox.shrink();
  const previewCount = 10;
  final shown = detail.photos.length > previewCount ? detail.photos.sublist(0, previewCount) : detail.photos;
  final hasMore = detail.photosTotal > shown.length || detail.photos.length > previewCount;
  final urls = detail.photos.map((p) => p.url).whereType<String>().toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      Row(
        children: [
          Text('剧照${detail.photosTotal > 0 ? '（${detail.photosTotal}）' : ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (hasMore)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _PhotosPage(
                      repository: repository,
                      type: detail.subject.type,
                      id: detail.subject.id,
                      initialItems: detail.photos,
                      total: detail.photosTotal,
                    ),
                  ),
                );
              },
              child: const Text('更多'),
            ),
        ],
      ),
      const SizedBox(height: 8),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
        itemCount: shown.length,
        itemBuilder: (_, i) {
          final p = shown[i];
          final displayUrl = photoImageUrl(p, SettingsStore.instance.imageQuality);
          if (displayUrl == null) return const Icon(Icons.image_outlined);
          final index = p.url == null ? 0 : urls.indexOf(p.url!);
          return GestureDetector(
            onTap: () => _openImagePreview(context, urls, index < 0 ? 0 : index),
            child: Hero(
              tag: p.url!,
              child: CachedNetworkImage(imageUrl: displayUrl, httpHeaders: doubanImageHeaders, fit: BoxFit.cover, errorWidget: (context, url, error) => const Icon(Icons.image_outlined)),
            ),
          );
        },
      ),
    ],
  );
}

class _PhotosPage extends StatelessWidget {
  const _PhotosPage({required this.repository, required this.type, required this.id, required this.initialItems, required this.total});

  final DoubanRepository repository;
  final String type;
  final String id;
  final List<Photo> initialItems;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全部剧照')),
      body: _PagedPhotos(repository: repository, type: type, id: id, initialItems: initialItems, total: total, fillViewport: true),
    );
  }
}

/// Paged long reviews. Tap a review to open its full text page.
/// Same ListView.builder paging pattern as _PagedComments.
class _PagedReviews extends StatefulWidget {
  const _PagedReviews({
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
  final List<Review> initialItems;
  final int total;
  final bool fillViewport;

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
          if (result.items.isEmpty) _total = _items.length;
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
    return ListView.builder(
      shrinkWrap: !widget.fillViewport,
      physics: widget.fillViewport ? null : const NeverScrollableScrollPhysics(),
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return LoadMoreFooter(
            countText: _total > 0 ? '已加载 ${_items.length} / $_total' : null,
            canLoadMore: () => !_loadingMore && hasMore,
            onLoadMore: _loadMore,
          );
        }
        final r = _items[i];
        return ListTile(
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
        );
      },
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
          if (result.items.isEmpty) _total = _items.length;
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
    final hasMore = _total > 0 && _items.length < _total;
    final footer = LoadMoreFooter(
      countText: _total > 0 ? '已加载 ${_items.length} / $_total' : null,
      canLoadMore: () => !_loadingMore && hasMore,
      onLoadMore: _loadMore,
    );
    final gridSliver = SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid.builder(
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
      ),
    );
    if (widget.fillViewport) {
      return CustomScrollView(slivers: [gridSliver, SliverToBoxAdapter(child: footer)]);
    }
    return CustomScrollView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      slivers: [gridSliver, SliverToBoxAdapter(child: footer)],
    );
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

class _MobileDetail extends StatefulWidget {
  const _MobileDetail({required this.detail, required this.repository});

  final SubjectDetail detail;
  final DoubanRepository repository;

  @override
  State<_MobileDetail> createState() => _MobileDetailState();
}

class _MobileDetailState extends State<_MobileDetail> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final repository = widget.repository;
    // NestedScrollView with a pinned tab header: the info sections
    // scroll away, but the 相关视频 / 评论 switch stays at the top
    // while the tab content scrolls beneath it. (Previously the
    // TabBar lived inside the page ListView and scrolled away with
    // the content, so switching tabs mid-comments meant scrolling
    // all the way back up.) Each tab keeps its own scroll offset
    // via its PageStorageKey when switching back and forth.
    return NestedScrollView(
      headerSliverBuilder: (_, __) => [
        SliverToBoxAdapter(
          child: Column(
            children: [
              _header(detail),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(detail.summary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _trailersPreview(context, detail.trailers),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _celebritiesRow(context, detail.celebrities, repository),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _photosPreview(context, detail, repository),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedTabBarDelegate(
            TabBar(
              controller: _tabController,
              tabs: const [Tab(text: '相关视频'), Tab(text: '评论')],
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: [
          ListView(
            key: const PageStorageKey('mobile-related'),
            children: [_relatedSection(detail, repository)],
          ),
          ListView(
            key: const PageStorageKey('mobile-comments'),
            children: [_commentsSection(detail, repository)],
          ),
        ],
      ),
    );
  }
}

/// Pinned tab header for the mobile detail page: exactly the
/// TabBar's own height, so the bar sticks to the top without a gap
/// or a clip once the info sections have scrolled away.
class _PinnedTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _PinnedTabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_PinnedTabBarDelegate oldDelegate) => tabBar != oldDelegate.tabBar;
}

/// Right-tab content: related subjects (tap navigates to their
/// detail page — previously a no-op) plus read-only related doulists
/// (no doulist page exists yet, so doulist rows stay non-navigating).
Widget _relatedSection(SubjectDetail detail, DoubanRepository repository) {
  if (detail.recommendations.isEmpty && detail.doulists.isEmpty) {
    return const EmptyState(message: '暂无相关推荐');
  }
  return Column(
    children: [
      for (final s in detail.recommendations)
        Builder(
          builder: (context) => SubjectRow(
            subject: s,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SubjectPage(
                    repository: repository,
                    type: s.type.isNotEmpty ? s.type : detail.subject.type,
                    id: s.id,
                  ),
                ),
              );
            },
          ),
        ),
      if (detail.doulists.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('相关豆列', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        for (final s in detail.doulists)
          ListTile(title: Text(s.title), subtitle: Text('豆列 · ${s.doulistCount ?? ''} 条')),
      ],
    ],
  );
}

/// Right-tab content: short comments then long reviews, each paged
/// with auto-load. Sections shrink-wrap inside the tab scroll view.
Widget _commentsSection(SubjectDetail detail, DoubanRepository repository) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('短评', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      _PagedComments(repository: repository, type: detail.subject.type, id: detail.subject.id, initialItems: detail.comments, total: detail.commentsTotal, fillViewport: false),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text('长评', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      _PagedReviews(repository: repository, type: detail.subject.type, id: detail.subject.id, initialItems: detail.reviews, total: detail.reviewsTotal, fillViewport: false),
    ],
  );
}

class _DesktopDetail extends StatelessWidget {
  const _DesktopDetail({required this.detail, required this.repository});

  final SubjectDetail detail;
  final DoubanRepository repository;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left 3/4: subject info, trailers, celebrities, photos.
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _header(detail),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(detail.summary),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _trailersPreview(context, detail.trailers),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _celebritiesRow(context, detail.celebrities, repository),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _photosPreview(context, detail, repository),
                ),
              ],
            ),
          ),
          // Right 1/4: tabbed related videos / comments.
          Expanded(
            flex: 1,
            child: Column(
              children: [
                const TabBar(tabs: [Tab(text: '相关视频'), Tab(text: '评论')]),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(children: [_relatedSection(detail, repository)]),
                      ListView(children: [_commentsSection(detail, repository)]),
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
}
