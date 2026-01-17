// lib/utils/gw_youtube.dart
//
// YouTube URL/ID ユーティリティ（共通）
// - URLでもIDでも videoId(11文字) を取り出す
// - 取れない場合は null
// - サムネURL生成

String? gwExtractYoutubeId(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;

  // すでにIDっぽい（11文字）
  final idLike = RegExp(r'^[a-zA-Z0-9_-]{11}$');
  if (idLike.hasMatch(s)) return s;

  // 文字列中から11文字IDを拾えるなら拾う（壊れURL/短縮URL混在対策）
  String? pick11(String text) {
    final m = RegExp(r'([A-Za-z0-9_-]{11})').firstMatch(text);
    return m?.group(1);
  }

  Uri? uri;
  try {
    uri = Uri.parse(s);
  } catch (_) {
    return pick11(s);
  }

  final host = uri.host.toLowerCase();

  // https://youtu.be/VIDEOID
  if (host.contains('youtu.be')) {
    if (uri.pathSegments.isNotEmpty) {
      final id = uri.pathSegments.first.trim();
      return idLike.hasMatch(id) ? id : pick11(id);
    }
  }

  // https://www.youtube.com/watch?v=VIDEOID
  if (host.contains('youtube.com')) {
    final v = uri.queryParameters['v'];
    if (v != null && v.isNotEmpty) {
      return idLike.hasMatch(v) ? v : pick11(v);
    }

    // /embed/VIDEOID
    final seg = uri.pathSegments;
    final embedIndex = seg.indexOf('embed');
    if (embedIndex >= 0 && seg.length > embedIndex + 1) {
      final id = seg[embedIndex + 1];
      return idLike.hasMatch(id) ? id : pick11(id);
    }

    // /shorts/VIDEOID
    final shortsIndex = seg.indexOf('shorts');
    if (shortsIndex >= 0 && seg.length > shortsIndex + 1) {
      final id = seg[shortsIndex + 1];
      return idLike.hasMatch(id) ? id : pick11(id);
    }
  }

  // 最後の手段：文字列中から拾えるか
  return pick11(s);
}

String? gwYoutubeThumbFromSrc(String src) {
  final id = gwExtractYoutubeId(src);
  if (id == null) return null;
  return 'https://img.youtube.com/vi/$id/hqdefault.jpg';
}
