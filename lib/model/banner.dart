// lib/model/banner.dart

import 'package:flutter/material.dart';

/// /wp-json/scroll-banner/v1/info の JSON モデル
class ScrollBanner {
  final int? id;
  final String? imageUrl;
  final String? link;
  final String? message;

  /// 管理画面の「バナー非表示」
  final bool hide;

  /// Web の「Turn Off Ads」用（アプリでは無視でOK）
  final bool userHide;

  /// 何 px スクロールしたら出すか
  final int scrollStart;

  /// 文字のスタイル
  final BannerFontStyle? fontStyle;

  /// 背景グラデーション
  final BannerGradientStyle? gradient;

  ScrollBanner({
    this.id,
    this.imageUrl,
    this.link,
    this.message,
    required this.hide,
    required this.userHide,
    required this.scrollStart,
    this.fontStyle,
    this.gradient,
  });

  factory ScrollBanner.fromJson(Map<String, dynamic> json) {
    return ScrollBanner(
      id: json['id'] as int?,
      imageUrl: json['image_url'] as String?,
      link: json['link'] as String?,
      message: json['message'] as String?,
      hide: (json['hide'] ?? false) == true,
      userHide: (json['user_hide'] ?? false) == true,
      scrollStart: json['scroll_start'] is int
          ? json['scroll_start'] as int
          : 200,
      fontStyle: json['font'] is Map<String, dynamic>
          ? BannerFontStyle.fromJson(json['font'] as Map<String, dynamic>)
          : null,
      gradient: json['gradient'] is Map<String, dynamic>
          ? BannerGradientStyle.fromJson(
              json['gradient'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  /// アプリで「出すかどうか」の最終判定
  bool get shouldShow {
    if (hide) return false;
    if (imageUrl == null || imageUrl!.isEmpty) return false;
    return true;
  }
}

/// JSON の font ブロック
class BannerFontStyle {
  final double size;
  final String unit; // "px" など
  final String weight; // "normal" / "bold" など
  final String? colorHex;
  final String? backgroundHex;

  BannerFontStyle({
    required this.size,
    required this.unit,
    required this.weight,
    this.colorHex,
    this.backgroundHex,
  });

  factory BannerFontStyle.fromJson(Map<String, dynamic> json) {
    return BannerFontStyle(
      size: (json['size'] is num) ? (json['size'] as num).toDouble() : 14.0,
      unit: json['unit'] as String? ?? 'px',
      weight: json['weight'] as String? ?? 'normal',
      colorHex: json['color'] as String?,
      backgroundHex: json['background_color'] as String?,
    );
  }

  /// "#RRGGBB" → Color（文字色）
  Color? get color {
    if (colorHex == null || colorHex!.isEmpty) return null;
    return _parseColor(colorHex!);
  }

  /// "#RRGGBB" → Color（背景色）
  Color? get backgroundColor {
    if (backgroundHex == null || backgroundHex!.isEmpty) return null;
    return _parseColor(backgroundHex!);
  }

  /// weight に "bold" が含まれていたら太字扱い
  bool get isBold => weight.toLowerCase().contains('bold');

  Color _parseColor(String hex) {
    var value = hex.replaceAll('#', '');
    if (value.length == 6) {
      // #RRGGBB → #FFRRGGBB（不透明）
      value = 'FF$value';
    }
    final intColor = int.parse(value, radix: 16);
    return Color(intColor);
  }
}

/// JSON の gradient ブロック
class BannerGradientStyle {
  final String? color1;
  final String? color2;
  final String? color3;
  final String? preset;

  BannerGradientStyle({this.color1, this.color2, this.color3, this.preset});

  factory BannerGradientStyle.fromJson(Map<String, dynamic> json) {
    return BannerGradientStyle(
      color1: json['color_1'] as String?,
      color2: json['color_2'] as String?,
      color3: json['color_3'] as String?,
      preset: json['preset'] as String?,
    );
  }
}
