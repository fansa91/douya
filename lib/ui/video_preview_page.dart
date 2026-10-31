import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';

/// Video preview for Frodo trailers. The video_url comes from the
/// subject detail's `trailers` field at runtime (verified 2026-10-31
/// for movie 1292052: trailers[0].video_url is an mp4) — it is never
/// hard-coded, because Frodo trailer URLs are time-limited.
/// c001apk has no video player (it only carries a videoUrl field),
/// so this page is douya's own design, not a c001apk copy:
///   - dedicated full-screen page (not inline in the detail page,
///     where a scrollable layout makes controller lifecycle fragile)
///   - cover poster while loading, loading error with retry + a
///     "go back to the detail page" hint (an expired trailer URL
///     can only be refreshed by re-entering the detail page)
///   - tap toggles controls, controls auto-hide 3s while playing
///   - double-tap left/right seeks -/+10s, slider seeks freely
///   - playback speed menu (0.5 / 1 / 1.25 / 1.5 / 2)
///   - prev/next across the subject's whole trailer list, without
///     going back to the detail page
///   - mobile fullscreen locks landscape (restored on exit/dispose);
///     desktop shortcuts: Space play/pause, Left/Right -/+5s,
///     F fullscreen, Esc exits fullscreen
///   - pauses when the app goes to background
///   - AppBar: copy link / open in browser (trailer URLs expire,
///     so the user may want to open one elsewhere before it does)
class VideoPreviewPage extends StatefulWidget {
  const VideoPreviewPage({super.key, required this.trailers, this.initialIndex = 0});

