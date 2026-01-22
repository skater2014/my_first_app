import 'package:flutter/foundation.dart';

// メインタブ（All, Genshin, Tekken）を切り替えるために使われます
enum YourSearchTabClass { all, genshin, tekken }

// 検索アイテム（SearchItem）を表すクラス
@immutable
class SearchItem {
  final int id;
  final String base;
  final String name;
  final DateTime date;
  final String? link;
  final String? thumbUrl;
  final Set<int> tagIds;
  final Set<int> categoryIds;
  final String? featuredType;
  final String? videoId;

  const SearchItem({
    required this.id,
    required this.base,
    required this.name,
    required this.date,
    required this.link,
    required this.thumbUrl,
    required this.tagIds,
    required this.categoryIds,
    required this.featuredType,
    required this.videoId,
  });

  bool get hasYoutube =>
      (featuredType == 'youtube') && (videoId?.trim().isNotEmpty ?? false);

  bool get isGenshin {
    final l = (link ?? '').toLowerCase();
    return l.contains('/genshin-impact/') ||
        base.startsWith('gu') ||
        base.contains('genshin') ||
        base.contains('artifacts');
  }

  bool get isTekken {
    final l = (link ?? '').toLowerCase();
    return l.contains('/tekken7/') || base.contains('tekken');
  }

  static String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  static DateTime _parseDate(dynamic v) {
    if (v is String)
      return DateTime.tryParse(v) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  static Set<int> _toIntSet(dynamic v) {
    final out = <int>{};
    if (v is List) {
      for (final x in v) {
        final n = (x is int) ? x : int.tryParse('$x');
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  static String? _pickVideoId(Map<String, dynamic> meta) {
    final pv = (meta['page_video_id'] ?? '').toString().trim();
    if (pv.isNotEmpty) return pv;
    final mid = (meta['media_id'] ?? '').toString().trim();
    if (mid.isNotEmpty) return mid;
    return null;
  }

  static String? _ytThumb(String videoId) =>
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

  factory SearchItem.fromWpPostJson(dynamic json, {required String base}) {
    final m = (json is Map<String, dynamic>) ? json : <String, dynamic>{};

    final id = (m['id'] is int)
        ? m['id'] as int
        : int.tryParse('${m['id']}') ?? 0;

    String title = '';
    final t = m['title'];
    if (t is Map && t['rendered'] != null) {
      title = '${t['rendered']}';
    } else {
      title = '${m['title'] ?? ''}';
    }
    final name = _stripHtml(title);

    final date = _parseDate(m['date']);
    final link = m['link']?.toString();

    final tagIds = _toIntSet(m['tags']);
    final categoryIds = _toIntSet(m['categories']);

    final metaRaw = m['meta'];
    final meta = (metaRaw is Map<String, dynamic>)
        ? metaRaw
        : <String, dynamic>{};
    final featuredType = (meta['page_featured_type'] ?? '').toString().trim();
    final videoId = _pickVideoId(meta);

    String? thumb;
    final emb = m['_embedded'];
    if (emb is Map && emb['wp:featuredmedia'] is List) {
      final List fm = emb['wp:featuredmedia'];
      if (fm.isNotEmpty && fm.first is Map) {
        final Map f0 = fm.first as Map;
        final src = f0['source_url']?.toString();
        if (src != null && src.trim().isNotEmpty) thumb = src;
      }
    }

    if ((thumb == null || thumb!.trim().isEmpty) &&
        videoId != null &&
        videoId.isNotEmpty) {
      thumb = _ytThumb(videoId);
    }

    return SearchItem(
      id: id,
      base: base,
      name: name,
      date: date,
      link: link,
      thumbUrl: thumb,
      tagIds: tagIds,
      categoryIds: categoryIds,
      featuredType: featuredType.isEmpty ? null : featuredType,
      videoId: videoId,
    );
  }
}
