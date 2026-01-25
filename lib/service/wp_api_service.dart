// lib/service/wp_api_service.dart

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../model/post.dart';
import '../model/comment.dart';
import '../model/banner.dart';
import 'package:my_first_app/model/character.dart';

class WpApiService {
  final http.Client _client;
  WpApiService({http.Client? client}) : _client = client ?? http.Client();

  static const String wpBaseUrl = 'https://gamewidth.net/wp-json';

  // ==========================================================
  // ✅ 共通：WP REST を安全に組み立て（必要なら _embed=1 を付ける）
  // ==========================================================
  Uri _buildWpUri(String path, {Map<String, String>? query, bool embed = true}) {
    final qp = <String, String>{};
    if (embed) qp['_embed'] = '1';
    if (query != null) qp.addAll(query);

    return Uri.parse('$wpBaseUrl/$path').replace(queryParameters: qp);
  }

  // ==========================================================
  // ✅ A) 標準投稿（wp/v2/posts）: Timeline用（カテゴリで絞る）
  // ==========================================================

  // カテゴリーIDを取得（slug -> id）
  Future<int> getCategoryIdBySlug(String slug) async {
    try {
      final uri = _buildWpUri('wp/v2/categories', embed: false, query: {'per_page': '100'});

      final res = await _client.get(uri);
      if (res.statusCode != 200) return -1;

      final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
      final category = list.firstWhere((c) => (c is Map && c['slug'] == slug), orElse: () => null);

      if (category is Map && category['id'] != null) {
        return category['id'] as int;
      }
      return -1;
    } catch (e) {
      print('Error fetching category by slug: $e');
      return -1;
    }
  }

  // posts を categoryId で取得
  Future<List<Post>> _fetchWpPostsByCategoryId({
    required int categoryId,
    int perPage = 50,
    int page = 1,
  }) async {
    try {
      final uri = _buildWpUri(
        'wp/v2/posts',
        query: {'categories': '$categoryId', 'per_page': '$perPage', 'page': '$page'},
        embed: true,
      );

      final res = await _client.get(uri);
      if (res.statusCode != 200) return [];

      final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error fetching WP posts: $e');
      return [];
    }
  }

  // Genshin Timeline（標準投稿をカテゴリで）
  Future<List<Post>> fetchGenshinTimelineWithCategory({
    required String categorySlug,
    int perPage = 50,
    int page = 1,
  }) async {
    final categoryId = await getCategoryIdBySlug(categorySlug);
    if (categoryId == -1) return [];
    return _fetchWpPostsByCategoryId(categoryId: categoryId, perPage: perPage, page: page);
  }

  // Tekken Timeline（標準投稿をカテゴリで）
  Future<List<Post>> fetchTekkenTimelineWithCategory({
    required String categorySlug,
    int perPage = 50,
    int page = 1,
  }) async {
    final categoryId = await getCategoryIdBySlug(categorySlug);
    if (categoryId == -1) return [];
    return _fetchWpPostsByCategoryId(categoryId: categoryId, perPage: perPage, page: page);
  }

  // ==========================================================
  // ✅ B) カスタム投稿 横断（search / all 用）
  // ここに入れた REST base が「All / Search の対象」になる
  // ==========================================================
  static const List<String> _restBases = [
    'wp/v2/gu', // Genshin Updaeds
    'wp/v2/genshin_updated_jp', // Genshin Updaeds JP　投稿記事　日本語
    //'wp/v2/my-genshin-builds', // My Genshin Builds キャラぅター詳細ページ
    // ✅ もし「All」「検索」に “ビルド記事” も混ぜたいなら追加
    // 'wp/v2/my-genshin-builds',
  ];