  final List<Trailer> trailers;
  final int initialIndex;

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> with WidgetsBindingObserver {
  static const _speeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  late int _index;
  VideoPlayerController? _controller;
  String? _error;
  bool _showControls = true;
  bool _isFullscreen = false;
  double _speed = 1.0;
  Timer? _hideTimer;

  Trailer get _trailer => widget.trailers[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.trailers.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.trailers.length - 1);
    _initCurrent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _controller?.pause();
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onTick);
      await controller.dispose();
    }
  }

  Future<void> _initCurrent() async {
    await _disposeController();
    if (widget.trailers.isEmpty) {
      if (mounted) setState(() => _error = '该条目没有预告片');
      return;
    }
    final url = _trailer.videoUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _error = '该预告没有可播放的视频地址');
      return;
    }
    if (mounted) {
      setState(() {
        _error = null;
        _speed = 1.0;
        _showControls = true;
      });
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setPlaybackSpeed(_speed);
      await controller.play();
      controller.addListener(_onTick);
      if (mounted) setState(() {});
      _scheduleHide();
    } catch (_) {
      if (mounted) setState(() => _error = '视频加载失败');
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controller?.value.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
      _scheduleHide();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(Duration offset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final target = controller.value.position + offset;
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > controller.value.duration
            ? controller.value.duration
            : target;
    await controller.seekTo(clamped);
    setState(() => _showControls = true);
    _scheduleHide();
  }

  void _onDoubleTap(TapDownDetails details) {
    // Double-tap delays the single-tap toggle slightly; that is the
    // standard trade-off for having both gestures on one surface.
    final width = MediaQuery.sizeOf(context).width;
    _seekBy(details.globalPosition.dx < width / 2 ? const Duration(seconds: -10) : const Duration(seconds: 10));
  }

  Future<void> _switchTrailer(int delta) async {
    final next = _index + delta;
    if (next < 0 || next >= widget.trailers.length || next == _index) return;
    setState(() => _index = next);
    await _initCurrent();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await _controller?.setPlaybackSpeed(speed);
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (mounted) setState(() => _isFullscreen = !_isFullscreen);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed || keyboard.isControlPressed || keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _seekBy(const Duration(seconds: -5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _seekBy(const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape && _isFullscreen) {
      _toggleFullscreen();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    // Always restore orientations, even if the page is left fullscreen.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _openInBrowser(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查浏览器设置')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查浏览器设置')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (widget.trailers.isEmpty) {
      return const Scaffold(body: Center(child: Text('该条目没有预告片')));
    }
    final trailer = _trailer;
    final title = trailer.title.isNotEmpty ? trailer.title : '预告片';
    final titleWithIndex = widget.trailers.length > 1 ? '$title (${_index + 1}/${widget.trailers.length})' : title;
    final videoUrl = trailer.videoUrl;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _isFullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(titleWithIndex),
                actions: [
                  if (videoUrl != null && videoUrl.isNotEmpty) ...[
                    IconButton(
                      icon: const Icon(Icons.link),
                      tooltip: '复制视频链接',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: videoUrl));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('链接已复制')));
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_browser),
                      tooltip: '在浏览器中打开',
                      onPressed: () => _openInBrowser(videoUrl),
                    ),
                  ],
                ],
              ),
        body: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 8),
                      const Text(
                        '预告地址有时效，返回详情重新打开可获取新地址；也可能是网络问题。',
                        style: TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FilledButton(onPressed: _initCurrent, child: const Text('重试')),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('返回', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            : controller == null || !controller.value.isInitialized
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      if (trailer.coverUrl != null && trailer.coverUrl!.isNotEmpty)
                        Image.network(
                          trailer.coverUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                        ),
                      const CircularProgressIndicator(color: Colors.white),
                    ],
                  )
                : GestureDetector(
                    onTap: _toggleControls,
                    onDoubleTapDown: _onDoubleTap,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                        if (_showControls && !controller.value.isPlaying)
                          IconButton(
                            iconSize: 64,
                            color: Colors.white,
                            onPressed: _togglePlay,
                            icon: const Icon(Icons.play_arrow),
                          ),
                        if (_isFullscreen && _showControls)
                          Positioned(
                            top: 16,
                            right: 16,
                            child: IconButton(
                              color: Colors.white,
                              tooltip: '退出全屏',
                              onPressed: _toggleFullscreen,
                              icon: const Icon(Icons.fullscreen_exit),
                            ),
                          ),
                        if (_showControls)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 24,
                            child: Row(
                              children: [
                                IconButton(
                                  color: Colors.white,
                                  tooltip: '上一个预告',
                                  onPressed: _index > 0 ? () => _switchTrailer(-1) : null,
                                  icon: const Icon(Icons.skip_previous),
                                ),
                                IconButton(
                                  color: Colors.white,
                                  onPressed: _togglePlay,
                                  icon: Icon(
                                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                  ),
                                ),
                                IconButton(
                                  color: Colors.white,
                                  tooltip: '下一个预告',
                                  onPressed: _index < widget.trailers.length - 1 ? () => _switchTrailer(1) : null,
                                  icon: const Icon(Icons.skip_next),
                                ),
                                Text(
                                  _format(controller.value.position),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: controller.value.position.inMilliseconds.toDouble().clamp(
                                          0,
                                          controller.value.duration.inMilliseconds.toDouble(),
                                        ),
                                    max: controller.value.duration.inMilliseconds.toDouble(),
                                    onChanged: (value) {
                                      controller.seekTo(Duration(milliseconds: value.toInt()));
                                    },
                                  ),
                                ),
                                Text(
                                  _format(controller.value.duration),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                PopupMenuButton<double>(
                                  tooltip: '倍速',
                                  icon: Text('${_speed}x', style: const TextStyle(color: Colors.white)),
                                  onSelected: _setSpeed,
                                  itemBuilder: (context) => [
                                    for (final s in _speeds)
                                      PopupMenuItem<double>(
                                        value: s,
                                        child: Text('${s}x${s == _speed ? ' ✓' : ''}'),
                                      ),
                                  ],
                                ),
                                IconButton(
                                  color: Colors.white,
                                  tooltip: _isFullscreen ? '退出全屏' : '全屏',
                                  onPressed: _toggleFullscreen,
                                  icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
