import 'package:flutter/material.dart';

import 'gw_youtube_player_stub.dart'
  if (dart.library.html) 'gw_youtube_player_web.dart'
  if (dart.library.io) 'gw_youtube_player_platform_io.dart' as impl;

class GwYoutubePlayer extends StatelessWidget {
  const GwYoutubePlayer({
    super.key,
    required this.videoId,
    this.autoPlay = false,
    this.mute = true,
    this.useAspectRatio = true,
    this.useCard = true,
  });

  final String videoId;
  final bool autoPlay;
  final bool mute;
  final bool useAspectRatio;
  final bool useCard;

  @override
  Widget build(BuildContext context) {
    return impl.buildGwYoutubePlayer(
      context: context,
      videoId: videoId,
      autoPlay: autoPlay,
      mute: mute,
      useAspectRatio: useAspectRatio,
      useCard: useCard,
    );
  }
}
