import 'gw_slider_item.dart';

class Post {
  final int id;
  final String postType;
  final String title;
  final String excerpt;
  final String contentHtml;
  final String link;

  final String? imageUrl;
  final DateTime date;

  final int likeCount;
  final bool showInHomepage;
  final bool showInSlider;

  final String? pageFeaturedType;
  final String? pageVideoId;
  final String? mediaId;

  final String? youtubeId;
  final List<GwSliderItem> sliderItems;

  Post({
    required this.id,
    required this.postType,
    required this.title,
    required this.excerpt,
    required this.contentHtml,
    required this.link,
    required this.imageUrl,
    required this.date,
    required this.likeCount,
    required this.showInHomepage,
    required this.showInSlider,
    required this.pageFeaturedType,
    required this.pageVideoId,
    required this.mediaId,
    required this.youtubeId,
    this.sliderItems = const [],
  });

  bool get hasVideo => (youtubeId ?? '').trim().isNotEmpty;
  bool get hasImage => (imageUrl ?? '').trim().isNotEmpty;
  bool get hasPostSlider => sliderItems.isNotEmpty;

  factory Post.fromJson(Map<String, dynamic> json) {
    final meta = (json['meta'] is Map)
        ? (json['meta'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    String? metaStr(String key) {
      final v = meta[key];
      if (v == null) return null;
      if (v is String) return v.trim().isEmpty ? null : v.trim();
      if (v is num || v is bool) return v.toString();
      if (v is List && v.isNotEmpty) {
        final s = v.first?.toString().trim() ?? '';
        return s.isEmpty ? null : s;
      }
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    bool metaYes(String key) {
      final s = metaStr(key);
      if (s == null) return false;
      final t = s.toLowerCase();
      return t == 'yes' || t == '1' || t == 'true' || t == 'on';
    }

    final featuredType = metaStr('page_featured_type');
    final videoId = metaStr('page_video_id');

    // ✅ 安全に wp:featuredmedia を読む（無ければ null）
    String? featuredImageUrl(Map<String, dynamic> j) {
      final embedded = j['_embedded'];
      if (embedded is! Map) return null;

      final mediaList = embedded['wp:featuredmedia'];
      if (mediaList is! List || mediaList.isEmpty) return null;

      final media0 = mediaList.first;
      if (media0 is! Map) return null;

      final url = media0['source_url'];
      return (url is String && url.trim().isNotEmpty) ? url.trim() : null;
    }

    return Post(
      id: json['id'] as int,
      postType: (json['type'] as String?) ?? 'post',

      title: (json['title']?['rendered'] as String? ?? '').trim(),
      excerpt: (json['excerpt']?['rendered'] as String? ?? '').trim(),
      contentHtml: (json['content']?['rendered'] as String? ?? '').trim(),
      link: (json['link'] as String?) ?? '',

      imageUrl: featuredImageUrl(json),
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),

      likeCount: _parseInt(json['gwc_like_count'] ?? metaStr('gwc_like_count')),
      showInHomepage: metaYes('show_in_homepage'),
      showInSlider: metaYes('show_in_slider'),

      pageFeaturedType: featuredType,
      pageVideoId: videoId,
      mediaId: metaStr('media_id'),

      youtubeId: (() {
        if (videoId == null || videoId.isEmpty) return null;
        final t = featuredType?.toLowerCase().trim();
        if (t == 'youtube') return videoId;
        if (t == null || t.isEmpty) return videoId;
        return videoId;
      })(),

      sliderItems: extractGwSliderItems(json),
    );
  }
}

int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}
