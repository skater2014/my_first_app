// lib/screens/search_screen.dart
//
// Explore / Search Screen
// - Explore（検索が空）: 動画だけを3カラムで流して“発見”を作る
// - Search（検索あり） : 画像 + 動画 を混在表示（必要ならチップで Video のみ）
//
// 重要な設計:
// 1) YouTube Player を大量生成すると重い → 画面内で「見えてる上位2つ」だけ再生
// 2) Search の “All / Video” 切替は、サーバ検索結果に対してクライアント側でフィルタ
// 3) 古い検索が後から返ってきて上書きしないように token でガード
//
// UI:
// - 上: SearchField
// - その下: FilterChip（All / Video） ※検索中のみ表示
// - 下: 3カラム Grid
//
// アイコン規則（日本語なし）:
// - video: play_arrow（停止中） / volume_off（自動再生中=ミュート）
// - image/article: image_outlined

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../service/wp_api_service.dart';
import '../model/post.dart';
import 'post_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // ---- API
  final _api = WpApiService();

  // ---- Search UI
  final _textController = TextEditingController();
  final _searchDebouncer = _Debouncer(const Duration(milliseconds: 350));

  // visibleFraction は細かく動くので、active再計算も少し待つ
  final _activeDebouncer = _Debouncer(const Duration(milliseconds: 250));

  bool _loading = false;
  String? _error;
  String _query = '';

  // ✅ Search中だけ有効：Video のみに絞るか
  //    - All: 画像 + 動画
  //    - Video: 動画だけ
  bool _videoOnlyInSearch = false;

  // ✅ 表示する投稿（Allなら画像も動画も混在）
  List<Post> _items = [];

  // ---- “見えてる割合” 管理
  // postId -> visibleFraction
  final Map<int, double> _visible = {};

  // ---- 自動再生するpostId（最大2）
  Set<int> _activeIds = <int>{};

  // ---- activeだけcontrollerを持つ（最大2）
  final Map<int, YoutubePlayerController> _controllers = {};

  // ✅ 古い検索結果が後から帰ってきて上書きしないためのトークン
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _loadExplore();
  }

  @override
  void dispose() {
    _textController.dispose();
    _searchDebouncer.dispose();
    _activeDebouncer.dispose();

    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();

    super.dispose();
  }

  // ----------------------------------------------------------------------
  // Explore（検索が空のとき）
  // - “発見”用途なので動画だけにして軽くする
  // ----------------------------------------------------------------------
  Future<void> _loadExplore() async {
    final token = ++_searchToken;

    setState(() {
      _loading = true;
      _error = null;
      _query = '';
      // Exploreではチップは出さないので、状態は残してもOKだが
      // UXを安定させたいならここで false に戻してもよい
      // _videoOnlyInSearch = false;
    });

    try {
      final posts = await _api.fetchAllPosts(perPage: 80);
      if (!mounted || token != _searchToken) return;

      // ✅ Exploreは動画だけ
      final videos = posts.where((p) => _youtubeIdOf(p) != null).toList();

      setState(() => _items = videos);
      _resetActiveState();
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() => _error = 'Failed to load Explore: $e');
    } finally {
      if (!mounted || token != _searchToken) return;
      setState(() => _loading = false);
    }
  }

  // ----------------------------------------------------------------------
  // Search（検索キーワードあり）
  // - まずサーバ検索結果を全部もらう（画像+動画混在）
  // - チップが Video のときだけ “動画のみ” に絞る（クライアント側フィルタ）
  // ----------------------------------------------------------------------
  Future<void> _search(String q) async {
    final trimmed = q.trim();
    final token = ++_searchToken;

    if (trimmed.isEmpty) {
      await _loadExplore();
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _query = trimmed;
    });

    try {
      // ✅ ここが「検索クエリ」：
      // WpApiService.searchAllPosts() が
      // /posts?search=..., /gu?search=..., /gu-jp?search=...
      // を叩いて結果をまとめて返す。
      final results = await _api.searchAllPosts(query: trimmed, perPage: 80);
      if (!mounted || token != _searchToken) return;

      // ✅ “tekken は出ない / genshin は出る” みたいな差は、
      // このフィルタが ON のときに起きる。
      // Video のときは youtubeId が無い投稿（画像記事など）は落ちる。
      final items = _videoOnlyInSearch
          ? results.where((p) => _youtubeIdOf(p) != null).toList()
          : results;

      setState(() => _items = items);
      _resetActiveState();
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (!mounted || token != _searchToken) return;
      setState(() => _loading = false);
    }
  }

  void _onChange(String text) {
    setState(() {}); // clearボタンなど更新
    _searchDebouncer.run(() => _search(text));
  }

  Future<void> _onRefresh() async {
    if (_query.isEmpty) {
      await _loadExplore();
    } else {
      await _search(_query);
    }
  }

  // ----------------------------------------------------------------------
  // YouTube / Image helpers
  // ----------------------------------------------------------------------
  String? _youtubeIdOf(Post p) {
    // youtubeId / pageVideoId が URL の場合もあるので convertUrlToId で吸収
    final raw = (p.youtubeId ?? p.pageVideoId)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(raw) ?? raw;
  }

  String _thumbUrl(String youtubeId) =>
      'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';

  String? _safeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.toLowerCase().split('?').first;
    // ✅ AVIF が表示できない端末があるので回避
    if (u.endsWith('.avif')) return null;
    return url;
  }

  // ----------------------------------------------------------------------
  // Active autoplay (max 2)
  // - “見えてる上位2つ” の動画だけプレイヤー化してミュート自動再生
  // ----------------------------------------------------------------------
  void _resetActiveState() {
    _visible.clear();
    _setActiveIds(<int>{});
  }

  YoutubePlayerController _createController(String youtubeId) {
    return YoutubePlayerController(
      initialVideoId: youtubeId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: true, // ✅ 基本はここでミュート
        hideControls: true,
        controlsVisibleAtStart: false,
        disableDragSeek: true,
        enableCaption: false,
      ),
    );
  }

  void _setActiveIds(Set<int> next) {
    if (setEquals(next, _activeIds)) return;

    final prev = _activeIds;
    _activeIds = next;

    // 1) 外れたものは停止して破棄（controller増殖防止）
    for (final id in prev.difference(next)) {
      final c = _controllers.remove(id);
      c?.pause();
      c?.dispose();
    }

    // 2) 入ったものは生成（最大2）
    for (final id in next.difference(prev)) {
      final idx = _items.indexWhere((p) => p.id == id);
      if (idx == -1) continue;

      final yt = _youtubeIdOf(_items[idx]);
      if (yt == null) continue;

      _controllers[id] = _createController(yt);
    }

    // 3) 念押しで mute + volume=0（端末によって mute が甘い事故対策）
    for (final id in next) {
      final c = _controllers[id];
      c?.mute();
      c?.setVolume(0);
      c?.play();
    }

    setState(() {});
  }

  void _recomputeActive() {
    const minVisible = 0.60; // 60%以上見えているセルだけ候補
    const maxActive = 2;

    if (_items.isEmpty) {
      _setActiveIds(<int>{});
      return;
    }

    final candidates = <int>[];

    for (final entry in _visible.entries) {
      final id = entry.key;
      final fraction = entry.value;

      if (fraction < minVisible) continue;

      final idx = _items.indexWhere((p) => p.id == id);
      if (idx == -1) continue;

      // ✅ “動画だけ” が自動再生対象（画像は対象外）
      if (_youtubeIdOf(_items[idx]) == null) continue;

      candidates.add(id);
    }

    // 見えてる割合が高い順にして上位2つ
    candidates.sort((a, b) => (_visible[b] ?? 0).compareTo(_visible[a] ?? 0));
    _setActiveIds(candidates.take(maxActive).toSet());
  }

  void _onVisibility(int postId, double fraction) {
    if (fraction <= 0) {
      _visible.remove(postId);
    } else {
      _visible[postId] = fraction;
    }
    _activeDebouncer.run(_recomputeActive);
  }

  // ----------------------------------------------------------------------
  // UI
  // ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final title = _query.isEmpty ? 'Explore' : 'Search';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _query.isEmpty ? title : '$title: $_query',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ---- Search Field
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                controller: _textController,
                onChanged: _onChange,
                onSubmitted: (v) => _search(v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search (empty = Explore)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  suffixIcon: _textController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _textController.clear();
                            setState(() {});
                            _loadExplore();
                          },
                        ),
                ),
              ),
            ),

            // ---- FilterChip (Search中のみ表示)
            if (_query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    _modeChip(
                      selected: !_videoOnlyInSearch,
                      icon: Icons.grid_view_rounded,
                      label: 'All',
                      onTap: () {
                        if (!_videoOnlyInSearch) return;
                        setState(() => _videoOnlyInSearch = false);
                        _search(_query); // 切替したら再検索（同じクエリ）
                      },
                    ),
                    const SizedBox(width: 10),
                    _modeChip(
                      selected: _videoOnlyInSearch,
                      icon: Icons.movie_filter_rounded,
                      label: 'Video',
                      onTap: () {
                        if (_videoOnlyInSearch) return;
                        setState(() => _videoOnlyInSearch = true);
                        _search(_query);
                      },
                    ),
                  ],
                ),
              ),

            // ---- Body
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FilterChip の見た目（あなたが見せたイメージに近い “わかりやすい2択”）
  Widget _modeChip({
    required bool selected,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      labelPadding: const EdgeInsets.symmetric(horizontal: 10),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(child: Text(_error!)),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(
              onPressed: _onRefresh,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('No results')),
        ],
      );
    }

    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            childAspectRatio: 1.0,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final post = _items[index];

            // yt == null なら「画像記事（or 動画ID無し）」
            final yt = _youtubeIdOf(post);

            // active は “動画” かつ “activeIdsに入ってる” ときだけ
            final active = yt != null && _activeIds.contains(post.id);
            final controller = _controllers[post.id];

            return VisibilityDetector(
              key: Key('cell:${post.id}'),
              onVisibilityChanged: (info) =>
                  _onVisibility(post.id, info.visibleFraction),
              child: InkWell(
                onTap: () {
                  // ✅ 詳細に行く前に止める（音漏れ/暴走防止）
                  _setActiveIds(<int>{});

                  // 詳細画面で「普通に再生/閲覧」
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PostDetailScreen(post: post),
                    ),
                  );
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (yt != null) ...[
                      // -----------------------
                      // VIDEO CELL
                      // -----------------------
                      if (active && controller != null)
                        IgnorePointer(
                          ignoring: true, // グリッド上では操作不可（軽量）
                          child: YoutubePlayer(
                            controller: controller,
                            aspectRatio: 1.0,
                          ),
                        )
                      else
                        CachedNetworkImage(
                          imageUrl: _thumbUrl(yt),
                          fit: BoxFit.cover,
                          placeholder: (_, __) =>
                              Container(color: Colors.black12),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                    ] else ...[
                      // -----------------------
                      // IMAGE/ARTICLE CELL
                      // -----------------------
                      _buildImageCell(post),
                    ],

                    // 右上マーク（言語なしで判別できるやつ）
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Icon(
                          yt != null
                              ? (active ? Icons.volume_off : Icons.play_arrow)
                              : Icons.image_outlined,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // 右上ローディング（結果がある状態で更新中）
        if (_loading && _items.isNotEmpty)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildImageCell(Post post) {
    final img = _safeImageUrl(post.imageUrl);

    if (img == null) {
      return Container(
        color: Colors.black12,
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      );
    }

    return CachedNetworkImage(
      imageUrl: img,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: Colors.black12),
      errorWidget: (_, __, ___) => Container(
        color: Colors.black12,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

// 入力を少し待ってから実行する Debouncer
class _Debouncer {
  final Duration delay;
  Timer? _timer;

  _Debouncer(this.delay);

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
