// lib/utils/video_player_manager.dart

import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../model/post.dart'; // Post クラスをインポート

class VideoPlayerManager {
  final List<Post> _items = []; // 投稿リストを保持

  // 動画再生に関する状態
  final Map<int, double> _visible = {};
  final Set<int> _activeIds = <int>{};
  final Map<int, YoutubePlayerController> _controllers = {};

  // 動画IDからYouTubeのIDを取得するヘルパー関数
  String? youtubeIdOf(String? videoUrl) {
    final raw = (videoUrl ?? "").trim();
    if (raw.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(raw) ?? raw;
  }

  // 最大2つまで再生
  void setActiveIds(Set<int> next) {
    if (_activeIds.containsAll(next)) return;

    final prev = Set<int>.from(_activeIds);
    _activeIds.clear();
    _activeIds.addAll(next);

    // 停止と破棄
    for (final id in prev.difference(next)) {
      final controller = _controllers.remove(id);
      controller?.pause();
      controller?.dispose();
    }

    // 新しい動画を生成
    for (final id in next.difference(prev)) {
      final post = _items.firstWhere(
        (p) => p.id == id,
        orElse: () => null,
      ); // _itemsリストからPostを取得
      final ytId = post != null
          ? _youtubeIdOf(post.youtubeId) // PostからYouTube IDを取得
          : null;

      if (ytId != null) {
        _controllers[id] = _createController(ytId);
      }
    }

    // すべてのコントローラーでミュートと再生
    for (final id in next) {
      final controller = _controllers[id];
      controller?.mute();
      controller?.setVolume(0);
      controller?.play();
    }
  }

  // 画面上の動画表示率に応じて再生対象を更新
  void onVisibilityChanged(int postId, double fraction) {
    if (fraction > 0.6) {
      _visible[postId] = fraction;
      _recomputeActive();
    } else {
      _visible.remove(postId);
    }
  }

  void _recomputeActive() {
    const maxActive = 2;
    final candidates = _visible.entries
        .where((entry) => entry.value > 0.6) // 60%以上見えているもの
        .map((entry) => entry.key)
        .take(maxActive)
        .toSet();

    setActiveIds(candidates);
  }

  // 新しいYouTubeコントローラーを作成する
  YoutubePlayerController _createController(String youtubeId) {
    return YoutubePlayerController(
      initialVideoId: youtubeId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true,
        hideControls: true,
        controlsVisibleAtStart: false,
        disableDragSeek: true,
        enableCaption: false,
      ),
    );
  }

  // 投稿データの更新
  void updateItems(List<Post> posts) {
    _items.clear();
    _items.addAll(posts);
  }
}
