import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../model/post.dart';
import '../service/wp_api_service.dart';
import '../store/like_store.dart';
import 'post_detail_screen.dart';

/// ============================================================
/// TimelineScreen（ホームのタイムライン）
///
/// ✅やっていること
/// - 投稿一覧を表示する（FutureBuilder）
/// - 動画がある投稿は「一番見えてる1件だけ」自動再生する
/// - いいねは「押した瞬間に +1 / -1 で即反映」
///   → サーバー通信が終わったらサーバーの値で確定
///   → 失敗したら元に戻す
///
/// ✅ポイント
/// - いいね押したときに _reload()（全リロード）しない
///   → それが「毎回リロードが邪魔」の原因だった
/// - いいねの処理は関数 _handleLikePressed() にまとめる
/// ============================================================
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _api = WpApiService();
  late Future<List<Post>> _futurePosts;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // -----------------------
  // 動画：一番見えてる投稿ID（1件だけ再生）
  // -----------------------
  int? _activePostId;
  final Map<int, double> _visibleMapByPostId = {};
  final Map<int, YoutubePlayerController> _ytControllers = {};

  // -----------------------
  // いいね：送信中フラグ（連打防止）
  // -----------------------
  final Set<int> _likeSending = <int>{};

  // ✅ サーバーから返ってきたlike数を投稿IDごとに保持（表示用）
  //    ここがあるから「全リロードなし」で数字だけ変えられる
  final Map<int, int> _likeCountById = {};

  @override
  void initState() {
    super.initState();
    _futurePosts = _api.fetchAllPosts();
  }

  /// 引っ張って更新（手動リロード用）
  Future<void> _reload() async {
    _safeSetState(() {
      _futurePosts = _api.fetchAllPosts();
    });
  }

  bool _isNew(Post post) {
    final diff = DateTime.now().difference(post.date.toLocal());
    return diff.inDays <= 14;
  }

  String? _safeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.avif')) return null;
    return url;
  }

  /// ✅ URLでもIDでもOK（正規表現なし）
  String? _videoIdOrNull(Post post) {
    final raw = post.youtubeId ?? post.pageVideoId;
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(t) ?? t;
  }

  YoutubePlayerController _getOrCreateYtController(Post post, String videoId) {
    final existing = _ytControllers[post.id];
    if (existing != null) return existing;

    final c = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true,
        loop: true,
        hideControls: true,
        disableDragSeek: true,
        controlsVisibleAtStart: false,
      ),
    );

    _ytControllers[post.id] = c;
    return c;
  }

  /// ============================================================
  /// ✅ いいね：押した瞬間に数字を +1/-1 して体感を良くする
  ///
  /// - LikeStore.toggle(post) で「ハート色」は即変わる
  /// - _likeCountById[post.id] で「数字」も即変える
  /// - サーバー通信成功 → サーバーの値で確定
  /// - 失敗 → 元に戻す
  ///
  /// ※注意：あなたのAPIは「like加算」だけっぽいので
  ///   - いいねONの時だけ _api.sendLike() を叩く
  ///   - OFFはローカル表示だけ（サーバー側のunlikeがないため）
  /// ============================================================
  Future<void> _handleLikePressed(Post post) async {
    final postId = post.id;

    // 送信中なら連打禁止
    if (_likeSending.contains(postId)) return;

    final wasLiked = LikeStore.isLiked(post);

    // 現在表示しているlike数（サーバー確定値があればそれを優先）
    final beforeCount = _likeCountById[postId] ?? post.likeCount;

    // 押した瞬間の「体感」用（+1/-1）
    final optimisticCount = (beforeCount + (wasLiked ? -1 : 1)).clamp(0, 1 << 31);

    // ✅ まずUIを即更新（ここで体感が良くなる）
    _safeSetState(() {
      _likeSending.add(postId);
      LikeStore.toggle(post); // ハートを即反転
      _likeCountById[postId] = optimisticCount; // 数字も即反映
    });

    try {
      // サーバーに送るのは「いいねON」の時だけ
      if (!wasLiked) {
        final newCount = await _api.sendLike(postId);

        if (!mounted) return;
        _safeSetState(() {
          _likeCountById[postId] = newCount; // ✅ サーバーの値で確定
        });
      }
    } catch (e) {
      debugPrint('Like error: $e');
      if (!mounted) return;

      // 失敗したら元に戻す
      _safeSetState(() {
        LikeStore.toggle(post); // 反転したのを戻す
        _likeCountById[postId] = beforeCount; // 数字も戻す
      });
    } finally {
      if (!mounted) return;
      _safeSetState(() {
        _likeSending.remove(postId);
      });
    }
  }

  /// ============================================================
  /// 動画：VisibilityDetectorで「一番見えてる投稿」をactiveにする
  /// ============================================================
  void _onVisibilityChanged(int postId, double visibleFraction) {
    if (visibleFraction <= 0) {
      _visibleMapByPostId.remove(postId);
    } else {
      _visibleMapByPostId[postId] = visibleFraction;
    }

    int? maxPostId;
    double maxVisible = 0.0;

    _visibleMapByPostId.forEach((id, v) {
      if (v > maxVisible) {
        maxVisible = v;
        maxPostId = id;
      }
    });

    // ✅ いちばん見えてるのが 30% 以上のときだけ active 更新
    if (maxPostId != null && maxPostId != _activePostId && maxVisible > 0.3) {
      _safeSetState(() => _activePostId = maxPostId);

      // ✅ active 以外はpause+dispose（=絶対再生しない）
      _ytControllers.removeWhere((id, c) {
        final remove = id != _activePostId;
        if (remove) {
          c.pause();
          c.dispose();
        }
        return remove;
      });
    }
  }

  Widget _newBadge() {
    return Positioned(
      top: 8,
      left: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// カード上部：動画があれば動画（activeの1件だけ再生）／なければ画像
  Widget? _buildTopMedia(Post post) {
    final vid = _videoIdOrNull(post);

    // ---- 動画がある場合 ----
    if (vid != null) {
      // activeの時だけプレイヤーを出す（=1件だけ再生）
      if (_activePostId == post.id) {
        final controller = _getOrCreateYtController(post, vid);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_activePostId == post.id) {
            controller.play();
          }
        });

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: YoutubePlayer(controller: controller, showVideoProgressIndicator: false),
              ),
              if (_isNew(post)) _newBadge(),
            ],
          ),
        );
      }

      // activeじゃない：サムネだけ
      final thumb = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
              ),
            ),
            if (_isNew(post)) _newBadge(),
          ],
        ),
      );
    }

    // ---- 動画がない場合：画像 ----
    final img = _safeImageUrl(post.imageUrl);
    if (img == null) return null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: CachedNetworkImage(
              imageUrl: img,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => const Center(child: Icon(Icons.broken_image)),
            ),
          ),
          if (_isNew(post)) _newBadge(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _likeSending.clear();
    for (final c in _ytControllers.values) {
      c.dispose();
    }
    _ytControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<List<Post>>(
        future: _futurePosts,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('読み込みエラー: ${snapshot.error}'));
          }

          final all = snapshot.data ?? [];
          final posts = all.where((p) => p.showInHomepage == true).toList();

          // 空でも引っ張って更新できるようにする
          if (posts.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('まだ投稿がありません')),
              ],
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];

              final liked = LikeStore.isLiked(post);
              final sending = _likeSending.contains(post.id);

              final topMedia = _buildTopMedia(post);

              return VisibilityDetector(
                key: Key('post-${post.id}'),
                onVisibilityChanged: (info) {
                  _onVisibilityChanged(post.id, info.visibleFraction);
                },
                child: InkWell(
                  onTap: () {
                    Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (topMedia != null) topMedia,
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      post.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${post.date.toLocal()}'.split(' ').first,
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      // ✅ 表示は「サーバー確定値があればそれ優先」
                                      'いいね！${_likeCountById[post.id] ?? post.likeCount}件',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ✅ いいねボタン：リロードしない / 即増減
                              IconButton(
                                icon: Icon(
                                  liked ? Icons.favorite : Icons.favorite_border,
                                  color: liked ? Colors.red : Colors.grey,
                                ),
                                onPressed: sending ? null : () => _handleLikePressed(post),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
