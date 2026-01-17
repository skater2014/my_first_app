import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../model/post.dart';
import '../service/wp_api_service.dart';
import '../store/like_store.dart';
import '../utils/gw_youtube.dart';
import '../widgets/gw_youtube_player.dart';

import 'post_detail_screen.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  final _api = WpApiService();
  final _scroll = ScrollController();

  // ===== paging =====
  static const int _perPage = 25;
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  List<Post> _posts = [];

  // ===== inline video =====
  int? _activePostId; // 1つだけ
  final Map<int, double> _visible = {};
  Timer? _pickDebounce;

  static const double _playThreshold = 0.62;
  static const double _stopThreshold = 0.18;

  // ✅ iOS/Androidのみ inline 再生（macOSで153を出さない）
  bool get _inlineVideoEnabled {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  // ===== like =====
  final Set<int> _likeSending = <int>{};
  final Map<int, int> _likeDelta = <int, int>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollLoadMore);
    _load(refresh: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScrollLoadMore);
    _scroll.dispose();
    _pickDebounce?.cancel();
    _visible.clear();
    _likeSending.clear();
    super.dispose();
  }

  void _onScrollLoadMore() {
    if (!_scroll.hasClients) return;
    if (_loading || _loadingMore) return;
    if (!_hasMore) return;

    final pos = _scroll.position;
    if (pos.maxScrollExtent <= 0) return;

    const threshold = 400.0;
    final reached = pos.pixels >= (pos.maxScrollExtent - threshold);
    if (!reached) return;

    _loadMore();
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _error = null;
        _loading = _posts.isEmpty;
        _loadingMore = !_posts.isEmpty;
      });
      _page = 1;
      _hasMore = true;
    } else {
      setState(() {
        _error = null;
        _loadingMore = true;
      });
    }

    try {
      final list = await _api.fetchPostsPage(
        page: _page,
        perPage: _perPage,
        homepageOnly: true,
      );

      if (!mounted) return;

      setState(() {
        if (refresh) {
          _posts = list;
        } else {
          _posts.addAll(list);
        }
        _hasMore = list.length == _perPage;
        _page += 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '読み込みエラー: $e');
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() => _load(refresh: false);

  Future<void> _refresh() async {
    _stopAllVideosNoSetState();
    await _load(refresh: true);
  }

  void _stopAllVideosNoSetState() {
    _visible.clear();
    _activePostId = null;
  }

  // -------- helpers --------
  String? _videoId(Post post) {
    final raw = (post.youtubeId ?? post.pageVideoId)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return gwExtractYoutubeId(raw);
  }

  int _likeCount(Post post) {
    final d = _likeDelta[post.id] ?? 0;
    final v = post.likeCount + d;
    return v < 0 ? 0 : v;
  }

  void _open(Post post) {
    _stopAllVideosNoSetState();
    setState(() {});
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
    );
  }

  bool _isNew(Post post) {
    final diff = DateTime.now().difference(post.date.toLocal());
    return diff.inDays <= 14;
  }

  // -------- visibility -> pick active --------
  void _onVisible(Post post, double fraction) {
    if (!_inlineVideoEnabled) return;
    final vid = _videoId(post);
    if (vid == null) return;

    if (fraction <= 0) {
      _visible.remove(post.id);
    } else {
      _visible[post.id] = fraction;
    }

    _pickDebounce?.cancel();
    _pickDebounce = Timer(const Duration(milliseconds: 90), _pickActive);
  }

  void _pickActive() {
    if (!mounted) return;

    int? maxId;
    double maxV = 0;

    _visible.forEach((id, v) {
      if (v > maxV) {
        maxV = v;
        maxId = id;
      }
    });

    if (maxId == null || maxV < _stopThreshold) {
      if (_activePostId != null) setState(() => _activePostId = null);
      return;
    }

    if (maxV >= _playThreshold && maxId != _activePostId) {
      setState(() => _activePostId = maxId);
      return;
    }

    if (_activePostId != null) {
      final activeV = _visible[_activePostId!] ?? 0.0;
      if (activeV < _stopThreshold) {
        setState(() => _activePostId = null);
      }
    }
  }

  // -------- like --------
  Future<void> _toggleLike(Post post) async {
    if (_likeSending.contains(post.id)) return;

    final liked = LikeStore.isLiked(post);

    setState(() {
      _likeSending.add(post.id);
      LikeStore.toggle(post);
      _likeDelta[post.id] = (_likeDelta[post.id] ?? 0) + (liked ? -1 : 1);
    });

    if (liked) {
      setState(() => _likeSending.remove(post.id));
      return;
    }

    try {
      await _api.sendLike(post.id);
    } catch (e) {
      debugPrint('Like error: $e');
      if (!mounted) return;
      setState(() {
        LikeStore.toggle(post);
        _likeDelta[post.id] = (_likeDelta[post.id] ?? 0) - 1;
      });
    } finally {
      if (!mounted) return;
      setState(() => _likeSending.remove(post.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GameWidth Timeline')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _posts.isEmpty) {
      return _ErrorView(message: _error!, onRetry: () => _load(refresh: true));
    }

    if (_posts.isEmpty) {
      return const _EmptyView(text: 'まだ投稿がありません');
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _posts.length + 1,
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!_hasMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('End')),
            );
          }
          return const SizedBox(height: 40);
        }

        final post = _posts[index];
        final vid = _videoId(post);
        final canDetect = _inlineVideoEnabled && vid != null;

        final card = RepaintBoundary(
          child: TimelineCard(
            post: post,
            inlineVideoEnabled: _inlineVideoEnabled,
            isActive: _activePostId == post.id,
            isNew: _isNew(post),
            liked: LikeStore.isLiked(post),
            sendingLike: _likeSending.contains(post.id),
            likeCount: _likeCount(post),
            videoId: vid,
            onOpen: () => _open(post),
            onToggleLike: () => _toggleLike(post),
          ),
        );

        if (!canDetect) return card;

        return VisibilityDetector(
          key: Key('post-${post.id}'),
          onVisibilityChanged: (info) => _onVisible(post, info.visibleFraction),
          child: card,
        );
      },
    );
  }
}

