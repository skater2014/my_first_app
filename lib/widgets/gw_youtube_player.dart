import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:visibility_detector/visibility_detector.dart';

class GwYoutubePlayer extends StatefulWidget {
  const GwYoutubePlayer({
    super.key,
    required this.videoId,
    this.showOverlaySeek = false,
    this.autoplay = false,
    this.aspectRatio = 16 / 9,
    this.showYoutubeControls = false,
    this.enableTapToPlay = false,
    this.onReady,
    bool? shouldPlay,
    this.autoPlayOnVisible = false,
    this.visibleFractionToPlay = 0.65,
    this.mute = true,
    bool showControls = true,
    this.useAspectRatio = true,
    this.useCard = true,
  }) : shouldPlay = shouldPlay ?? autoplay,
       showControls = showYoutubeControls ?? showControls;

  final String videoId;
  final bool shouldPlay;
  final bool autoPlayOnVisible;
  final double visibleFractionToPlay;
  final bool mute;
  final bool showControls;
  final bool useAspectRatio;
  final bool useCard;
  final bool showOverlaySeek;
  final bool autoplay;
  final double aspectRatio;
  final bool showYoutubeControls;
  final bool enableTapToPlay;
  final VoidCallback? onReady;

  @override
  State<GwYoutubePlayer> createState() => _GwYoutubePlayerState();
}

class _GwYoutubePlayerState extends State<GwYoutubePlayer> {
  late final YoutubePlayerController _c;
  bool _visibleEnough = false;
  bool _appliedOnce = false;

  bool get _shouldPlayNow =>
      widget.autoPlayOnVisible ? _visibleEnough : widget.shouldPlay;

  @override
  void initState() {
    super.initState();
    _c = YoutubePlayerController(
      params: YoutubePlayerParams(
        mute: widget.mute,
        showControls: widget.showControls,
        showFullscreenButton: false,
        playsInline: true,
      ),
    );
    _c.loadVideoById(videoId: widget.videoId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPlayPolicy());
  }

  void _applyPlayPolicy() {
    if (!mounted) return;
    if (widget.mute) {
      _c.mute();
    } else {
      _c.unMute();
    }
    if (_shouldPlayNow) {
      _c.playVideo();
    } else {
      _c.pauseVideo();
    }
    _appliedOnce = true;
  }

  @override
  void didUpdateWidget(covariant GwYoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.videoId != widget.videoId) {
      _appliedOnce = false;
      _c.loadVideoById(videoId: widget.videoId);
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyPlayPolicy());
      return;
    }

    final changed =
        oldWidget.mute != widget.mute ||
        oldWidget.shouldPlay != widget.shouldPlay ||
        oldWidget.autoPlayOnVisible != widget.autoPlayOnVisible ||
        oldWidget.showControls != widget.showControls;

    if (!_appliedOnce || changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyPlayPolicy());
    }
  }

  @override
  void dispose() {
    _c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body = YoutubePlayer(
      controller: _c,
      aspectRatio: widget.useAspectRatio ? 16 / 9 : 16 / 9,
    );

    if (widget.useCard) {
      body = Material(
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: body,
      );
    }

    if (widget.autoPlayOnVisible) {
      body = VisibilityDetector(
        key: ValueKey('yt-vis-${widget.videoId}'),
        onVisibilityChanged: (info) {
          final frac = info.visibleFraction.clamp(0.0, 1.0);
          final next = frac >= widget.visibleFractionToPlay;
          if (next != _visibleEnough) {
            _visibleEnough = next;
            _applyPlayPolicy();
          }
        },
        child: body,
      );
    }

    return body;
  }
}
