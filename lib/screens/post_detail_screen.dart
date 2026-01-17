import 'dart:async';

import 'package:flutter/foundation.dart'
    show compute, debugPrint, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// HTML parse
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../model/post.dart';
import '../model/comment.dart';
import '../model/banner.dart';
import '../service/wp_api_service.dart';

import 'category_post_list_screen.dart';
import '../widgets/gw_post_slider.dart';
import '../widgets/wp_html_view.dart';
import '../widgets/wp_tables.dart';
import '../widgets/gw_youtube_player.dart';
import '../utils/gw_youtube.dart';

// =======================
// isolate parse result
// =======================
class _ParsedPostHtml {
  final List<String> tables;
  final String htmlWithoutTables;
  const _ParsedPostHtml({required this.tables, required this.htmlWithoutTables});
}

_ParsedPostHtml _parsePostHtml(String rawHtml) {
  final frag1 = html_parser.parseFragment(rawHtml);
  final tables =
      frag1.querySelectorAll('table').map((t) => t.outerHtml).toList();

  final dom.DocumentFragment frag2 = html_parser.parseFragment(rawHtml);
  for (final t in frag2.querySelectorAll('table')) {
    t.remove();
  }
  final wrapper = dom.Element.tag('div')..nodes.addAll(frag2.nodes);

  return _ParsedPostHtml(tables: tables, htmlWithoutTables: wrapper.innerHtml);
}

class PostDetailScreen extends StatefulWidget {
  final Post post;
  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _api = WpApiService();
  final _scroll = ScrollController();

  late final Future<_ParsedPostHtml> _parseFuture;

  late final Future<ScrollBanner?> _bannerFuture;
  late final Future<List<Comment>> _commentsFuture;

  ScrollBanner? _banner;
  bool _bannerVisible = false;
  double _bannerThreshold = 200;

  bool get _canPlayYoutube {
    if (kIsWeb) return true; // webはplayer使う
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    // ✅ macOS/Windows/Linux は false（153回避）
  }

