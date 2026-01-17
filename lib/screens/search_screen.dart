import 'package:flutter/material.dart';

// lib/screens/search_screen.dart
//
// ✅ Search = 検索ハブ（司令塔UI）
//
// 役割：
// 1) SearchField（検索文字）管理
// 2) モード切替（Posts / Genshin / Tekken）管理
// 3) 言語切替（EN / JP）管理
// 4) モードに応じて叩くAPIを決める
// 5) Posts：YouTube 自動再生・停止（音漏れ防止）
//    - ✅ iOS/Androidのみ：グリッド内自動再生（mute）
//    - ✅ Web / Desktop は重い＆不安定なので：サムネのみ（自動再生しない）
//    - ✅ youtube_player_flutter を画面で直接使わない（GwYoutubePlayerに統一）
// 6) Genshin：ページング + 重複排除
//
// ✅ 注意：Rowは幅オーバーしやすい → Wrapで改行させる（Right overflow対策）
// ✅ 注意：Genshinはサーバが同キャラ別記事を複数返すことがある → charName優先で1つにまとめる

import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode, setEquals, defaultTargetPlatform, TargetPlatform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';

// ✅ YouTube（共通Widget）
import '../widgets/gw_youtube_player.dart';

// ✅ YouTube util（ID抽出 / thumb）
import '../utils/gw_youtube.dart';

import '../constants.dart'; // ✅ AppLang / wpBaseUrl
import '../service/wp_api_service.dart'; // ✅ WpApiService と GwcApi
import '../model/post.dart';
import '../model/gwc_character.dart';

import 'post_detail_screen.dart';
import 'character_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _SearchMode { posts, genshin, tekken }

class _SearchScreenState extends State<SearchScreen> {
  // ==========================================================
  // ✅ API（通信）
  // ==========================================================
  final _postApi = WpApiService();
  late final GwcApi _gwcApi;

  // ==========================================================
  // ✅ Search UI（共通）
  // ==========================================================
  final _textController = TextEditingController();
  final _searchDebouncer = _Debouncer(const Duration(milliseconds: 350));
  final _activeDebouncer = _Debouncer(const Duration(milliseconds: 250));

  bool _loading = false;
  String? _error;
  String _query = '';

  _SearchMode _mode = _SearchMode.posts;

  // ==========================================================
  // ✅ 言語切替（Posts / Genshin を別々に持つ）
  // ==========================================================
  AppLang _postsLang = AppLang.en;
  AppLang _genshinLang = AppLang.en;

  AppLang _langForCurrentMode() {
    if (_mode == _SearchMode.posts) return _postsLang;
    if (_mode == _SearchMode.genshin) return _genshinLang;
    return AppLang.en;
  }

  void _setLangForCurrentMode(AppLang next) {
    if (next == _langForCurrentMode()) return;

    // ✅ 言語切替の瞬間は動画停止（音漏れ防止）
    _stopAllVideosNoSetState();

    setState(() {
      if (_mode == _SearchMode.posts) _postsLang = next;
      if (_mode == _SearchMode.genshin) _genshinLang = next;
    });

    // ✅ 同じ検索文字で再検索
    _searchByMode(_textController.text);
  }

  // ==========================================================
  // ✅ Posts
  // ==========================================================
  bool _videoOnlyInSearch = false;
  List<Post> _items = [];

  bool get _enableGridAutoplay {
    if (kIsWeb) return false; // ✅ Webはサムネのみ（軽量）
    final tp = defaultTargetPlatform;
    return tp == TargetPlatform.android || tp == TargetPlatform.iOS;
  }

  final Map<int, double> _visible = {}; // postId -> visibleFraction
  Set<int> _activeIds = <int>{};

  // ==========================================================
  // ✅ Genshin（ページング）
  // ==========================================================
  final List<GwcCharacter> _chars = [];
  final Set<int> _charIds = <int>{};

  // ✅ 重複排除キー（同キャラ別記事対策：charName最優先）
  final Set<String> _charKeys = <String>{};

  final ScrollController _charScroll = ScrollController();

