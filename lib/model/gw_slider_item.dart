// lib/model/gw_slider_item.dart
import 'dart:convert';

/// ============================================================
/// GwSliderItem
/// - スライダーの「1枚ぶん」を表すデータモデル
/// - WordPress REST / meta / acf から来る JSON を Dart で扱いやすくする
/// ============================================================
class GwSliderItem {
  /// type: このスライドの種類
  /// - "image"  : 画像スライド
  /// - "youtube": YouTubeスライド
  final String type;

  /// src: 表示に必要な本体情報
  /// - image   : 画像URL
  /// - youtube : 動画URL または 動画ID
  final String src;

  /// thumb: サムネイル画像URL（任意）
  final String? thumb;

  /// title: スライドのタイトル（任意）
  final String? title;

  GwSliderItem({required this.type, required this.src, this.thumb, this.title});

  /// JSON(= Map) から GwSliderItem を作る
  factory GwSliderItem.fromJson(Map<String, dynamic> j) {
    // ✅ typeの揺れ対策：小文字＋trim
    final rawType = (j["type"] ?? "").toString().trim().toLowerCase();

    // ✅ src のキー名揺れに対応して広めに拾う（trimも重要）
    final rawSrc =
        (j["src"] ??
                j["url"] ??
                j["youtube_id"] ??
                j["youtubeId"] ??
                j["youtube_url"] ??
                j["youtubeUrl"] ??
                j["id"] ??
                "")
            .toString()
            .trim();

    // ✅ type 正規化（空/揺れを吸収）
    String normalizedType = rawType;

    // ✅ youtubeっぽいヒント（キー揺れ + URL含む）
    final hasYoutubeHint =
        j["youtube_id"] != null ||
        j["youtubeId"] != null ||
        j["youtube_url"] != null ||
        j["youtubeUrl"] != null ||
        (rawSrc.contains("youtu.be") || rawSrc.contains("youtube.com"));

    // type が空でも YouTubeのヒントがあれば youtube 扱い
    if (normalizedType.isEmpty && hasYoutubeHint) {
      normalizedType = "youtube";
    }

    // type の別名を吸収
    if (normalizedType == "video" ||
        normalizedType == "yt" ||
        normalizedType == "you") {
      normalizedType = "youtube";
    }
    if (normalizedType == "img" ||
        normalizedType == "photo" ||
        normalizedType == "picture") {
      normalizedType = "image";
    }

    return GwSliderItem(
      type: normalizedType,
      src: rawSrc,
      thumb: j["thumb"]?.toString(),
      title: j["title"]?.toString(),
    );
  }
}

/// ============================================================
/// extractGwSliderItems
/// - 記事JSONから「gw_slider_items（配列）」を探して List<GwSliderItem> にする
///
/// ✅ いろんな置き方に耐える
/// - json["gw_slider_items"]         // 直下
/// - json["meta"]["gw_slider_items"] // meta の中
/// - json["acf"]["gw_slider_items"]  // ACF の中
///
/// ✅ 無い記事でも落ちない → [] を返す
/// ✅ "JSON文字列" で返ってきても救済する
/// ============================================================
List<GwSliderItem> extractGwSliderItems(Map<String, dynamic> json) {
  dynamic raw =
      json["gw_slider_items"] ??
      (json["meta"] is Map ? (json["meta"]["gw_slider_items"]) : null) ??
      (json["acf"] is Map ? (json["acf"]["gw_slider_items"]) : null);

  // ✅ WordPress側が JSON文字列で返すケースを救済
  // 例: "[{\"type\":\"youtube\",\"youtube_id\":\"xxx\"}]"
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }

  // List じゃなければスライダー無し
  if (raw is! List) return const [];

  return raw
      .whereType<Map>()
      .map((e) => GwSliderItem.fromJson(Map<String, dynamic>.from(e)))
      .where((e) => e.type.isNotEmpty && e.src.isNotEmpty)
      .toList();
}
