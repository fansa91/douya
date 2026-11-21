import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models/models.dart';
import 'image_preview_page.dart';
import 'widgets.dart';

/// The photo wall: every photo for a celebrity in a 3-column grid,
/// paged. Cells are square and the photo is contained (BoxFit.
/// contain), so a landscape photo is letterboxed, not cropped to
/// the old 110×150 portrait box — the thumbnail keeps its original
/// aspect ratio. Tapping a photo opens the existing image preview
/// over the photos loaded so far.
class CelebrityPhotosPage extends StatefulWidget {
  const CelebrityPhotosPage({
    super.key,
    required this.repository,
    required this.id,
    required this.name,
  });

  final DoubanRepository repository;
  final String id;

  /// Celebrity name, for the AppBar title.
  final String name;

  @override
  State<CelebrityPhotosPage> createState() => _CelebrityPhotosPageState();
}

class _CelebrityPhotosPageState extends State<CelebrityPhotosPage> {
  List<CelebrityPhoto> _photos = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    try {
      final result = await widget.repository.fetchCelebrityPhotos(widget.id, count: 20);
      if (!mounted) return;
      setState(() {
        _photos = result.photos;
        _total = result.total;
        _loading = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.repository.fetchCelebrityPhotos(widget.id, start: _photos.length, count: 20);
      if (!mounted) return;
      final seen = _photos.map((p) => p.id).toSet();
      setState(() {
        _photos = [..._photos, ...result.photos.where((p) => seen.add(p.id))];
        if (result.total > 0) _total = result.total;
        if (result.photos.isEmpty) _total = _photos.length;
        _loadMoreFailed = false;
      });
    } catch (e) {
      debugPrint('$e');
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('剧照${_total > 0 ? '（$_total）' : ''}'),
      ),
      body: _loading
          ? const LoadingList()
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('加载失败'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _failed = false;
                          });
                          _loadFirst();
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : _photos.isEmpty
                  ? const EmptyState(message: '暂无剧照')
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.all(16),
                          sliver: SliverGrid.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 1,
                            ),
                            itemCount: _photos.length,
                            itemBuilder: (context, i) => _cell(context, _photos[i], i),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: LoadMoreFooter(
                            key: const ValueKey('celebrity-photos-footer'),
                            canLoadMore: () => !_loadingMore && _photos.length < _total,
                            onLoadMore: _loadMore,
                            failed: _loadMoreFailed,
                            countText: _total > 0 ? '已加载 ${_photos.length} / $_total' : null,
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _cell(BuildContext context, CelebrityPhoto photo, int index) {
    final url = photo.imageUrl;
    final urls = _photos.map((p) => p.imageUrl).whereType<String>().toList();
    return GestureDetector(
      onTap: url == null
          ? null
          : () {
              final previewIndex = urls.indexOf(url);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ImagePreviewPage(
                    urls: urls,
                    initialIndex: previewIndex < 0 ? 0 : previewIndex,
                  ),
                ),
              );
            },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: url == null
            ? const Icon(Icons.image_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: url,
                  httpHeaders: doubanImageHeaders,
                  fit: BoxFit.contain,
                  errorWidget: (context, url, error) => const Icon(Icons.image_outlined),
                ),
              ),
      ),
    );
  }
}
