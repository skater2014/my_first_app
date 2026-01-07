import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../model/post.dart';
import '../service/wp_api_service.dart';
import '../store/like_store.dart';
import 'post_detail_screen.dart';

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

  int? _activePostId;
  final Map<int, double> _visibleMapByPostId = {};

  final Set<int> _likeSending = <int>{};

  // ✅ active の1件だけプレイヤーを持つ（複数再生しない）
  final Map<int, YoutubePlayerController> _ytControllers = {};

  @override
  void initState() {
    super.initState();
    _futurePosts = _api.fetchAllPosts();
  }

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

  // ✅ URLでもIDでもOK（正規表現なし）
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
        autoPlay: true, // ✅ active になったら自動再生
        mute: true, // ✅ 勝手に爆音事故防止（必要なら後で false）
        loop: true,
        hideControls: true, // ✅ 再生UIいらない
        disableDragSeek: true,
        controlsVisibleAtStart: false,
      ),
    );

    _ytControllers[post.id] = c;
    return c;
  }

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

      // ✅ active 以外は「絶対再生しない」＝ pause + dispose
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
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// ✅ カード上部：動画があれば動画（active の1件だけ自動再生）／なければ画像
  Widget? _buildTopMedia(Post post) {
    final vid = _videoIdOrNull(post);

    // ---- 動画がある場合 ----
    if (vid != null) {
      // active の時だけプレイヤーを出す（＝1件だけ再生）
      if (_activePostId == post.id) {
        final controller = _getOrCreateYtController(post, vid);

        // 念のため active になった瞬間に play を叩く（autoPlay保険）
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
                child: YoutubePlayer(
                  controller: controller,
                  showVideoProgressIndicator: false,
                ),
              ),
              if (_isNew(post)) _newBadge(),
            ],
          ),
        );
      }

      // active じゃない時：YouTubeサムネだけ（▶︎マーク出さない）
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
                placeholder: (_, __) =>
                    const Center(child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) =>
                    const Center(child: Icon(Icons.broken_image)),
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
              placeholder: (_, __) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image)),
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
    return Scaffold(
      appBar: AppBar(title: const Text('GameWidth Timeline')),
      body: RefreshIndicator(
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

            if (posts.isEmpty) {
              return const Center(child: Text('まだ投稿がありません'));
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
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PostDetailScreen(post: post),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                        '${post.date.toLocal()}'
                                            .split(' ')
                                            .first,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'いいね！${post.likeCount}件',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    liked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: liked ? Colors.red : Colors.grey,
                                  ),
                                  onPressed: sending
                                      ? null
                                      : () async {
                                          final wasLiked = liked;

                                          _safeSetState(() {
                                            _likeSending.add(post.id);
                                            LikeStore.toggle(post);
                                          });

                                          if (!wasLiked) {
                                            try {
                                              await _api.sendLike(post.id);
                                              if (!mounted) return;
                                              await _reload();
                                            } catch (e) {
                                              debugPrint('Like error: $e');
                                              if (!mounted) return;
                                              _safeSetState(() {
                                                LikeStore.toggle(post);
                                              });
                                            } finally {
                                              if (!mounted) return;
                                              _safeSetState(() {
                                                _likeSending.remove(post.id);
                                              });
                                            }
                                          } else {
                                            if (!mounted) return;
                                            _safeSetState(() {
                                              _likeSending.remove(post.id);
                                            });
                                          }
                                        },
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
      ),
    );
  }
}
