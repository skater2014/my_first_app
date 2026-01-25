// lib/model/character.dart
import 'package:flutter/material.dart'; // ✅ Color / Colors を使うため

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String _slugFromLink(String link) {
  final u = Uri.tryParse(link);
  if (u == null) return '';
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  return segs.isEmpty ? '' : segs.last;
}

// element URL から "Anemo" 等を復元（フィルタ表示用）
String _elementTypeFromIconUrl(String url) {
  final m = RegExp(
    r'Element_([A-Za-z]+)',
    caseSensitive: false,
  ).firstMatch(url);
  if (m == null) return '';
  final raw = (m.group(1) ?? '').trim();
  if (raw.isEmpty) return '';
  return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
}

class GenshinCharacter {
  /// ✅ gwc/v1/characters の "id"（= ビルド記事ID）
  final int id;

  /// ✅ 詳細ページ遷移に使う
  final String slug;
  final String permalink;

  final String name; // char_name
  final String rarity; // "4" or "5" たまに "★5" みたいなのも来る想定
  final String weaponType; // weapon_type
  final String portraitUrl; // portrait
  final String role;

  final String elementIconUrl; // element (URL)
  final String weaponIconUrl; // weapon (URL)

  const GenshinCharacter({
    required this.id,
    required this.slug,
    required this.permalink,
    required this.name,
    required this.rarity,
    required this.weaponType,
    required this.portraitUrl,
    required this.role,
    required this.elementIconUrl,
    required this.weaponIconUrl,
  });

  // ==========================================================
  // rarity / bg
  // ==========================================================

  /// ✅ rarity を int に正規化（"5", "★5", "rarity:5" みたいなの全部OK）
  int get rarityInt {
    final digits = rarity.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  bool get isFiveStar => rarityInt >= 5;

  String get rarityBgUrl {
    return isFiveStar
        ? 'https://gamewidth.net/wp-content/themes/Xiaoyu%20Tekken7/images/genshin/5_sm.png'
        : 'https://gamewidth.net/wp-content/themes/Xiaoyu%20Tekken7/images/genshin/4_sm.png';
  }

  /// ✅ 4★/5★でグラデの濃さを変える
  List<Color> get rarityGradientColors {
    if (isFiveStar) {
      return [
        Colors.white.withOpacity(0.10),
        Colors.transparent,
        Colors.black.withOpacity(0.30),
      ];
    }
    return [
      Colors.black.withOpacity(0.12),
      Colors.transparent,
      Colors.black.withOpacity(0.38),
    ];
  }

  List<double> get rarityGradientStops => const [0.0, 0.55, 1.0];

  // ==========================================================
  // filter helpers
  // ==========================================================
  String get elementType => _elementTypeFromIconUrl(elementIconUrl);

  /// slug が空でも permalink から拾う保険
  String get resolvedSlug {
    final s = slug.trim();
    if (s.isNotEmpty) return s;
    final p = permalink.trim();
    if (p.isNotEmpty) return _slugFromLink(p);
    return '';
  }

  factory GenshinCharacter.fromJson(Map<String, dynamic> json) {
    return GenshinCharacter(
      id: _toInt(json['id']), // ✅ ここだけでOK
      slug: (json['slug'] ?? '').toString(),
      permalink: (json['permalink'] ?? '').toString(),
      name: (json['char_name'] ?? '').toString(),
      rarity: (json['rarity'] ?? '').toString(),
      weaponType: (json['weapon_type'] ?? '').toString(),
      portraitUrl: (json['portrait'] ?? '').toString(),
      role: (json['role'] ?? '').toString(),
      elementIconUrl: (json['element'] ?? '').toString(),
      weaponIconUrl: (json['weapon'] ?? '').toString(),
    );
  }
}

class TekkenCharacter {
  final String name;
  final String imageUrl;
  final String? categoryImageUrl;

  TekkenCharacter({
    required this.name,
    required this.imageUrl,
    this.categoryImageUrl,
  });

  factory TekkenCharacter.fromJson(Map<String, dynamic> json) {
    return TekkenCharacter(
      name: (json['name'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
      categoryImageUrl: json['category_image_url']?.toString(),
    );
  }
}
