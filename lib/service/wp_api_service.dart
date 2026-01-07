// lib/service/wp_api_service.dart
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../model/post.dart';
import '../model/comment.dart';
import '../model/banner.dart';

/// WordPress REST API を叩くサービス
///
/// ==========================================================
/// ✅ このクラスの目的（このアプリの根っこ）
/// ==========================================================
/// 1) 投稿一覧を取る（複数 post_type を混ぜる）
///    - タイムライン / Explore / Search で使う
///
/// 2) いいねを送信する（device_idで重複防止）
///
/// 3) コメントを取得/投稿する
///
/// 4) スクロールバナーを取得する
///
/// ==========================================================
/// ✅ ここが重要（あなたの混乱ポイント）
/// ==========================================================
/// ● 「検索一覧で genshin_updated が出ない」理由は、
///   そもそも検索対象 REST に genshin_updated を含めていないから。
///
/// ● ただし「含めたのに出ない」場合はWP側の設定問題：
///   - show_in_rest = true になってない
///   - RESTのパス名（rest_base）が post_type と一致していない
///
/// 例：
///   register_post_type('genshin_updated', [
///     'show_in_rest' => true,
///     'rest_base'    => 'genshin_updated', // ←これが違うと404
///   ]);
///
///   ✅ まずブラウザで確認：
///   https://あなたのドメイン/wp-json/wp/v2/genshin_updated
///   - 200 → Flutter側で出せる
///   - 404 → WP側のrest_baseが違う or REST無効
///
/// ==========================================================
/// ✅ さらに重要（検索順の話）
/// ==========================================================
/// 「sortByDate=falseにしたから WPの検索順を尊重できる」
/// → これは “単一post_typeだけ” なら正しい。
///
/// でも複数post_typeを合体すると、
/// 全体の並びは “WPの関連順” にはならない。
///
/// なぜなら：
///   postsの結果 + guの結果 + gu-jpの結果 + ... を
///   「配列をくっつけた順」で並ぶから。
///
/// ✅ だから「tekken7が後ろに流れる」のは普通に起きる。
///
/// → 真の関連順が必要なら、後で
///   - WP側で統合検索APIを作る
///   - もしくは Flutter側で簡易スコアリング（タイトル一致優先など）
///   のどちらかが必要。
class WpApiService {
  final http.Client _client;

  WpApiService({http.Client? client}) : _client = client ?? http.Client();

  // ==========================================================
  // ✅ ここが本体：横断対象の REST base 一覧
  // ==========================================================
  //
  // 目的：
  // - タイムライン/Explore/Search で “対象にしたい投稿タイプ” を
  //   ここに全部並べる
  //
  // 注意：
  // - ここに書いた文字列は “post_type名” ではなく
  //   “RESTのパス名(rest_base)” を想定
  //
  // 例：
  // - 標準投稿: posts
  // - CPT: gu, gu-jp, genshin_updated, ...
  //
  // ✅ もし 404 が出るなら、WP側の rest_base を確認してここを合わせる
  static const List<String> _restBases = [
    'posts',
    'gu',
    'gu-jp',
    'genshin_updated',
    'genshin_updated_jp',
    'artifacts',
  ];

