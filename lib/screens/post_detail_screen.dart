import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../model/post.dart';
import '../model/comment.dart';
import '../model/banner.dart';
import '../service/wp_api_service.dart';
import '../widgets/wp_tables.dart';
import 'category_post_list_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  const PostDetailScreen({Key? key, required this.post}) : super(key: key);

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _api = WpApiService();
  final _scrollController = ScrollController();

  late Future<ScrollBanner?> _bannerFuture;
  late Future<List<Comment>> _commentsFuture;

  ScrollBanner? _banner;
  bool _bannerVisible = false;
  double _bannerThreshold = 200;

  YoutubePlayerController? _ytController;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  String get formattedDate {
    final d = widget.post.date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}';
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String? get _videoIdOrNull {
    final raw = widget.post.youtubeId ?? widget.post.pageVideoId;
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    return YoutubePlayer.convertUrlToId(t) ?? t;
  }

  bool get _hasVideo => _videoIdOrNull != null;

  String? _safeImageUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = url.toLowerCase().split('?').first;
    if (u.endsWith('.avif')) return null; // ✅ AVIFは表示できない端末多い
    return url;
  }

  void _handleScroll() {
    if (_banner == null) return;

    final show =
        _scrollController.hasClients &&
        _scrollController.offset >= _bannerThreshold;

    if (show != _bannerVisible) {
      _safeSetState(() => _bannerVisible = show);
    }
  }

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_handleScroll);

    if (_hasVideo) {
      final id = _videoIdOrNull!;
      _ytController = YoutubePlayerController(
        initialVideoId: id,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          enableCaption: true,
        ),
      );
    }

    // ✅ dispose後 setState 対策（then内は必ず safeSetState）
    _bannerFuture = _api.fetchScrollBanner().then((b) {
      if (!mounted) return b;

      _safeSetState(() {
        _banner = b;
        if (b != null) {
          _bannerThreshold = b.scrollStart.toDouble();
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleScroll();
      });

      return b;
    });

    _commentsFuture = _api.fetchComments(widget.post.id);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _ytController?.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('カテゴリに変換できないリンクです')));
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
      final Uri uri =
          (link.startsWith('http://') || link.startsWith('https://'))
          ? Uri.parse(link)
          : Uri.parse(
              'https://dummy.local/${link.startsWith('/') ? link.substring(1) : link}',
            );

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
                  if (b.imageUrl != null && b.imageUrl!.isNotEmpty)
                    SizedBox(
                      width: 120,
                      height: double.infinity,
                      child: CachedNetworkImage(
                        imageUrl: b.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            const Center(child: CircularProgressIndicator()),
                        errorWidget: (_, __, ___) =>
                            const Center(child: Icon(Icons.broken_image)),
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

  Widget _headerMedia() {
    if (_hasVideo && _ytController != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: YoutubePlayer(
          controller: _ytController!,
          showVideoProgressIndicator: true,
        ),
      );
    }

    final img = _safeImageUrl(widget.post.imageUrl);
    if (img != null) {
      return Hero(
        tag: 'post-image-${widget.post.id}',
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: CachedNetworkImage(
            imageUrl: img,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                const Center(child: CircularProgressIndicator()),
            errorWidget: (_, __, ___) =>
                const Center(child: Icon(Icons.broken_image)),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final html = widget.post.contentHtml;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.post.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 130),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerMedia(),
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formattedDate,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.post.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // ✅ 本文：WpHtmlView が「TablePress画像 / lazy画像 / AVIF削除 / 折り返し」を全部面倒見る
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: WpHtmlView(html: html),
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Text(
                      'コメント',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  FutureBuilder<List<Comment>>(
                    future: _commentsFuture,
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
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Text('まだコメントはありません。'),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          children: [
                            for (int i = 0; i < comments.length; i++) ...[
                              _commentTile(comments[i]),
                              if (i != comments.length - 1)
                                const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
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
