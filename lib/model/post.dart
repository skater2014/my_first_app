// lib/model/post.dart

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

  /// ✅ YouTube動画として扱うためのID（基本はこれだけ見ればOK）
  /// - pageVideoId が入っていれば youtubeId に入れる方針（type未設定でも消えない）
  final String? youtubeId;

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
  });

  // ✅ getter追加：UI側が読みやすくなる
  bool get hasVideo => (youtubeId ?? '').trim().isNotEmpty;
  bool get hasImage => (imageUrl ?? '').trim().isNotEmpty;

  factory Post.fromJson(Map<String, dynamic> json) {
    // meta を安全に取得（無い/型違い対策）
    final meta = (json['meta'] is Map)
        ? (json['meta'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    // meta値を「とにかく文字列」で取る
    String? metaStr(String key) {
      final v = meta[key];
      if (v == null) return null;

      if (v is String) {
        final s = v.trim();
        return s.isEmpty ? null : s;
      }
      if (v is num || v is bool) return v.toString();
      if (v is List && v.isNotEmpty) {
        final first = v.first;
        if (first == null) return null;
        final s = first.toString().trim();
        return s.isEmpty ? null : s;
      }
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // yes/1/true/on を true 扱い（WP保存揺れ対策）
    bool metaYes(String key) {
      final s = metaStr(key);
      if (s == null) return false;
      final t = s.toLowerCase();
      return t == 'yes' || t == '1' || t == 'true' || t == 'on';
    }

    final featuredType = metaStr('page_featured_type');
    final videoId = metaStr('page_video_id');

    return Post(
      id: json['id'] as int,
      postType: (json['type'] as String?) ?? 'post',

      title: (json['title']?['rendered'] as String? ?? '').trim(),
      excerpt: (json['excerpt']?['rendered'] as String? ?? '').trim(),
      contentHtml: (json['content']?['rendered'] as String? ?? '').trim(),

      link: (json['link'] as String?) ?? '',

      imageUrl: (() {
        final embedded = json['_embedded'] as Map<String, dynamic>?;
        final mediaList = embedded?['wp:featuredmedia'] as List<dynamic>?;
        if (mediaList == null || mediaList.isEmpty) return null;
        final media = mediaList.first as Map<String, dynamic>;
        return media['source_url'] as String?;
      })(),

      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),

      likeCount: _parseInt(json['gwc_like_count'] ?? metaStr('gwc_like_count')),

      showInHomepage: metaYes('show_in_homepage'),
      showInSlider: metaYes('show_in_slider'),

      pageFeaturedType: featuredType,
      pageVideoId: videoId,
      mediaId: metaStr('media_id'),

      // ✅ 重要：typeが無くても videoId が入ってるなら “動画扱い” にする
      youtubeId: (() {
        if (videoId == null || videoId.isEmpty) return null;

        final t = featuredType?.toLowerCase().trim();

        // youtube明示は採用
        if (t == 'youtube') return videoId;

        // type未設定でも “消さない” 方針で採用（動画が消える事故を防ぐ）
        if (t == null || t.isEmpty) return videoId;

        // 将来：youtube以外を弾きたいならここで null にする
        return videoId;
      })(),
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
