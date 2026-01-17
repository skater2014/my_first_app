import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../model/post.dart';
import '../service/wp_api_service.dart';
import 'post_detail_screen.dart';

class GwcCategoryInfo {
  final String slug;
  final String nameJa;
  final IconData icon;

  const GwcCategoryInfo({
    required this.slug,
    required this.nameJa,
    required this.icon,
  });
}

const gwcCategories = <GwcCategoryInfo>[
  GwcCategoryInfo(
    slug: 'genshin-impact',
    nameJa: 'Genshin Impact 全体',
    icon: Icons.videogame_asset,
  ),
  GwcCategoryInfo(
    slug: 'genshin_updated',
    nameJa: 'Genshin Updated',
    icon: Icons.update,
  ),
  GwcCategoryInfo(
    slug: 'tekken7',
    nameJa: 'TEKKEN 7',
    icon: Icons.sports_martial_arts,
  ),
];

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;

          // ✅ 幅が狭いなら 1列、普通は 2列（必要なら 3列も追加できる）
          final crossAxisCount = w < 360 ? 1 : 2;

          // ✅ カードの高さを「比率」じゃなくて「固定高寄り」で安定させる
          //   1列の時は少し低め、2列の時は少し高め
          final mainAxisExtent = crossAxisCount == 1 ? 120.0 : 150.0;

          // ✅ 幅が狭いとき文字が溢れやすいので少し小さめに
          final titleFontSize = w < 360 ? 15.0 : 16.0;

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: mainAxisExtent,
            ),
            itemCount: gwcCategories.length,
            itemBuilder: (context, index) {
              final cat = gwcCategories[index];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CategoryPostsScreen(
                        slug: cat.slug,
                        title: cat.nameJa,
                      ),
                    ),
                  );
                },
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(cat.icon, size: 28),
                        const SizedBox(height: 8),

                        // ✅ タイトル（最大2行）
                        Text(
                          cat.nameJa,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: titleFontSize,
                            height: 1.15,
                          ),
                        ),

                        const Spacer(), // ✅ 下のslugを最下部に寄せて overflowしにくくする
                        // ✅ slug（1行）
                        Text(
                          cat.slug,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
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

class CategoryPostsScreen extends StatefulWidget {
  final String slug;
  final String? title;

  const CategoryPostsScreen({super.key, required this.slug, this.title});

  @override
  State<CategoryPostsScreen> createState() => _CategoryPostsScreenState();
}

class _CategoryPostsScreenState extends State<CategoryPostsScreen> {
  final _api = WpApiService();
  late Future<List<Post>> _futurePosts;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _futurePosts = _load();
  }

  Future<List<Post>> _load() async {
    final all = await _api.fetchAllPosts();
    final slug = widget.slug;

    List<Post> filtered;

    if (slug == 'genshin_updated') {
      filtered = all.where((p) => p.postType == 'genshin_updated').toList();
    } else if (slug == 'genshin-impact') {
      filtered = all.where((p) {
        final uri = Uri.tryParse(p.link);
        final path = uri?.path ?? '';
        return path.contains('/genshin-impact/');
      }).toList();
    } else if (slug == 'tekken7') {
      filtered = all.where((p) {
        final uri = Uri.tryParse(p.link);
        final path = uri?.path ?? '';
        return path.contains('/tekken7/');
      }).toList();
    } else {
      filtered = all.where((p) => p.link.contains(slug)).toList();
    }

    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  Future<void> _reload() async {
    _safeSetState(() {
      _futurePosts = _load();
    });
  }

  /// ✅ AVIFを弾く（空白/クラッシュ防止）
  String? _safeThumbUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.avif')) return null;
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.title ?? widget.slug;

    // ✅ 画像がデカすぎる警告（Highlight Oversized Images）対策：必要なサイズに縮めてキャッシュ
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final thumbCacheW = (110 * dpr).round();
    final thumbCacheH = (80 * dpr).round();

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
              return const Center(child: Text('このカテゴリの記事はまだありません'));
            }

            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                final thumbUrl = _safeThumbUrl(post.imageUrl);

                return InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(post: post),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        if (thumbUrl != null)
                          ClipRRect(
                            borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(12),
                            ),
                            child: SizedBox(
                              width: 110,
                              height: 80,
                              child: CachedNetworkImage(
                                imageUrl: thumbUrl,
                                fit: BoxFit.cover,

                                // ✅ ここが「画像デカすぎ」対策の本丸
                                memCacheWidth: thumbCacheW,
                                memCacheHeight: thumbCacheH,

                                placeholder: (_, __) => const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                errorWidget: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          )
                        else
                          const SizedBox(
                            width: 110,
                            height: 80,
                            child: Center(
                              child: Icon(Icons.image_not_supported),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
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
                                const SizedBox(height: 4),
                                Text(
                                  '${post.date.toLocal()}'.split(' ').first,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
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
