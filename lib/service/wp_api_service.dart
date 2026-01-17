// lib/service/wp_api_service.dart
//
// =============================================================
// ✅ 役割：WordPress / 自作REST API を叩く “通信の司令塔”
// =============================================================
//
// ✅ 方針（超重要）
// - screens/ にはHTTP処理を書かない
// - 画面は「このファイルの関数を呼ぶだけ」
// - URL/例外/パラメータはここに集約して、修正点を1箇所に閉じ込める
//
// ✅ このファイルが担当するAPI
// 1) WordPress標準 REST API（/wp-json/wp/v2/...）
//    - posts / comments / categories など
//
// 2) あなたの自作 REST API（/wp-json/gwc/v1/...）
//    - characters / like など
//
// 3) （任意）Reset API（/wp-json/gw/v1/reset など）
// =============================================================

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart'; // siteBaseUrl / wpV2BaseUrl / gwcV1BaseUrl / scrollBannerApiUrl / AppLang
import '../model/banner.dart';
import '../model/comment.dart';
import '../model/gwc_character.dart';
import '../model/post.dart';

/// =============================================================
/// ✅ 共通：HTTP例外（本文を短縮して保持）
/// =============================================================
class ApiException implements Exception {
  final int statusCode;
  final String url;
  final String bodySnippet;

  ApiException({
    required this.statusCode,
    required this.url,
    required this.bodySnippet,
  });

  @override
  String toString() => 'HTTP $statusCode: $url :: $bodySnippet';
}

/// =============================================================
/// ✅ 共通ユーティリティ（ログ・本文短縮）
/// =============================================================
String _snip(String s, [int max = 400]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}...';
}

void _log(bool enabled, String msg) {
  if (!enabled) return;
  // ignore: avoid_print
  print(msg);
}

/// =============================================================
/// ✅ WordPress標準 API（wp/v2）を叩くクラス
/// =============================================================
class WpApiService {
  // ==========================================================
  // ✅ 速度/安定性のための方針
  // ==========================================================
  static final http.Client _sharedClient = http.Client();

  static final Map<String, _CacheEntry> _memCache = <String, _CacheEntry>{};
  static const Duration _defaultCacheTtl = Duration(seconds: 20);

  final http.Client _client;
  final bool logEnabled;

  WpApiService({http.Client? client, this.logEnabled = false})
    : _client = client ?? _sharedClient;

  // ==========================================================
  // ✅ 横断検索に使うREST base（言語別）
  // ==========================================================
  static const List<String> _restBasesEn = <String>[
    'posts',
    'gu',
    'genshin_updated',
    'artifacts',
  ];

  static const List<String> _restBasesJa = <String>[
    'posts',
    'gu-jp',
    'genshin_updated_jp',
    'artifacts',
  ];

  List<String> _basesByLang(AppLang lang) =>
      (lang == AppLang.ja) ? _restBasesJa : _restBasesEn;

  // ==========================================================
  // ✅ 共通：GETしてJSONを返す（Map or List）
  // ==========================================================
  Future<dynamic> _getJson(
    Uri uri, {
    Map<String, String>? headers,
    Duration? cacheTtl,
  }) async {
    final h = headers ?? const {'accept': 'application/json'};
    final ttl = cacheTtl ?? _defaultCacheTtl;

    final key = uri.toString();
    final now = DateTime.now();

    final hit = _memCache[key];
    if (hit != null && hit.expiresAt.isAfter(now)) {
      _log(logEnabled, '🧠 CACHE HIT $uri');
      return hit.data;
    }

    _log(logEnabled, '➡️ GET $uri');
    final res = await _client.get(uri, headers: h);

    if (res.statusCode != 200) {
      throw ApiException(
        statusCode: res.statusCode,
        url: uri.toString(),
        bodySnippet: _snip(res.body),
      );
    }

    final decoded = jsonDecode(res.body);

    if (ttl > Duration.zero) {
      _memCache[key] = _CacheEntry(decoded, now.add(ttl));
    }

    return decoded;
  }

