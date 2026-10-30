import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Full-screen image gallery, modeled on c001apk's ImageViewPage:
/// PageView + PhotoView zoom, AppBar shows "current / total", desktop
/// left/right arrows switch pages, long-press shows a menu.
/// Save / share are NOT here yet (they need saver_gallery / share_plus
/// plus Android permissions); the menu currently only copies the link.
class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({super.key, required this.urls, this.initialIndex = 0});

  final List<String> urls;
  final int initialIndex;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late final PageController _pageController;
  late int _current;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _changePage(int delta) {
    if (_menuOpen || !_pageController.hasClients || widget.urls.isEmpty) return;
    final current = (_pageController.page ?? _current.toDouble()).round();
    final next = (current + delta).clamp(0, widget.urls.length - 1);
    if (next == current) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 255),
      curve: Curves.ease,
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        _menuOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _changePage(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _changePage(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _showMenu() async {
    if (_menuOpen || widget.urls.isEmpty) return;
    _menuOpen = true;
    final url = widget.urls[_current];
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('复制图片链接', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('链接已复制')),
                  );
                },
              ),
              ListTile(
                title: const Text('取消', style: TextStyle(fontSize: 14)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
    } finally {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            widget.urls.isEmpty ? '0/0' : '${_current + 1}/${widget.urls.length}',
          ),
        ),
        body: widget.urls.isEmpty
            ? const Center(
                child: Text('暂无图片', style: TextStyle(color: Colors.white)),
              )
            : GestureDetector(
                onLongPress: _showMenu,
                onSecondaryTap: _showMenu,
                child: PhotoViewGallery.builder(
                  backgroundDecoration: const BoxDecoration(color: Colors.black),
                  scrollPhysics: const BouncingScrollPhysics(),
                  builder: (context, index) => PhotoViewGalleryPageOptions(
                    imageProvider: CachedNetworkImageProvider(widget.urls[index]),
                    initialScale: PhotoViewComputedScale.contained,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 8,
                    heroAttributes: PhotoViewHeroAttributes(tag: widget.urls[index]),
                  ),
                  itemCount: widget.urls.length,
                  loadingBuilder: (context, event) => Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: event == null || event.expectedTotalBytes == null
                            ? null
                            : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                      ),
                    ),
                  ),
                  pageController: _pageController,
                  onPageChanged: (index) => setState(() => _current = index),
                ),
              ),
      ),
    );
  }
}