  // ==========================================================
  // ✅ 共通：特定のREST baseから投稿を取って Post リストにする
  // ==========================================================
  //
  // 目的：
  // - fetchAllPosts と searchAllPosts の両方で同じ処理を使う
  //
  // ポリシー：
  // - 失敗しても例外で落とさず「空配列」で返す（アプリを止めない）
  //
  // 注意：
  // - per_page/page は WP REST の制約を受ける（上限など）
  // - searchQuery は WP標準の全文検索（タイトル/本文など対象）
  Future<List<Post>> _fetchPostsFromBase(
    String base, {
    required int perPage,
    int page = 1,
    String? searchQuery,
  }) async {
    try {
      // ----------------------------
      // クエリパラメータを組み立てる
      // ----------------------------
      //
      // _embed=1:
      //   - アイキャッチ画像など埋め込み情報を取りたい時に便利
      //
      // per_page/page:
      //   - ページング
      //
      // search:
      //   - WordPress標準の検索（全文検索）
      final qp = <String>['_embed=1', 'per_page=$perPage', 'page=$page'];

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        // ✅ URLエンコード（スペースや記号対策）
        final q = Uri.encodeQueryComponent(searchQuery.trim());
        qp.add('search=$q');
      }

      // 例: https://example.com/wp-json/wp/v2/posts?_embed=1&per_page=30&page=1&search=genshin
      final uri = Uri.parse('$wpBaseUrl/$base?${qp.join("&")}');

      final res = await _client.get(uri);

      // ✅ 200以外は “その投稿タイプは取れない” とみなして空で返す
      if (res.statusCode != 200) return [];

      final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;

      // ✅ JSON → Post モデル
      return list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // ネットワーク障害 / JSON壊れ / 404など全部ここに来る
      return [];
    }
  }

  // ----------------------------------------------------------------------
  // ① 通常投稿だけの一覧（関連記事用など）
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - “postsだけ” が欲しい場面用（関連記事など）
  //
  // 注意：
  // - この関数は CPT を混ぜない（posts専用）
  Future<List<Post>> fetchLatestPosts({int page = 1, int perPage = 10}) async {
    final uri = Uri.parse(
      '$wpBaseUrl/posts?_embed=1&per_page=$perPage&page=$page',
    );
    final res = await _client.get(uri);

    if (res.statusCode != 200) {
      throw Exception('Failed to load posts: ${res.statusCode}');
    }

    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((json) => Post.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------------------
  // ② 複数post_typeをまとめて取得（タイムライン/Explore用）
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - Explore や タイムラインで “全部混ぜて” 表示する
  //
  // ポリシー：
  // - ここは日付順でOK（新しい順）
  //
  // 注意：
  // - WPは投稿タイプごとに別エンドポイントなので
  //   Future.waitで並列取得 → 合体 → 日付ソート、という流れにする
  Future<List<Post>> fetchAllPosts({int perPage = 50}) async {
    // ✅ 全REST baseを並列で取得（速い）
    final lists = await Future.wait(
      _restBases.map((b) => _fetchPostsFromBase(b, perPage: perPage)),
    );

    // ✅ 合体
    final allPosts = <Post>[];
    for (final l in lists) {
      allPosts.addAll(l);
    }

    // ✅ 重複除去（安全策）
    //
    // 目的：
    // - 何らかの理由で同じIDが混ざった時に、Grid/Listで変な挙動を防ぐ
    final seen = <int>{};
    final unique = <Post>[];
    for (final p in allPosts) {
      if (seen.add(p.id)) unique.add(p);
    }

    // ✅ 新しい順
    unique.sort((a, b) => b.date.compareTo(a.date));
    return unique;
  }

  // ----------------------------------------------------------------------
  // ③ いいね API（/wp-json/gwc/v1/like）
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - Flutterから “いいね” を送って WordPress側で加算する
  //
  // 注意：
  // - device_id を送って、同じ端末が連打しても増えないようにする
  Future<int> sendLike(int postId) async {
    final deviceId = await _getDeviceId();

    // wpBaseUrl 例： https://example.com/wp-json/wp/v2
    // これを https://example.com/wp-json に戻す（カスタムルート用）
    final restBase = wpBaseUrl.replaceFirst(RegExp(r'/wp/v2/?$'), '');
    final uri = Uri.parse('$restBase/gwc/v1/like');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'post_id': postId, 'device_id': deviceId}),
    );

    if (response.statusCode != 200) {
      throw Exception('Like API error: ${response.statusCode}');
    }

    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;

    // APIが { count: 123 } を返す想定
    return (json['count'] ?? 0) as int;
  }

  // ----------------------------------------------------------------------
  // ④ device_id（いいね重複防止）
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - 端末固有IDを SharedPreferences に保存して再利用する
  //
  // ポリシー：
  // - 一度作ったらずっと同じID（アプリ再起動でも保持）
  Future<String> _getDeviceId() async {
    const key = 'gwc_device_id';
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(key);

    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random();
    final newId =
        'dev-${DateTime.now().millisecondsSinceEpoch}-${random.nextInt(1 << 32)}';
    await prefs.setString(key, newId);
    return newId;
  }

  // ----------------------------------------------------------------------
  // ⑤ コメント一覧
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - 投稿詳細でコメントを表示する
  //
  // order=asc:
  // - 古い→新しい順（会話が読みやすい）
  Future<List<Comment>> fetchComments(int postId) async {
    final uri = Uri.parse(
      '$wpBaseUrl/comments?post=$postId&per_page=100&orderby=date&order=asc',
    );

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to load comments: ${response.statusCode}');
    }

    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .map((e) => Comment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------------------
  // ⑥ コメント投稿
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - Flutterからコメントを送る
  //
  // 注意：
  // - WP側の設定によっては認証が必要な場合もある
  // - 今は “匿名投稿できる設定” を前提にしている
  Future<void> postComment({
    required int postId,
    required String authorName,
    required String authorEmail,
    required String content,
  }) async {
    final uri = Uri.parse('$wpBaseUrl/comments');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'post': postId,
        'author_name': authorName,
        'author_email': authorEmail,
        'content': content,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Failed to post comment: status ${response.statusCode}');
    }
  }

  // ----------------------------------------------------------------------
  // ⑦ バナー
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - スクロールバナー設定をWPから取得する
  //
  // ポリシー：
  // - 失敗しても null（バナー無しで動く）
  Future<ScrollBanner?> fetchScrollBanner() async {
    try {
      final uri = Uri.parse(scrollBannerApiUrl);
      final res = await _client.get(uri);

      if (res.statusCode != 200) return null;

      final dynamic raw = jsonDecode(res.body);
      if (raw is! Map<String, dynamic>) return null;

      final banner = ScrollBanner.fromJson(raw);

      // ✅ shouldShow=falseなら表示しない（null扱い）
      if (!banner.shouldShow) return null;

      return banner;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------------
  // ⑧ 通常カテゴリ slug から post 一覧を取る（posts専用）
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - バナーのリンクなどからカテゴリ一覧へ飛ぶ場合に使う
  //
  // 注意：
  // - これは “postsのカテゴリ” 前提
  // - CPT側のカテゴリ体系を使うなら別実装が必要
  Future<List<Post>> fetchPostsByCategorySlug(
    String slug, {
    int perPage = 20,
  }) async {
    final catUri = Uri.parse('$wpBaseUrl/categories?slug=$slug');
    final catRes = await _client.get(catUri);

    if (catRes.statusCode != 200) {
      throw Exception('Failed to load category: ${catRes.statusCode}');
    }

    final List<dynamic> catJson = jsonDecode(catRes.body) as List<dynamic>;
    if (catJson.isEmpty) return [];

    final int catId = catJson.first['id'] as int;

    final postsUri = Uri.parse(
      '$wpBaseUrl/posts?_embed=1&per_page=$perPage&categories=$catId',
    );
    final postsRes = await _client.get(postsUri);

    if (postsRes.statusCode != 200) {
      throw Exception('Failed to load category posts: ${postsRes.statusCode}');
    }

    final List<dynamic> postsJson = jsonDecode(postsRes.body) as List<dynamic>;
    return postsJson
        .map((e) => Post.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ----------------------------------------------------------------------
  // ✅ 横断検索（複数post_type）
  // ----------------------------------------------------------------------
  //
  // 目的：
  // - SearchScreen から呼ばれて、キーワード検索結果を返す
  //
  // “search” の正体：
  // - WordPress標準 `?search=` パラメータ（全文検索）
  // - タイトル/本文などが対象
  //
  // ✅ 重要：並びの話（あなたが混乱していたポイント）
  // - sortByDate=false にしても、複数post_typeを合体した時点で
  //   “全体としての関連順” にはならない。
  //
  // なぜ：
  // - postsの結果 → guの結果 → ... を単純に「順番にくっつける」から。
  //
  // ✅ 改善したい場合：
  // - Flutter側で “簡易スコアリング” を入れる
  //   (タイトル完全一致 > タイトル部分一致 > 本文一致 など)
  // - または WP側に “統合検索API” を作って、サーバー側で関連順を返す
  Future<List<Post>> searchAllPosts({
    required String query,
    int perPage = 30,
    int page = 1,
    bool sortByDate = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // ✅ 全post_type（REST base）で並列検索
    final lists = await Future.wait(
      _restBases.map(
        (b) => _fetchPostsFromBase(
          b,
          perPage: perPage,
          page: page,
          searchQuery: trimmed,
        ),
      ),
    );

    // ✅ 合体
    final all = <Post>[];
    for (final l in lists) {
      all.addAll(l);
    }

    // ✅ 重複除去（安全策）
    final seen = <int>{};
    final unique = <Post>[];
    for (final p in all) {
      if (seen.add(p.id)) unique.add(p);
    }

    // ✅ 必要なら日付順（ただし関連順は壊れる）
    if (sortByDate) {
      unique.sort((a, b) => b.date.compareTo(a.date));
    }

    return unique;
  }
}
