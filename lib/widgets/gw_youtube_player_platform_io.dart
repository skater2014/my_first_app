import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'gw_youtube_player_stub.dart' as stub;

Widget buildGwYoutubePlayer({
  required BuildContext context,
  required String videoId,
  required bool autoPlay,
  required bool mute,
  required bool useAspectRatio,
  required bool useCard,
}) {
  // ✅ macOS/Windows/Linux は YouTube iframe を作らない（エラー153回避）
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    return stub.buildGwYoutubePlayer(
      context: context,
      videoId: videoId,
      autoPlay: autoPlay,
      mute: mute,
      useAspectRatio: useAspectRatio,
      useCard: useCard,
    );
  }

  // ✅ iOS/Android だけ youtube_player_iframe
  return _GwYoutubeMobile(
    videoId: videoId,
    autoPlay: autoPlay,
    mute: mute,
    useAspectRatio: useAspectRatio,
    useCard: useCard,
  );
}

class _GwYoutubeMobile extends StatefulWidget {
  const _GwYoutubeMobile({
    required this.videoId,
    required this.autoPlay,
    required this.mute,
    required this.useAspectRatio,
    required this.useCard,
  });

  final String videoId;
  final bool autoPlay;
  final bool mute;
  final bool useAspectRatio;
  final bool useCard;

  @override
  State<_GwYoutubeMobile> createState() => _GwYoutubeMobileState();
}

class _GwYoutubeMobileState extends State<_GwYoutubeMobile> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();

    _controller = YoutubePlayerController(
      params: YoutubePlayerParams(
        mute: widget.mute,
        showControls: false,
        showFullscreenButton: false,
        playsInline: true,
        strictRelatedVideos: true,
      ),
    );

    // ✅ autoplay は params じゃなく load/cue で制御（5.2.2安定）
    if (widget.autoPlay) {
      _controller.loadVideoById(videoId: widget.videoId);
    } else {
      _controller.cueVideoById(videoId: widget.videoId);
    }
  }

  @override
  void didUpdateWidget(covariant _GwYoutubeMobile oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.videoId != widget.videoId) {
      if (widget.autoPlay) {
        _controller.loadVideoById(videoId: widget.videoId);
      } else {
        _controller.cueVideoById(videoId: widget.videoId);
      }
    }
    if (oldWidget.mute != widget.mute) {
      widget.mute ? _controller.mute() : _controller.unMute();
    }
    if (oldWidget.autoPlay != widget.autoPlay) {
      widget.autoPlay ? _controller.playVideo() : _controller.pauseVideo();
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body = YoutubePlayer(controller: _controller);

    if (widget.useAspectRatio) {
      body = AspectRatio(aspectRatio: 16 / 9, child: body);
    }

    // ✅ スクロール/Like を奪わない
    body = IgnorePointer(ignoring: true, child: body);

    if (!widget.useCard) return body;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}