  @override
  void initState() {
    super.initState();

    _scroll.addListener(_onScroll);

    _parseFuture = compute(_parsePostHtml, widget.post.contentHtml);

    _bannerFuture = _api.fetchScrollBanner().then((b) {
      if (!mounted) return b;
      setState(() {
        _banner = b;
        if (b != null) _bannerThreshold = b.scrollStart.toDouble();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
      return b;
    });

    _commentsFuture = _api.fetchComments(widget.post.id);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_banner == null) return;
    if (!_scroll.hasClients) return;

    final show = _scroll.offset >= _bannerThreshold;
    if (show != _bannerVisible) {
      setState(() => _bannerVisible = show);
    }
  }

  // ===== helpers =====
  String two(int n) => n.toString().padLeft(2, '0');

  String get formattedDate {
    final d = widget.post.date.toLocal();
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String? get _videoIdOrNull {
    final raw = (widget.post.youtubeId ?? widget.post.pageVideoId)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return gwExtractYoutubeId(raw);
  }

  String? _safeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.avif')) return null;
    return url;
  }

  // ===== banner =====
  Color _parseHexColor(String hex, {Color fallback = Colors.black}) {
    try {
      var v = hex.replaceAll('#', '').trim();
      if (v.length == 6) v = 'FF$v';
      return Color(int.parse(v, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Decoration _bannerDecoration(ScrollBanner b) {
    final g = b.gradient;
    if (g != null) {
      final colors = <Color>[];
      if ((g.color1 ?? '').isNotEmpty) colors.add(_parseHexColor(g.color1!));
      if ((g.color2 ?? '').isNotEmpty) colors.add(_parseHexColor(g.color2!));
      if ((g.color3 ?? '').isNotEmpty) colors.add(_parseHexColor(g.color3!));
      if (colors.length >= 2) {
        return BoxDecoration(gradient: LinearGradient(colors: colors));
      }
    }
    final bg = b.fontStyle?.backgroundColor;
    return BoxDecoration(color: bg ?? Colors.black);
  }

  TextStyle _bannerTextStyle(ScrollBanner b) {
    final f = b.fontStyle;
    if (f == null) {
      return const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      );
    }
    return TextStyle(
      fontSize: f.size,
      fontWeight: f.isBold ? FontWeight.bold : FontWeight.normal,
      color: f.color ?? Colors.white,
    );
  }

  void _onBannerTap(ScrollBanner b) {
    final link = (b.link ?? '').trim();
    if (link.isEmpty) return;

    final slug = _extractCategorySlugFromLink(link);
    if (slug == null || slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カテゴリに変換できないリンクです')),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryPostListScreen(
          categorySlug: slug,
          title: (b.message ?? '').trim().isEmpty ? slug : b.message,
        ),
      ),
    );
  }

  String? _extractCategorySlugFromLink(String link) {
    try {
      final uri = (link.startsWith('http://') || link.startsWith('https://'))
          ? Uri.parse(link)
          : Uri.parse('https://dummy.local/${link.startsWith('/') ? link.substring(1) : link}');

      final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final idx = seg.indexOf('category');
      if (idx >= 0 && seg.length > idx + 1) return seg[idx + 1];
      if (seg.length == 1) return seg.first;
      return null;
    } catch (_) {
      final t = link.trim();
      if (t.isEmpty) return null;
      return t.replaceAll('/', '');
    }
  }

  Widget _bannerWidget(ScrollBanner b) {
    final message = (b.message ?? '').trim();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _onBannerTap(b),
            child: Container(
              height: 74,
              decoration: _bannerDecoration(b),
              child: Row(
                children: [
                  if ((b.imageUrl ?? '').isNotEmpty)
                    SizedBox(
                      width: 120,
                      height: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: b.imageUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: (120 * MediaQuery.of(context).devicePixelRatio).round(),
                        placeholder: (_, __) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) => Container(color: Colors.black12),
                      ),
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        message.isEmpty ? 'お知らせ' : message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _bannerTextStyle(b),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.chevron_right, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== header media =====
  Widget _headerMedia() {
    final vid = _videoIdOrNull;
    if (vid != null && vid.isNotEmpty) {
      // ✅ macOS/Windows/Linux は再生しない。サムネ固定。
      if (!_canPlayYoutube) {
        final thumb = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: CachedNetworkImage(
            imageUrl: thumb,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.black12),
            errorWidget: (_, __, ___) => Container(color: Colors.black12),
          ),
        );
      }

      return GwYoutubePlayer(videoId: vid);
    }

    final img = _safeImageUrl(widget.post.imageUrl);
    if (img == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final w = constraints.maxWidth;
        const ratio = 16 / 9;
        final h = w / ratio;
        final cacheW = (w * dpr).round();
        final cacheH = (h * dpr).round();

        return AspectRatio(
          aspectRatio: ratio,
          child: CachedNetworkImage(
            imageUrl: img,
            fit: BoxFit.cover,
            memCacheWidth: cacheW,
            memCacheHeight: cacheH,
            placeholder: (_, __) => Container(color: Colors.black12),
            errorWidget: (_, __, ___) => Container(color: Colors.black12),
          ),
        );
      },
    );
  }

  Widget _commentTile(Comment c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.authorName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatDateTime(c.date),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(c.content, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sliderItems = widget.post.sliderItems;
    final hasSlider = sliderItems.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.post.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            FutureBuilder<_ParsedPostHtml>(
              future: _parseFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('本文解析エラー: ${snap.error}'));
                }

                final parsed = snap.data!;
                debugPrint('TABLE COUNT=${parsed.tables.length} postId=${widget.post.id}');

                return CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: hasSlider
                          ? GwPostSlider(items: sliderItems) // ✅ slider側もmac再生しない（別ファイルで修正）
                          : _headerMedia(),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formattedDate,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.post.title,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    const SliverToBoxAdapter(child: Divider(height: 1)),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: WpHtmlView(html: parsed.htmlWithoutTables),
                      ),
                    ),

                    if (parsed.tables.isNotEmpty) ...[
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '表',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final html = parsed.tables[i];
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: WpTablesView(tableHtml: html),
                            );
                          },
                          childCount: parsed.tables.length,
                        ),
                      ),
                    ],

                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    const SliverToBoxAdapter(child: Divider(height: 1)),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Text(
                          'コメント',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: _CommentsSection(
                        future: _commentsFuture,
                        tileBuilder: _commentTile,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 130)),
                  ],
                );
              },
            ),

            FutureBuilder<ScrollBanner?>(
              future: _bannerFuture,
              builder: (context, snapshot) {
                final b = _banner ?? snapshot.data;
                if (b == null) return const SizedBox.shrink();
                if (!b.shouldShow) return const SizedBox.shrink();
                if (!_bannerVisible) return const SizedBox.shrink();

                return Align(
                  alignment: Alignment.bottomCenter,
                  child: _bannerWidget(b),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentsSection extends StatelessWidget {
  const _CommentsSection({required this.future, required this.tileBuilder});
  final Future<List<Comment>> future;
  final Widget Function(Comment c) tileBuilder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Comment>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('コメント取得エラー: ${snapshot.error}'),
          );
        }

        final comments = snapshot.data ?? [];
        if (comments.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('まだコメントはありません。'),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            children: [
              for (int i = 0; i < comments.length; i++) ...[
                tileBuilder(comments[i]),
                if (i != comments.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}
