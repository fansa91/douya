import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';

/// Video preview for a Frodo trailer. The video_url comes from the
/// subject detail's `trailers` field at runtime (verified 2026-10-31
/// for movie 1292052: trailers[0].video_url is an mp4) — it is never
/// hard-coded, because Frodo trailer URLs are time-limited.
/// Controls auto-hide 3 seconds after the last tap, like weiyue's
/// player auto-hide; tap anywhere to bring them back.
class VideoPreviewPage extends StatefulWidget {
  const VideoPreviewPage({super.key, required this.trailer});

  final Trailer trailer;

  @override
  State<VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<VideoPreviewPage> {
  VideoPlayerController? _controller;
  String? _error;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = widget.trailer.videoUrl;
    if (url == null || url.isEmpty) {
      setState(() => _error = '该预告没有可播放的视频地址');
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.play();
      controller.addListener(_onTick);
      if (mounted) setState(() {});
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = '视频加载失败：$e');
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
    setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final title = widget.trailer.title.isNotEmpty
        ? widget.trailer.title
        : '预告片';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: _error != null
          ? Center(
              child: Text(_error!, style: const TextStyle(color: Colors.white)),
            )
          : controller == null || !controller.value.isInitialized
              ? const Center(child: CircularProgressIndicator())
              : GestureDetector(
                  onTap: _toggleControls,
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
                      if (_showControls)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 24,
                          child: Row(
                            children: [
                              IconButton(
                                color: Colors.white,
                                onPressed: _togglePlay,
                                icon: Icon(
                                  controller.value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                              Text(
                                _format(controller.value.position),
                                style: const TextStyle(color: Colors.white),
                              ),
                              Expanded(
                                child: Slider(
                                  value: controller.value.position.inMilliseconds
                                      .toDouble()
                                      .clamp(
                                        0,
                                        controller.value.duration.inMilliseconds.toDouble(),
                                      ),
                                  max: controller.value.duration.inMilliseconds.toDouble(),
                                  onChanged: (value) {
                                    controller.seekTo(
                                      Duration(milliseconds: value.toInt()),
                                    );
                                  },
                                ),
                              ),
                              Text(
                                _format(controller.value.duration),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
