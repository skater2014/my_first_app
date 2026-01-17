import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

Widget buildGwYoutubePlayer({
  required BuildContext context,
  required String videoId,
  required bool autoPlay,
  required bool mute,
  required bool useAspectRatio,
  required bool useCard,
}) {
  return _GwYoutubeWeb(
    videoId: videoId,
    autoPlay: autoPlay,
    mute: mute,
    useAspectRatio: useAspectRatio,
    useCard: useCard,
  );
}

class _GwYoutubeWeb extends StatefulWidget {
  const _GwYoutubeWeb({
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
  State<_GwYoutubeWeb> createState() => _GwYoutubeWebState();
}

class _GwYoutubeWebState extends State<_GwYoutubeWeb> {
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

    if (widget.autoPlay) {
      _controller.loadVideoById(videoId: widget.videoId);
    } else {
      _controller.cueVideoById(videoId: widget.videoId);
    }
  }

  @override
  void didUpdateWidget(covariant _GwYoutubeWeb oldWidget) {
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

    body = IgnorePointer(ignoring: true, child: body);

    if (!widget.useCard) return body;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}
