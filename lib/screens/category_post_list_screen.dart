import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ★ 追加：Firebase Analytics
import 'package:firebase_analytics/firebase_analytics.dart';

import '../model/post.dart';
import '../service/wp_api_service.dart';
import 'post_detail_screen.dart';

class CategoryPostListScreen extends StatefulWidget {
  final String categorySlug;
  final String? title;

  const CategoryPostListScreen({
    super.key,
    required this.categorySlug,
    this.title,
  });

  @override
  State<CategoryPostListScreen> createState() => _CategoryPostListScreenState();
}

class _CategoryPostListScreenState extends State<CategoryPostListScreen> {
  final _api = WpApiService();
  late Future<List<Post>> _futurePosts;

  // ★ 同じ画面で何度も screen_view を送らないためのフラグ
  bool _sentScreenView = false;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _futurePosts = _load();
  }

  // ★ ここが重要：この画面が「表示されたタイミング」で screen_view を送る
  // initState だけだとタイミングが早すぎる事があるので didChangeDependencies が安全
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sentScreenView) return;
    _sentScreenView = true;

    // ★ 画面名を slug 入りでユニークにする（これが “genshin / tekken7” を分ける）
    // 例：category/genshin-impact, category/tekken7
    final screenName = 'category/${widget.categorySlug}';

    FirebaseAnalytics.instance.logScreenView(
      screenName: screenName,
      // ★ スクリーンクラスは “画面の種類” として固定でOK（分類）
      screenClass: 'CategoryPostListScreen',
    );
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('\r', '')
        .replaceAll('\n\n', '\n')
        .trim();
  }

  String? _safeThumbUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.avif')) return null;
    return url;
  }

  Future<List<Post>> _load() async {
    final all = await _api.fetchAllPosts();
    final slug = widget.categorySlug;

    bool belongs(Post p) {
      try {
        final uri = Uri.parse(p.link);
        final segments = uri.path
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();

        if (slug == 'genshin-impact')
          return segments.contains('genshin-impact');
        if (slug == 'genshin_updated')
          return segments.contains('genshin_updated');
        if (slug == 'tekken7') return segments.contains('tekken7');

        return p.link.contains(slug);
      } catch (_) {
        return p.link.contains(slug);
      }
    }

    final filtered = all.where(belongs).toList();
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  Future<void> _reload() async {
    _safeSetState(() {
      _futurePosts = _load();
    });
  }

  Widget _postCard(Post post) {
    final thumb = _safeThumbUrl(post.imageUrl);
    final excerpt = _stripHtml(post.excerpt);

    return InkWell(
      onTap: () {
        // ★ ここで PostDetailScreen に push している
        // だから PostDetailScreen 側にも screen_view を入れると「記事詳細」も追える
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)));
      },
      borderRadius: BorderRadius.circular(14),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            if (thumb != null)
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
                child: SizedBox(
                  width: 120,
                  height: 86,
                  child: CachedNetworkImage(
                    imageUrl: thumb,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) =>
                        const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              )
            else
              Container(
                width: 120,
                height: 86,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(14),
                  ),
                ),
                child: const Icon(Icons.article, size: 28),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${post.date.toLocal()}'.split(' ').first,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (excerpt.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? widget.categorySlug;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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

            final posts = snapshot.data ?? [];
            if (posts.isEmpty) {
              return const Center(child: Text('まだ投稿がありません'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: posts.length,
              itemBuilder: (context, i) => _postCard(posts[i]),
            );
          },
        ),
      ),
    );
  }
}