  // ==========================================================
  // ✅ 共通：wp/v2 の任意endpoint + query で Post[] を取る（汎用）
  // ==========================================================
  //
  // 画面や他のメソッドは「postsを取る」なら基本ここに寄せる。
  Future<List<Post>> fetchPostsByQuery(
    Map<String, String> queryParameters, {
    String base = 'posts',
    bool homepageOnly = false,
    AppLang? lang,
  }) async {
    // ※ WP側に lang クエリが必要ならここで付与できる（Polylang等）
    final qp = <String, String>{
      '_embed': '1',
      ...queryParameters,
      if (lang != null) 'lang': lang.code,
    };

    final uri = Uri.parse('$wpV2BaseUrl/$base').replace(queryParameters: qp);
    final raw = await _getJson(uri);

    if (raw is! List) {
      return <Post>[];
    }

    final list = raw
        .whereType<Map>()
        .map((e) => Post.fromJson(e.cast<String, dynamic>()))
        .toList();

    final posts = homepageOnly
        ? list.where((p) => p.showInHomepage == true).toList()
        : list;

    posts.sort((a, b) => b.date.compareTo(a.date));
    return posts;
  }

  // ==========================================================
  // ✅ 共通：特定REST baseから投稿を取る（失敗しても空配列）
  // ==========================================================
  Future<List<Post>> _fetchPostsFromBase(
    String base, {
    required int perPage,
    int page = 1,
    String? searchQuery,
  }) async {
    try {
      final qp = <String, String>{
        '_embed': '1',
        'per_page': '$perPage',
        'page': '$page',
        if (searchQuery != null && searchQuery.trim().isNotEmpty)
          'search': searchQuery.trim(),
      };

      final uri = Uri.parse('$wpV2BaseUrl/$base').replace(queryParameters: qp);
      final raw = await _getJson(uri);

      if (raw is! List) return <Post>[];

      return raw
          .whereType<Map>()
          .map((e) => Post.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return <Post>[];
    }
  }

  // ----------------------------------------------------------------------
  // ① 通常投稿だけの一覧（postsのみ）
  // ----------------------------------------------------------------------
  Future<List<Post>> fetchLatestPosts({int page = 1, int perPage = 10}) {
    return fetchPostsByQuery(<String, String>{
      'per_page': '$perPage',
      'page': '$page',
    }, base: 'posts');
  }

  // ----------------------------------------------------------------------
  // ② 複数baseをまとめて取得（Explore用）
  // ✅ lang で base を分ける（EN/JPを混ぜない）
  // ✅ idで重複排除
  // ----------------------------------------------------------------------
  Future<List<Post>> fetchAllPosts({
    int perPage = 30,
    AppLang lang = AppLang.en,
  }) async {
    final bases = _basesByLang(lang);

    final lists = await Future.wait(
      bases.map((b) => _fetchPostsFromBase(b, perPage: perPage)),
    );

    final all = <Post>[];
    for (final l in lists) {
      all.addAll(l);
    }

    final seen = <int>{};
    final unique = <Post>[];
    for (final p in all) {
      if (seen.add(p.id)) unique.add(p);
    }

    unique.sort((a, b) => b.date.compareTo(a.date));
    return unique;
  }

  // ----------------------------------------------------------------------
  // ✅ Timeline用（軽量）
  // - posts だけ取得
  // - showInHomepage=true をここでフィルタ
  // ----------------------------------------------------------------------
  Future<List<Post>> fetchHomepagePosts({
    int perPage = 30,
    int page = 1,
    AppLang lang = AppLang.en,
  }) async {
    final posts = await fetchPostsByQuery(
      <String, String>{'per_page': '$perPage', 'page': '$page'},
      base: 'posts',
      homepageOnly: true,
      lang: lang,
    );

    return posts;
  }

  // ----------------------------------------------------------------------
  // ✅ Timeline/ページング用（TimelineScreen が呼ぶ）
  // ----------------------------------------------------------------------
  Future<List<Post>> fetchPostsPage({
    required int page,
    int perPage = 20,
    bool homepageOnly = false,
    AppLang lang = AppLang.en,
  }) async {
    return fetchPostsByQuery(
      <String, String>{'per_page': '$perPage', 'page': '$page'},
      base: 'posts',
      homepageOnly: homepageOnly,
      lang: lang,
    );
  }

  // ----------------------------------------------------------------------
  // ③ いいね API（/wp-json/gwc/v1/like）
  // ----------------------------------------------------------------------
  Future<int> sendLike(int postId) async {
    final deviceId = await _getDeviceId();
    final uri = Uri.parse('$gwcV1BaseUrl/like');

    _log(logEnabled, '➡️ POST $uri');

    final response = await _client.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'post_id': postId,
        'device_id': deviceId,
      }),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        url: uri.toString(),
        bodySnippet: _snip(response.body),
      );
    }

    final raw = jsonDecode(response.body);
    if (raw is! Map) {
      throw Exception('Unexpected JSON shape: ${raw.runtimeType}');
    }

    final map = raw.cast<String, dynamic>();
    final count = map['count'] ?? 0;

    if (count is int) return count;
    if (count is String) return int.tryParse(count) ?? 0;
    return 0;
  }

  // ----------------------------------------------------------------------
  // ④ device_id（いいね重複防止）
  // ----------------------------------------------------------------------
  //
  // ✅ Webでの RangeError 回避：
  // - 2^32 の nextInt は JS変換で事故ることがある
  // - 2^31-1（0x7fffffff）なら安全
  Future<String> _getDeviceId() async {
    const key = 'gwc_device_id';
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(key);

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final r = Random();
    final newId =
        'dev-${DateTime.now().millisecondsSinceEpoch}-${r.nextInt(0x7fffffff)}';
    await prefs.setString(key, newId);
    return newId;
  }

  // ----------------------------------------------------------------------
  // ⑤ コメント一覧（wp/v2）
  // ----------------------------------------------------------------------
  Future<List<Comment>> fetchComments(int postId) async {
    final uri = Uri.parse('$wpV2BaseUrl/comments').replace(
      queryParameters: <String, String>{
        'post': '$postId',
        'per_page': '30',
        'orderby': 'date',
        'order': 'asc',
      },
    );

    final raw = await _getJson(uri);
    if (raw is! List) {
      throw Exception('Unexpected JSON shape: ${raw.runtimeType}');
    }

    return raw
        .whereType<Map>()
        .map((e) => Comment.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // ----------------------------------------------------------------------
  // ⑥ コメント投稿（wp/v2）
  // ----------------------------------------------------------------------
  Future<void> postComment({
    required int postId,
    required String authorName,
    required String authorEmail,
    required String content,
  }) async {
    final uri = Uri.parse('$wpV2BaseUrl/comments');

    _log(logEnabled, '➡️ POST $uri');

    final response = await _client.post(
      uri,
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'post': postId,
        'author_name': authorName,
        'author_email': authorEmail,
        'content': content,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        url: uri.toString(),
        bodySnippet: _snip(response.body),
      );
    }
  }

  // ----------------------------------------------------------------------
  // ⑦ バナー（プラグイン）
  // ----------------------------------------------------------------------
  Future<ScrollBanner?> fetchScrollBanner() async {
    try {
      final uri = Uri.parse(scrollBannerApiUrl);
      final raw = await _getJson(uri);

      if (raw is! Map) return null;

      final map = raw.cast<String, dynamic>();
      final banner = ScrollBanner.fromJson(map);
      if (!banner.shouldShow) return null;

      return banner;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------------
  // ⑧ カテゴリ slug → posts 一覧（wp/v2）
  // ----------------------------------------------------------------------
  Future<List<Post>> fetchPostsByCategorySlug(
    String slug, {
    int perPage = 20,
  }) async {
    final catUri = Uri.parse(
      '$wpV2BaseUrl/categories',
    ).replace(queryParameters: <String, String>{'slug': slug});

    final catRaw = await _getJson(catUri);
    if (catRaw is! List) {
      throw Exception('Unexpected JSON shape: ${catRaw.runtimeType}');
    }
    if (catRaw.isEmpty) return <Post>[];

    final first = catRaw.first;
    if (first is! Map) {
      throw Exception('Unexpected category item: ${first.runtimeType}');
    }

    final catId = (first as Map)['id'];

    return fetchPostsByQuery(<String, String>{
      'per_page': '$perPage',
      'categories': '$catId',
    }, base: 'posts');
  }

  // ----------------------------------------------------------------------
  // ✅ 横断検索（複数base）
  // ✅ lang で対象baseを切替（EN/JP混在防止）
  // ----------------------------------------------------------------------
  Future<List<Post>> searchAllPosts({
    required String query,
    int perPage = 20,
    int page = 1,
    bool sortByDate = false,
    AppLang lang = AppLang.en,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return <Post>[];

    final bases = _basesByLang(lang);

    final lists = await Future.wait(
      bases.map(
        (b) => _fetchPostsFromBase(
          b,
          perPage: perPage,
          page: page,
          searchQuery: trimmed,
        ),
      ),
    );

    final all = <Post>[];
    for (final l in lists) {
      all.addAll(l);
    }

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

  // ----------------------------------------------------------------------
  // ✅ （任意）Reset API
  // ----------------------------------------------------------------------
  Future<Map<String, dynamic>> fetchReset({AppLang? lang}) async {
    final uri = Uri.parse('$siteBaseUrl/wp-json/gw/v1/reset').replace(
      queryParameters: <String, String>{if (lang != null) 'lang': lang.code},
    );

    final raw = await _getJson(uri);

    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return raw.cast<String, dynamic>();

    throw Exception('Reset API unexpected JSON shape: ${raw.runtimeType}');
  }
}

/// =============================================================
/// ✅ 自作「GWC Characters API」（gwc/v1）を叩くクラス
/// =============================================================
class GwcApi {
  final http.Client _client;
  final String _base;
  final bool logEnabled;

  GwcApi({http.Client? client, String? baseOverride, this.logEnabled = false})
    : _client = client ?? http.Client(),
      _base = baseOverride ?? gwcV1BaseUrl;

  String _langParam(AppLang lang) => (lang == AppLang.ja) ? 'ja' : 'en';

  Uri _u(String path, Map<String, String> q) {
    final full = '$_base/$path';
    return Uri.parse(full).replace(queryParameters: q);
  }

  List<Map<String, dynamic>> _extractItems(dynamic raw) {
    if (raw is Map<String, dynamic> && raw['items'] is List) {
      final list = raw['items'] as List;
      return list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (raw is Map && raw['items'] is List) {
      final list = raw['items'] as List;
      return list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    throw Exception('Unexpected JSON shape: ${raw.runtimeType}');
  }

  Future<dynamic> _getJson(Uri uri) async {
    _log(logEnabled, '➡️ GET $uri');

    final res = await _client.get(
      uri,
      headers: const <String, String>{'accept': 'application/json'},
    );

    if (res.statusCode != 200) {
      throw ApiException(
        statusCode: res.statusCode,
        url: uri.toString(),
        bodySnippet: _snip(res.body),
      );
    }

    return jsonDecode(res.body);
  }

  Future<List<GwcCharacter>> fetchCharacters({
    required int page,
    int perPage = 20,
    bool full = false,
    bool includeHtml = false,
    String? search,
    String? element,
    String? weaponType,
    String? rarity,
    String? role,
    String sort = 'updated', // name|rarity|updated
    String order = 'desc', // asc|desc
    AppLang lang = AppLang.en,
  }) async {
    const allowedSort = <String>{'name', 'rarity', 'updated'};
    final s = allowedSort.contains(sort) ? sort : 'updated';
    final o = (order.toLowerCase() == 'desc') ? 'desc' : 'asc';

    final q = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      'full': full ? '1' : '0',
      'include_html': includeHtml ? '1' : '0',
      'lang': _langParam(lang),
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (element != null && element.trim().isNotEmpty)
        'element': element.trim(),
      if (weaponType != null && weaponType.trim().isNotEmpty)
        'weapon_type': weaponType.trim(),
      if (rarity != null && rarity.trim().isNotEmpty) 'rarity': rarity.trim(),
      if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
      'sort': s,
      'order': o,
    };

    final uri = _u('characters', q);
    final raw = await _getJson(uri);

    final items = _extractItems(raw);
    return items.map(GwcCharacter.fromJson).toList();
  }

  Future<GwcCharacter> fetchCharacterById(
    int id, {
    AppLang? lang,
    bool full = true,
    bool includeHtml = false,
  }) async {
    final q = <String, String>{
      'full': full ? '1' : '0',
      'include_html': includeHtml ? '1' : '0',
      if (lang != null) 'lang': _langParam(lang),
    };

    final uri = _u('characters/$id', q);
    final raw = await _getJson(uri);

    if (raw is Map<String, dynamic>) {
      if (raw.containsKey('items')) {
        final items = _extractItems(raw);
        if (items.isEmpty) throw Exception('No item in response');
        return GwcCharacter.fromJson(items.first);
      }
      return GwcCharacter.fromJson(raw);
    }

    if (raw is Map) {
      final map = raw.cast<String, dynamic>();
      if (map.containsKey('items')) {
        final items = _extractItems(map);
        if (items.isEmpty) throw Exception('No item in response');
        return GwcCharacter.fromJson(items.first);
      }
      return GwcCharacter.fromJson(map);
    }

    throw Exception('Unexpected JSON shape: ${raw.runtimeType}');
  }
}

/// =============================================================
/// ✅ in-memory cache entry（超軽量）
/// =============================================================
class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
}
