import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:youtube_player_iframe/youtube_player_iframe.dart' as yti;
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as ytf;

/// ✅ Web(ブラウザ) → youtube_player_iframe (iframe)
/// ✅ iOS/Android → youtube_player_flutter
class YoutubeEmbed extends StatefulWidget {
  final String videoId;
  final String title;

  const YoutubeEmbed({
    super.key,
    required this.videoId,
    this.title = '',
  });

  @override
  State<YoutubeEmbed> createState() => _YoutubeEmbedState();
}

class _YoutubeEmbedState extends State<YoutubeEmbed> {
  ytf.YoutubePlayerController? _mobile; // mobile用
  yti.YoutubePlayerController? _web;    // web(iframe)用

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      _web = yti.YoutubePlayerController.fromVideoId(
        videoId: widget.videoId,
        params: const yti.YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          playsInline: true,
          enableJavaScript: true,
          strictRelatedVideos: true,
        ),
      );
    } else {
      _mobile = ytf.YoutubePlayerController(
        initialVideoId: widget.videoId,
        flags: const ytf.YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          enableCaption: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _mobile?.dispose();
    _web?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title.trim().isNotEmpty) ...[
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: kIsWeb
                  ? yti.YoutubePlayer(controller: _web!)
                  : ytf.YoutubePlayer(
                      controller: _mobile!,
                      showVideoProgressIndicator: true,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