class TimelineCard extends StatelessWidget {
  const TimelineCard({
    super.key,
    required this.post,
    required this.inlineVideoEnabled,
    required this.isActive,
    required this.isNew,
    required this.liked,
    required this.sendingLike,
    required this.likeCount,
    required this.videoId,
    required this.onOpen,
    required this.onToggleLike,
  });

  final Post post;
  final bool inlineVideoEnabled;
  final bool isActive;
  final bool isNew;
  final bool liked;
  final bool sendingLike;
  final int likeCount;
  final String? videoId;

  final VoidCallback onOpen;
  final VoidCallback onToggleLike;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (videoId != null || (post.imageUrl ?? '').isNotEmpty)
            TimelineTopMedia(
              videoId: videoId,
              imageUrl: post.imageUrl,
              inlineVideoEnabled: inlineVideoEnabled,
              isActive: isActive,
              isNew: isNew,
              onOpen: onOpen,
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpen,
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
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'いいね！$likeCount件',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: liked ? Colors.red : Colors.grey,
                  ),
                  onPressed: sendingLike ? null : onToggleLike,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TimelineTopMedia extends StatelessWidget {
  const TimelineTopMedia({
    super.key,
    required this.videoId,
    required this.imageUrl,
    required this.inlineVideoEnabled,
    required this.isActive,
    required this.isNew,
    required this.onOpen,
  });

  final String? videoId;
  final String? imageUrl;
  final bool inlineVideoEnabled;
  final bool isActive;
  final bool isNew;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Stack(
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _media(context)),
          if (isNew) const _NewBadge(),
        ],
      ),
    );
  }

  Widget _media(BuildContext context) {
    if (videoId != null) {
      final thumb = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      if (!inlineVideoEnabled || !isActive) {
        return _Thumb(url: thumb);
      }

      // iOS/Androidのみここに到達
      return IgnorePointer(
        ignoring: true,
        child: GwYoutubePlayer(
          key: ValueKey('yt:$videoId'),
          videoId: videoId!,
          autoPlay: true,
          mute: true,
          useCard: false,
          useAspectRatio: false,
        ),
      );
    }

    final u = (imageUrl ?? '').trim();
    if (u.isEmpty) return Container(color: Colors.black12);

    final lower = u.toLowerCase().split('?').first;
    if (lower.endsWith('.avif')) return Container(color: Colors.black12);

    return _Thumb(url: u);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final w = c.maxWidth;
        final h = w / (16 / 9);
        final cacheW = (w * dpr).round();
        final cacheH = (h * dpr).round();

        return CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          memCacheWidth: cacheW,
          memCacheHeight: cacheH,
          fadeInDuration: Duration.zero,
          placeholder: (_, __) => Container(color: Colors.black12),
          errorWidget: (_, __, ___) => Container(color: Colors.black12),
        );
      },
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
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
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(message)),
        const SizedBox(height: 12),
        Center(
          child: FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(text)),
      ],
    );
  }
}