  int _charPage = 1;
  final int _charPerPage = 20;
  bool _charHasMore = true;
  bool _charLoadingMore = false;

  // ✅ 古い検索結果で上書きしないためのトークン
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();

    _gwcApi = GwcApi();

    // ✅ 初期：Posts Explore（検索空＝動画だけ）
    _loadExplore();

    // ✅ Genshinの無限スクロール
    _charScroll.addListener(() {
      if (_mode != _SearchMode.genshin) return;
      if (_loading) return;
      if (_charLoadingMore) return;
      if (!_charHasMore) return;
      if (!_charScroll.hasClients) return;

      final pos = _charScroll.position;

      // ✅ リストが短くてスクロールできない時（max=0）は絶対に loadMore しない
      if (pos.maxScrollExtent <= 0) return;

      const threshold = 300.0;
      final reachedBottom = pos.pixels >= (pos.maxScrollExtent - threshold);
      if (!reachedBottom) return;

      _loadCharactersMore();
    });
  }

  @override
  void dispose() {
    _stopAllVideosNoSetState();

    _textController.dispose();
    _searchDebouncer.dispose();
    _activeDebouncer.dispose();
    _charScroll.dispose();

    super.dispose();
  }

  // ==========================================================
  // ✅ 動画停止（disposeでも安全）
  // - controller を画面で持たないので、activeIds を空にするだけで止まる
  // ==========================================================
  void _stopAllVideosNoSetState() {
    _visible.clear();
    _activeIds = <int>{};
  }

  // ==========================================================
  // ✅ モード切替
  // ==========================================================
  void _setMode(_SearchMode next) {
    if (next == _mode) return;

    _stopAllVideosNoSetState();

    setState(() {
      _mode = next;
      if (_mode != _SearchMode.posts) _videoOnlyInSearch = false;
    });

    _searchByMode(_textController.text);
  }

  // ==========================================================
  // ✅ 入力変化
  // ==========================================================
  void _onChange(String text) {
    setState(() {});
    _searchDebouncer.run(() => _searchByMode(text));
  }

  Future<void> _searchByMode(String q) async {
    if (_mode == _SearchMode.posts) return _searchPosts(q);
    if (_mode == _SearchMode.genshin) return _searchGenshin(q);
    return _searchTekken(q);
  }

  Future<void> _onRefresh() async => _searchByMode(_query);

  // ==========================================================
  // ✅ Posts：Explore（検索空）＝動画だけ
  // ==========================================================
  Future<void> _loadExplore() async {
    final token = ++_searchToken;

    setState(() {
      _loading = true;
      _error = null;
      _query = '';
    });

    try {
      final posts = await _postApi.fetchAllPosts(perPage: 40, lang: _postsLang);
      if (!mounted || token != _searchToken) return;

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

  // ==========================================================
  // ✅ Posts：Search（検索あり）
  // ==========================================================
  Future<void> _searchPosts(String q) async {
    final trimmed = q.trim();
    final token = ++_searchToken;

    if (trimmed.isEmpty) return _loadExplore();

    setState(() {
      _loading = true;
      _error = null;
      _query = trimmed;
    });

    try {
      final results = await _postApi.searchAllPosts(
        query: trimmed,
        perPage: 40,
        lang: _postsLang,
      );

      if (!mounted || token != _searchToken) return;

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

  // ==========================================================
  // ✅ Genshin：重複排除キー
  // ==========================================================
  String _charKeyOf(GwcCharacter c) {
    final primary = c.charName.trim();
    if (primary.isNotEmpty) return primary.toLowerCase();

    final key =
        (c.permalink.isNotEmpty
                ? c.permalink
                : (c.slug.isNotEmpty ? c.slug : c.title))
            .trim()
            .toLowerCase();

    return key;
  }

  int _addCharactersUnique(List<GwcCharacter> list) {
    var added = 0;

    for (final ch in list) {
      final key = _charKeyOf(ch);

      final okByKey = key.isEmpty ? true : _charKeys.add(key);
      final okById = _charIds.add(ch.id);

      if (!okByKey || !okById) continue;

      _chars.add(ch);
      added++;
    }

    return added;
  }

  // ==========================================================
  // ✅ Genshin：検索（空なら一覧）
  // ==========================================================
  Future<void> _searchGenshin(String q) async {
    final trimmed = q.trim();
    final token = ++_searchToken;

    _stopAllVideosNoSetState();

    setState(() {
      _loading = true;
      _error = null;
      _query = trimmed;
    });

    try {
      _chars.clear();
      _charIds.clear();
      _charKeys.clear();
      _charPage = 1;
      _charHasMore = true;
      _charLoadingMore = false;

      final list = await _gwcApi.fetchCharacters(
        page: _charPage,
        perPage: _charPerPage,
        full: false,
        includeHtml: false,
        search: trimmed.isEmpty ? null : trimmed,
        lang: _genshinLang,
      );

      if (!mounted || token != _searchToken) return;

      final added = _addCharactersUnique(list);

      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[Genshin] page=1 raw=${list.length} added=$added lang=${_genshinLang.code}',
        );
      }

      _charHasMore = !(list.isEmpty || added == 0);
      _charPage = 2;

      if (_charScroll.hasClients) _charScroll.jumpTo(0);

      setState(() {});
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() => _error = 'Genshin characters failed: $e');
    } finally {
      if (!mounted || token != _searchToken) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadCharactersMore() async {
    if (_loading) return;
    if (_charLoadingMore) return;
    if (!_charHasMore) return;

    final token = _searchToken;

    setState(() {
      _loading = true;
      _charLoadingMore = true;
      _error = null;
    });

    try {
      final list = await _gwcApi.fetchCharacters(
        page: _charPage,
        perPage: _charPerPage,
        full: false,
        includeHtml: false,
        search: _query.trim().isEmpty ? null : _query.trim(),
        lang: _genshinLang,
      );

      if (!mounted || token != _searchToken) return;

      final added = _addCharactersUnique(list);

      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[Genshin] page=$_charPage raw=${list.length} added=$added lang=${_genshinLang.code}',
        );
      }

      if (list.isEmpty || added == 0) {
        _charHasMore = false;
      } else {
        _charPage += 1;
      }

      setState(() {});
    } catch (e) {
      if (!mounted || token != _searchToken) return;
      setState(() => _error = 'Load more failed: $e');
    } finally {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _charLoadingMore = false;
      });
    }
  }

  // ==========================================================
  // ✅ Tekken（将来）
  // ==========================================================
  Future<void> _searchTekken(String q) async {
    _stopAllVideosNoSetState();
    setState(() {
      _query = q.trim();
      _error = null;
      _loading = false;
    });
  }

  // ==========================================================
  // ✅ element 表示（URL→Geoなど）
  // ==========================================================
  String _elementLabelFromAny(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';

    final m = RegExp(
      r'Element_([A-Za-z]+)\.(png|webp|jpg)$',
      caseSensitive: false,
    ).firstMatch(s.split('?').first);
    if (m != null) {
      final name = (m.group(1) ?? '').trim();
      if (name.isEmpty) return '';
      return name[0].toUpperCase() + name.substring(1).toLowerCase();
    }

    if (!s.startsWith('http')) {
      return s[0].toUpperCase() + s.substring(1).toLowerCase();
    }

    return '';
  }

  String? _elementIconUrl(String raw) {
    final s = raw.trim();
    if (!s.startsWith('http')) return null;

    final clean = s.toLowerCase().split('?').first;
    if (clean.endsWith('.png') ||
        clean.endsWith('.webp') ||
        clean.endsWith('.jpg')) {
      return s;
    }
    return null;
  }

  // ==========================================================
  // ✅ YouTube / Image helpers（Posts）
  // ==========================================================
  String? _youtubeIdOf(Post p) {
    final raw = (p.youtubeId ?? p.pageVideoId)?.trim();
    if (raw == null || raw.isEmpty) return null;

    // ✅ できるだけ “11文字ID” を返す（URLも対応）
    final id = gwExtractYoutubeId(raw);
    if (id != null && id.isNotEmpty) return id;

    // fallback：文字列中から11文字を拾う（変なURLでも拾える）
    final m = RegExp(r'([A-Za-z0-9_-]{11})').firstMatch(raw);
    return m?.group(1);
  }

  String _thumbUrl(String youtubeId) =>
      'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg';

  String? _safeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.avif')) return null;
    return url;
  }

  // ==========================================================
  // ✅ Active autoplay（Posts）
  // - 画面で controller を持たない
  // - activeIds に入っているセルだけ GwYoutubePlayer(autoPlay/mute) を出す
  // ==========================================================
  void _resetActiveState() {
    _visible.clear();
    _setActiveIds(<int>{});
  }

  void _setActiveIds(Set<int> next) {
    // ✅ autoplay無効環境では常に空
    if (!_enableGridAutoplay) {
      if (_activeIds.isNotEmpty) {
        _activeIds = <int>{};
        if (mounted) setState(() {});
      }
      return;
    }

    if (setEquals(next, _activeIds)) return;
    _activeIds = next;

    if (mounted) setState(() {});
  }

  void _recomputeActive() {
    if (_mode != _SearchMode.posts) return;
    if (!_enableGridAutoplay) return;

    final minVisible = kIsWeb ? 0.75 : 0.60;

    // ★ここ
    final maxActive = kIsWeb ? 1 : 3;

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
      if (_youtubeIdOf(_items[idx]) == null) continue;

      candidates.add(id);
    }

    candidates.sort((a, b) => (_visible[b] ?? 0).compareTo(_visible[a] ?? 0));
    _setActiveIds(candidates.take(maxActive).toSet());
  }

  void _onVisibility(int postId, double fraction) {
    if (_mode != _SearchMode.posts) return;
    if (!_enableGridAutoplay) return;

    if (fraction <= 0) {
      _visible.remove(postId);
    } else {
      _visible[postId] = fraction;
    }
    _activeDebouncer.run(_recomputeActive);
  }

  // ==========================================================
  // ✅ UI
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    final title = _query.isEmpty ? 'Explore' : 'Search';
    final currentLang = _langForCurrentMode();

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
            // ===== Search box =====
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                controller: _textController,
                onChanged: _onChange,
                onSubmitted: (v) => _searchByMode(v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search (mode: Posts / Genshin / Tekken)',
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
                            _searchByMode('');
                          },
                        ),
                ),
              ),
            ),

            // ✅ Mode chips（Rowだと溢れる → Wrap）
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _modeChip(
                    selected: _mode == _SearchMode.posts,
                    icon: Icons.article_outlined,
                    label: 'Posts',
                    onTap: () => _setMode(_SearchMode.posts),
                  ),
                  _modeChip(
                    selected: _mode == _SearchMode.genshin,
                    icon: Icons.people_alt_outlined,
                    label: 'Genshin',
                    onTap: () => _setMode(_SearchMode.genshin),
                  ),
                  _modeChip(
                    selected: _mode == _SearchMode.tekken,
                    icon: Icons.sports_mma_outlined,
                    label: 'Tekken',
                    onTap: () => _setMode(_SearchMode.tekken),
                  ),
                ],
              ),
            ),

            // ✅ Language chips（Rowだと溢れる → Wrap）
            if (_mode != _SearchMode.tekken)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _modeChip(
                      selected: currentLang == AppLang.en,
                      icon: Icons.language,
                      label: 'EN',
                      onTap: () => _setLangForCurrentMode(AppLang.en),
                    ),
                    _modeChip(
                      selected: currentLang == AppLang.ja,
                      icon: Icons.translate,
                      label: 'JP',
                      onTap: () => _setLangForCurrentMode(AppLang.ja),
                    ),
                  ],
                ),
              ),

            // Postsだけ：All/Video（検索あり時）
            if (_mode == _SearchMode.posts && _query.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _modeChip(
                      selected: !_videoOnlyInSearch,
                      icon: Icons.grid_view_rounded,
                      label: 'All',
                      onTap: () {
                        if (!_videoOnlyInSearch) return;
                        _stopAllVideosNoSetState();
                        setState(() => _videoOnlyInSearch = false);
                        _searchPosts(_query);
                      },
                    ),
                    _modeChip(
                      selected: _videoOnlyInSearch,
                      icon: Icons.movie_filter_rounded,
                      label: 'Video',
                      onTap: () {
                        if (_videoOnlyInSearch) return;
                        _stopAllVideosNoSetState();
                        setState(() => _videoOnlyInSearch = true);
                        _searchPosts(_query);
                      },
                    ),
                  ],
                ),
              ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: _buildBodyByMode(),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildBodyByMode() {
    if (_mode == _SearchMode.posts) return _buildPostsBody();
    if (_mode == _SearchMode.genshin) return _buildGenshinBody();
    return _buildTekkenBody();
  }

  // ==========================================================
  // ✅ Posts Body（グリッド）
  // ==========================================================
  Widget _buildPostsBody() {
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
            final yt = _youtubeIdOf(post);

            final active =
                _enableGridAutoplay &&
                yt != null &&
                _activeIds.contains(post.id);

            final cell = InkWell(
              onTap: () {
                _stopAllVideosNoSetState();
                if (mounted) setState(() {});

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
                    // ✅ iOS/Androidのみ：自動再生（mute）
                    if (active)
                      IgnorePointer(
                        ignoring: true,
                        child: GwYoutubePlayer(
                          key: ValueKey('yt:${post.id}'),
                          videoId: yt,
                          autoPlay: true,
                          mute: true,
                          useCard: false,
                          useAspectRatio: false, // グリッドの正方形に合わせる
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
                    _buildImageCell(post),
                  ],
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
                            ? (_enableGridAutoplay && active
                                  ? Icons.volume_off
                                  : Icons.play_arrow)
                            : Icons.image_outlined,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            );

            if (yt == null || !_enableGridAutoplay) return cell;

            return VisibilityDetector(
              key: Key('cell:${post.id}'),
              onVisibilityChanged: (info) =>
                  _onVisibility(post.id, info.visibleFraction),
              child: cell,
            );
          },
        ),

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

  // ==========================================================
  // ✅ Genshin Body（ListView）
  // ==========================================================
  Widget _buildGenshinBody() {
    if (_loading && _chars.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _chars.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(child: Text(_error!)),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(
              onPressed: () => _searchGenshin(_query),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    if (_chars.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: Text('No characters')),
        ],
      );
    }

    return ListView.builder(
      controller: _charScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _chars.length + 1,
      itemBuilder: (context, index) {
        if (index == _chars.length) {
          if (_loading && _charLoadingMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!_charHasMore) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: Text('End')),
            );
          }
          return const SizedBox.shrink();
        }

        final c = _chars[index];
        final elementLabel = _elementLabelFromAny(c.element);
        final elementIcon = _elementIconUrl(c.element);

        return ListTile(
          leading: _portrait(c.portrait),
          title: Text(c.charName.isNotEmpty ? c.charName : c.title),
          subtitle: Wrap(
            spacing: 8,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (elementIcon != null)
                CachedNetworkImage(
                  imageUrl: elementIcon,
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      const SizedBox(width: 16, height: 16),
                ),
              if (elementLabel.isNotEmpty) Text(elementLabel),
              if (c.weaponType.isNotEmpty) Text(c.weaponType),
              if (c.rarity.isNotEmpty) Text('★${c.rarity}'),
              if (c.role.isNotEmpty) Text(c.role),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CharacterDetailScreen(
                  characterId: c.id,
                  lang: _genshinLang,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _portrait(String url) {
    const size = 44.0;

    if (url.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.person),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: Colors.black12),
        errorWidget: (_, __, ___) => Container(
          color: Colors.black12,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }

  // ==========================================================
  // ✅ Tekken Body（将来）
  // ==========================================================
  Widget _buildTekkenBody() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Center(child: Text('Tekken mode: coming soon')),
        SizedBox(height: 12),
        Center(child: Text('ここに Tekken キャラAPI を繋げる')),
      ],
    );
  }
}

// ==========================================================
// ✅ Debouncer（このファイルで1回だけ定義）
// ==========================================================
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