  // 特定のREST baseから投稿一覧（_embed=1）
  Future<List<Post>> fetchPostsFromBase(
    String base, {
    required int perPage,
    int page = 1,
    String? searchQuery,
  }) async {
    try {
      final q = <String, String>{'per_page': '$perPage', 'page': '$page'};
      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        q['search'] = searchQuery.trim();
      }

      final uri = _buildWpUri(base, query: q, embed: true);
      final res = await _client.get(uri);

      if (res.statusCode != 200) return [];

      final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error: $e');
      return [];
    }
  }

  // 全投稿（横断）
  Future<List<Post>> fetchAllPosts({int perPage = 50}) async {
    final lists = await Future.wait(_restBases.map((b) => fetchPostsFromBase(b, perPage: perPage)));

    final allPosts = <Post>[];
    for (final l in lists) {
      allPosts.addAll(l);
    }

    // 重複除外
    final seen = <int>{};
    final unique = <Post>[];
    for (final p in allPosts) {
      if (seen.add(p.id)) unique.add(p);
    }

    unique.sort((a, b) => b.date.compareTo(a.date));
    return unique;
  }

  // 横断検索（横断）
  Future<List<Post>> searchAllPosts({
    required String query,
    int perPage = 30,
    int page = 1,
    bool sortByDate = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final lists = await Future.wait(
      _restBases.map(
        (b) => fetchPostsFromBase(b, perPage: perPage, page: page, searchQuery: trimmed),
      ),
    );

    final all = <Post>[];
    for (final l in lists) {
      all.addAll(l);
    }

    // 重複除外
    final seen = <int>{};
    final unique = <Post>[];
    for (final p in all) {
      if (seen.add(p.id)) unique.add(p);
    }

    if (sortByDate) {
      unique.sort((a, b) => b.date.compareTo(a.date));
    }
    return unique;
  }

  // ==========================================================
  // ✅ C) キャラ一覧（gwc/v1/characters）
  // ==========================================================
  Future<List<GenshinCharacter>> fetchGenshinCharacters({int perPage = 50, int page = 1}) async {
    try {
      final uri = _buildWpUri(
        'gwc/v1/characters',
        embed: false,
        query: {'per_page': '$perPage', 'page': '$page'},
      );

      final res = await _client.get(uri);
      if (res.statusCode != 200) return [];

      final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => GenshinCharacter.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error fetching Genshin characters: $e');
      return [];
    }
  }

  // ==========================================================
  // ✅ D) 詳細取得（1件）
  // - ID優先：/wp-json/wp/v2/{rest_base}/{id}?_embed=1
  // - 保険： /wp-json/wp/v2/{rest_base}?slug=xxx&per_page=1&_embed=1
  // ==========================================================
  Future<Post?> fetchSingleById(String base, int id) async {
    if (id <= 0) return null;

    final uri = _buildWpUri('$base/$id', embed: true);
    final res = await _client.get(uri);
    if (res.statusCode != 200) return null;

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;

    return Post.fromJson(decoded);
  }

  Future<Post?> fetchSingleBySlug(String base, String slug) async {
    final s = slug.trim();
    if (s.isEmpty) return null;

    final uri = _buildWpUri(base, query: {'slug': s, 'per_page': '1'}, embed: true);

    final res = await _client.get(uri);
    if (res.statusCode != 200) return null;

    final decoded = jsonDecode(res.body);
    if (decoded is! List || decoded.isEmpty) return null;

    final first = decoded.first;
    if (first is! Map<String, dynamic>) return null;

    return Post.fromJson(first);
  }

  // ==========================================================
  // ✅ Tekken キャラクター（独自API）
  // ==========================================================
  Future<List<TekkenCharacter>> fetchTekkenCharacters({int perPage = 50, int page = 1}) async {
    try {
      final uri = _buildWpUri(
        'gamewidth/v1/tekken7-characters',
        embed: false,
        query: {'per_page': '$perPage', 'page': '$page'},
      );

      final res = await _client.get(uri);
      if (res.statusCode != 200) return [];

      final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
      return list.map((e) => TekkenCharacter.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error fetching Tekken characters: $e');
      return [];
    }
  }

  // ==========================================================
  // ✅ コメント
  // ==========================================================
  Future<List<Comment>> fetchComments(int postId) async {
    final uri = _buildWpUri(
      'wp/v2/comments',
      embed: false,
      query: {'post': '$postId', 'per_page': '100', 'orderby': 'date', 'order': 'asc'},
    );

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Failed to load comments: ${res.statusCode}');
    }

    final List<dynamic> jsonList = jsonDecode(res.body) as List<dynamic>;
    return jsonList.map((e) => Comment.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ==========================================================
  // ✅ いいね
  // ==========================================================
  Future<int> sendLike(int postId) async {
    final deviceId = await _getDeviceId();

    final uri = Uri.parse('$wpBaseUrl/gwc/v1/like');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'post_id': postId, 'device_id': deviceId}),
    );

    // 200以外はエラー
    if (res.statusCode != 200) {
      throw Exception('Like API error: ${res.statusCode} body=${res.body}');
    }

    final Map<String, dynamic> json = jsonDecode(res.body);
    return (json['count'] ?? 0) as int;
  }

  Future<String> _getDeviceId() async {
    const key = 'gwc_device_id';
    final prefs = await SharedPreferences.getInstance();

    final existing = prefs.getString(key);
    if (existing != null && existing.isNotEmpty) return existing;

    // ✅ ここが修正点：
    // 1<<32 が環境によって 0 扱いになり RangeError の原因になることがあるので
    // nextInt の上限は「必ず > 0」になる値にする
    final random = Random();
    final suffix = random.nextInt(0x7fffffff); // 2,147,483,647（確実に>0）

    final newId = 'dev-${DateTime.now().microsecondsSinceEpoch}-$suffix';
    await prefs.setString(key, newId);
    return newId;
  }

  // ==========================================================
  // ✅ Scroll Banner
  // ==========================================================
  Future<ScrollBanner?> fetchScrollBanner() async {
    try {
      final uri = _buildWpUri('scroll-banner/v1/info', embed: false);
      final res = await _client.get(uri);
      if (res.statusCode != 200) return null;

      final raw = jsonDecode(res.body);
      if (raw is! Map<String, dynamic>) return null;

      return ScrollBanner.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  // ==========================
  // ✅ Contact（自作RESTへ送信）
  // ==========================
  Future<void> sendContact({
    required String name,
    required String email,
    String subject = '',
    required String message,
  }) async {
    final deviceId = await _getDeviceId();

    final uri = Uri.parse('$wpBaseUrl/gwc/v1/contact');

    // honeypot: company は常に空で送る（UIには出さない）
    final body = jsonEncode({
      'name': name.trim(),
      'email': email.trim(),
      'subject': subject.trim(),
      'message': message.trim(),
      'device_id': deviceId,
      'company': '', // honeypot
    });

    final res = await _client.post(uri, headers: {'Content-Type': 'application/json'}, body: body);

    if (res.statusCode != 200) {
      // サーバー側の error を拾う
      try {
        final j = jsonDecode(res.body);
        throw Exception('Contact API error: ${res.statusCode} ${j['error'] ?? res.body}');
      } catch (_) {
        throw Exception('Contact API error: ${res.statusCode} ${res.body}');
      }
    }

    // ok=true なら成功（レスポンスボディは使わなくてもOK）
  }
}
