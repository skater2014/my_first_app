import 'package:flutter/material.dart';
import '../widgets/gw_youtube_player.dart';

class YoutubeTestScreen extends StatelessWidget {
  const YoutubeTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube TEST')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: GwYoutubePlayer(
              videoId: 'auQKdUUlbA0',
              autoplay: true,
              mute: true,
              showYoutubeControls: true,
              useCard: false, // ← iOS/Androidで白くなる回避テスト
            ),
          ),
        ),
      ),
    );
  }
}
