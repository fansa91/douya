import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_view/photo_view.dart';
import 'widgets.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen image gallery, modeled on c001apk's ImageViewPage:
/// PageView + PhotoView zoom, AppBar shows "current / total", desktop
/// left/right arrows switch pages, desktop mouse-wheel zooms at the
/// cursor, long-press shows a menu with save / save-all / share /
/// copy / open-in-browser (desktop only).
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
  final _galleryKey = GlobalKey();
  final _controllers = <int, PhotoViewController>{};
  final _scaleStates = <int, PhotoViewScaleStateController>{};
  final _providers = <int, CachedNetworkImageProvider>{};
  final _imageSizes = <int, Size>{};
  final _imageListeners = <int, (ImageStream, ImageStreamListener)>{};
  bool _saving = false;

  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    for (final (stream, listener) in _imageListeners.values) {
      stream.removeListener(listener);
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final state in _scaleStates.values) {
      state.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  CachedNetworkImageProvider _providerFor(int index) {
    final provider = _providers.putIfAbsent(index, () => CachedNetworkImageProvider(widget.urls[index], headers: doubanImageHeaders));
    if (!_imageSizes.containsKey(index) && !_imageListeners.containsKey(index)) {
      final stream = provider.resolve(const ImageConfiguration());
      late final ImageStreamListener listener;
      void stopListening() {
        stream.removeListener(listener);
        _imageListeners.remove(index);
      }

      listener = ImageStreamListener((info, _) {
        _imageSizes[index] = Size(info.image.width.toDouble(), info.image.height.toDouble());
        info.dispose();
        stopListening();
      }, onError: (Object error, StackTrace? stackTrace) => stopListening());
      _imageListeners[index] = (stream, listener);
      stream.addListener(listener);
    }
    return provider;
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
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed || keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isShiftPressed) {
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

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0 || _menuOpen) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final controller = _controllers[_current];
      final imageSize = _imageSizes[_current];
      final box = _galleryKey.currentContext?.findRenderObject();
      if (controller?.scale == null || imageSize == null || box is! RenderBox || !box.hasSize) return;
      final minimum = math.min(box.size.width / imageSize.width, box.size.height / imageSize.height);
      final maximum = math.max(box.size.width / imageSize.width, box.size.height / imageSize.height) * 8;
      final scale = controller!.scale!;
      final next = (scale * math.exp((-event.scrollDelta.dy * 0.0015).clamp(-20, 20))).clamp(minimum, maximum).toDouble();
      final anchor = box.globalToLocal(event.position) - box.size.center(Offset.zero);
      controller.updateMultiple(
        scale: next,
        position: anchor - (anchor - controller.position) * (next / scale),
      );
      _scaleStates[_current]?.setInvisibly(next > minimum ? PhotoViewScaleState.zoomedIn : PhotoViewScaleState.initial);
    });
  }

  void _snack(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<bool> _requestPhotoPermission() async {
    if (Platform.isAndroid) {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk <= 32) {
        await Permission.storage.request();
        final status = await Permission.storage.status;
        if (status == PermissionStatus.denied || status == PermissionStatus.permanentlyDenied) {
          _snack('存储权限未授权', action: const SnackBarAction(label: '去设置', onPressed: openAppSettings));
          return false;
        }
        return true;
      }
    }
    await Permission.photos.request();
    final status = await Permission.photos.status;
    if (status == PermissionStatus.denied || status == PermissionStatus.permanentlyDenied) {
      _snack('相册权限未授权', action: const SnackBarAction(label: '去设置', onPressed: openAppSettings));
      return false;
    }
    return true;
  }

  Future<void> _saveImages(List<String> urls) async {
    if (_saving || urls.isEmpty) return;
    if (_isDesktop) {
      _snack('桌面端暂不支持直接保存图片，请在浏览器中打开');
      return;
    }
    if (!await _requestPhotoPermission()) return;
    setState(() => _saving = true);
    try {
      var saved = 0;
      final dio = Dio();
      for (var i = 0; i < urls.length; i++) {
        try {
          final response = await dio.get(urls[i], options: Options(responseType: ResponseType.bytes));
          final name = urls[i].split('/').last;
          // saver_gallery 3.0.10 form (c001apk's 3.0.5 used name /
          // androidExistNotSave; the resolved version renamed them).
          final result = await SaverGallery.saveImage(
            Uint8List.fromList(response.data),
            fileName: name,
            androidRelativePath: 'Pictures/douya',
            skipIfExists: true,
          );
          if (result.isSuccess) saved++;
        } catch (_) {
          // Per-image failure is counted below; keep saving the rest.
        }
      }
      _snack(saved == urls.length ? '已保存' : '已保存 $saved / ${urls.length} 张');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _shareImage(String url) async {
    try {
      final response = await Dio().get(url, options: Options(responseType: ResponseType.bytes));
      final temp = await getTemporaryDirectory();
      final path = '${temp.path}/${url.split('/').last}';
      await File(path).writeAsBytes(response.data);
      await Share.shareXFiles([XFile(path)], subject: url);
    } catch (e) {
      _snack('分享失败：$e');
    }
  }

  Future<void> _openInBrowser(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        _snack('无法打开链接，请检查浏览器设置');
      }
    } catch (_) {
      _snack('无法打开链接，请检查浏览器设置');
    }
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
                title: const Text('保存图片', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  _saveImages([url]);
                },
              ),
              if (widget.urls.length != 1)
                ListTile(
                  title: const Text('保存全部图片', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _saveImages(widget.urls);
                  },
                ),
              ListTile(
                title: const Text('分享', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  _shareImage(url);
                },
              ),
              ListTile(
                title: const Text('复制图片链接', style: TextStyle(fontSize: 14)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: url));
                  Navigator.of(context).pop();
                  _snack('链接已复制');
                },
              ),
              if (_isDesktop)
                ListTile(
                  title: const Text('在浏览器中打开', style: TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openInBrowser(url);
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
            : Stack(
                alignment: Alignment.center,
                children: [
                  Listener(
                    key: _galleryKey,
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                      onLongPress: _showMenu,
                      onSecondaryTap: _showMenu,
                      child: PhotoViewGallery.builder(
                        backgroundDecoration: const BoxDecoration(color: Colors.black),
                        scrollPhysics: const BouncingScrollPhysics(),
                        builder: (context, index) => PhotoViewGalleryPageOptions(
                          imageProvider: _providerFor(index),
                          controller: _controllers.putIfAbsent(index, PhotoViewController.new),
                          scaleStateController: _scaleStates.putIfAbsent(index, PhotoViewScaleStateController.new),
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
                  if (_saving) const CircularProgressIndicator(color: Colors.white),
                ],
              ),
      ),
    );
  }
}
