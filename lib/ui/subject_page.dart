import 'package:flutter/material.dart';

import '../data/repository.dart';
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
                  child: Image.network(
                    trailers[i].coverUrl!,
                    width: 72,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.play_circle_outlined),
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
              child: s.pic == null
                  ? const Icon(Icons.book_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(s.pic!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.book_outlined)),
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

Widget _commentList(List<ShortComment> comments) {
  if (comments.isEmpty) return const EmptyState(message: '暂无短评');
  return Column(
    children: [
      for (final c in comments)
        ListTile(
          title: Text(c.userName),
          subtitle: Text(c.text, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: c.rating != null ? RatingText(rating: c.rating!, community: false) : null,
        ),
    ],
  );
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

Widget _reviewList(List<Review> reviews) {
  if (reviews.isEmpty) return const EmptyState(message: '暂无长评');
  return Column(
    children: [
      for (final r in reviews)
        ListTile(
          title: Text(r.title),
          subtitle: Text(r.abstract, maxLines: 3, overflow: TextOverflow.ellipsis),
          trailing: Text('有用 ${r.usefulCount}'),
        ),
    ],
  );
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
                ListView(children: [_commentList(detail.comments)]),
                ListView(children: [_reviewList(detail.reviews)]),
                detail.photos.isEmpty
                    ? const EmptyState(message: '暂无剧照')
                    : Builder(
                        builder: (context) {
                          final urls = detail.photos
                              .map((p) => p.url)
                              .whereType<String>()
                              .toList();
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
                            itemCount: detail.photos.length,
                            itemBuilder: (_, i) {
                              final p = detail.photos[i];
                              if (p.url == null) return const Icon(Icons.image_outlined);
                              final index = urls.indexOf(p.url!);
                              return GestureDetector(
                                onTap: () => _openImagePreview(context, urls, index < 0 ? 0 : index),
                                child: Hero(
                                  tag: p.url!,
                                  child: Image.network(p.url!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_outlined)),
                                ),
                              );
                            },
                          );
                        },
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
                      child: Image.network(detail.subject.pic!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.book_outlined)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.summary),
                _trailerSection(context, detail.trailers),
                const SizedBox(height: 24),
                const Text('短评', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                _commentList(detail.comments),
                const SizedBox(height: 24),
                const Text('长评', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                _reviewList(detail.reviews),
                if (detail.photos.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('剧照', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final urls = detail.photos
                          .map((p) => p.url)
                          .whereType<String>()
                          .toList();
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
                        itemCount: detail.photos.length,
                        itemBuilder: (_, i) {
                          final p = detail.photos[i];
                          if (p.url == null) return const Icon(Icons.image_outlined);
                          final index = urls.indexOf(p.url!);
                          return GestureDetector(
                            onTap: () => _openImagePreview(context, urls, index < 0 ? 0 : index),
                            child: Image.network(p.url!, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const Icon(Icons.image_outlined)),
                          );
                        },
                      );
                    },
                  ),
                ],
              ],
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
