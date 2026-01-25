import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:provider/provider.dart';

import '../service/wp_api_service.dart';
import '../model/post.dart';
import '../app_settings.dart';

import 'genshin_character_list_screen.dart';
import 'tekken_character_list_screen.dart';
import 'post_detail_screen.dart';

/// ============================================================
/// SearchScreen
/// - GwTopHeader が更新する AppSettings.searchQuery を監視して検索を走らせる
/// - メインタブ（All / Genshin / Tekken）
/// - サブタブ（各: Timeline / Character）
///
/// ✅検索の仕様
/// - query が空：今いるタブのタイムラインを表示
/// - query がある：searchAllPosts() で検索結果を表示
///   ※WPの search は基本「部分一致/全文検索寄り」(完全一致保証ではない)
/// ============================================================
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with TickerProviderStateMixin {
  final _api = WpApiService();

  // ✅ AppSettings.searchQuery の「前回値」を保持（同じ文字で検索連打しない）
  String _lastAppQuery = '';

  // ✅ 入力のたびにAPI叩かないためのデバウンス
  final _searchDebouncer = _Debouncer(const Duration(milliseconds: 350));

  bool _loading = false;
  String? _error;

  // ✅ 画面側で保持する現在の検索文字（AppSettingsと同じになる）
  String _query = '';

  // ✅ 画面に出す投稿一覧（タイムライン or 検索結果）
  List<Post> _items = [];

  late final TabController _tabController; // メイン（All/Genshin/Tekken）
  late final TabController _genshinSubTabController; // サブ（Timeline/Character）
  late final TabController _tekkenSubTabController; // サブ（Timeline/Character）

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    _genshinSubTabController = TabController(length: 2, vsync: this);
    _tekkenSubTabController = TabController(length: 2, vsync: this);

    // ✅ スワイプでタブ切り替えでも、検索中じゃない時だけタイムライン再取得
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_query.isEmpty) {
        _loadTimelineData(_currentMainTabType());
      }
    });

    // ✅ 初期表示：All のタイムライン
    _loadTimelineData('All');
  }

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _tabController.dispose();
    _genshinSubTabController.dispose();
    _tekkenSubTabController.dispose();
    super.dispose();
  }

  /// ✅ 今のメインタブから "All/Genshin/Tekken" を返す
  String _currentMainTabType() {
    final idx = _tabController.index;
    return (idx == 0)
        ? 'All'
        : (idx == 1)
        ? 'Genshin'
        : 'Tekken';
  }

  /// ✅ タイムライン取得（検索じゃない通常一覧）
  Future<void> _loadTimelineData(String timelineType) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      List<Post> posts = [];

      if (timelineType == 'All') {
        posts = await _api.fetchAllPosts(perPage: 80);
      } else if (timelineType == 'Genshin') {
        posts = await _api.fetchGenshinTimelineWithCategory(
          categorySlug: 'genshin-impact',
          perPage: 80,
        );
      } else if (timelineType == 'Tekken') {
        posts = await _api.fetchTekkenTimelineWithCategory(categorySlug: 'tekken7', perPage: 80);
      }

      if (!mounted) return;
      setState(() => _items = posts);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to load timeline: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// ✅ 検索（AppSettings.searchQuery が変わったら呼ばれる）
  Future<void> _search(String query) async {
    final trimmed = query.trim();

    setState(() {
      _loading = true;
      _error = null;
      _query = trimmed;
    });

    // ✅ 検索が空なら、今のタブのタイムラインへ戻す
    if (trimmed.isEmpty) {
      await _loadTimelineData(_currentMainTabType());
      return;
    }

    try {
      final results = await _api.searchAllPosts(query: trimmed, perPage: 80);
      if (!mounted) return;
      setState(() => _items = results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Search failed: $e');
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// ✅ Pull-to-refresh
  Future<void> _onRefresh() async {
    if (_query.isEmpty) {
      await _loadTimelineData(_currentMainTabType());
    } else {
      await _search(_query);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ GwTopHeader が更新する AppSettings.searchQuery を監視
    final appQuery = context.select<AppSettings, String>((s) => s.searchQuery);

    // ✅ searchQuery が変わった時だけ検索（同じ値なら何もしない）
    if (appQuery != _lastAppQuery) {
      _lastAppQuery = appQuery;

      // ✅ setState が build 中に起きないように、デバウンスで遅らせて実行
      _searchDebouncer.run(() {
        if (!mounted) return;
        _search(appQuery);
      });
    }

    return Column(
      children: [
        // ✅ メインタブ
        Material(
          child: TabBar(
            controller: _tabController,
            onTap: _onTabChanged,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'Genshin'),
              Tab(text: 'Tekken'),
            ],
          ),
        ),

        // ✅ 中身
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildAllTab(), _buildGenshinTab(), _buildTekkenTab()],
          ),
        ),
      ],
    );
  }

  /// ✅ メインタブ変更（タップ時）
  void _onTabChanged(int index) {
    // ✅ タブ変えたら検索文字を消して、そのタブの一覧へ戻す
    context.read<AppSettings>().setSearchQuery('');
    // context.read<AppSettings>().closeSearch(); // ← AppSettingsにあるならONでもOK

    setState(() {
      _error = null;
      _query = '';
      _items = [];
    });

    if (index == 0) _loadTimelineData('All');
    if (index == 1) _loadTimelineData('Genshin');
    if (index == 2) _loadTimelineData('Tekken');
  }

  // ---------------------------
  // UI: All
  // ---------------------------
  Widget _buildAllTab() {
    return _buildGridOrState();
  }

  // ---------------------------
  // UI: Genshin（Timeline / Character）
  // ---------------------------
  Widget _buildGenshinTab() {
    return Column(
      children: [
        TabBar(
          controller: _genshinSubTabController,
          tabs: const [
            Tab(text: 'Timeline'),
            Tab(text: 'Character'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _genshinSubTabController,
            children: [
              _buildGridOrState(), // Timeline（_items を表示）
              const GenshinCharacterListScreen(), // Character（別画面の検索欄はここで独立が安全）
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------
  // UI: Tekken（Timeline / Character）
  // ---------------------------
  Widget _buildTekkenTab() {
    return Column(
      children: [
        TabBar(
          controller: _tekkenSubTabController,
          tabs: const [
            Tab(text: 'Timeline'),
            Tab(text: 'Character'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tekkenSubTabController,
            children: [_buildGridOrState(), const TekkenCharacterListScreen()],
          ),
        ),
      ],
    );
  }

  /// ✅ 共通：状態（loading/error/empty）か Grid を返す
  /// ✅ RefreshIndicator は “スクロール可能Widget（GridView）” を直接 child にするのが確実
  Widget _buildGridOrState() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) return const Center(child: Text('No results'));

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(8.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8.0,
          mainAxisSpacing: 8.0,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final post = _items[index];
          final yt = _youtubeIdOf(post);

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
              );
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (yt != null)
                  CachedNetworkImage(
                    imageUrl: 'https://img.youtube.com/vi/$yt/hqdefault.jpg',
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.black12),
                  )
                else
                  _buildImageCell(post),
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
                      yt != null ? Icons.play_arrow : Icons.image_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// ✅ YouTube ID を取得（URLでもIDでも対応）
  String? _youtubeIdOf(Post p) {
    final raw = (p.youtubeId ?? p.pageVideoId)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(raw) ?? raw;
  }

  /// ✅ 画像セル（サムネが無い場合のフォールバック）
  Widget _buildImageCell(Post post) {
    final img = post.imageUrl;
    if (img == null || img.isEmpty) {
      return Container(
        color: Colors.black12,
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      );
    }

    return CachedNetworkImage(
      imageUrl: img,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: Colors.black12),
      errorWidget: (_, __, ___) =>
          Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined)),
    );
  }
}

/// ============================================================
/// Debouncer
/// - 文字入力のたびに検索APIを叩かないための遅延実行
/// ============================================================
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
