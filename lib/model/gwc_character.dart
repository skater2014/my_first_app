// lib/model/gwc_character.dart
//
// ✅ GWCキャラの「データモデル」
// - APIのJSON(Map) → Dartのクラスに変換する（fromJson）
// - meta / data の中に本体が入ってるので必ず吸い上げる
// - null / 型違い / 空要素([""]など)に強くする

class GwcCharacter {
  // ----------------------------
  // ✅ 基本情報
  // ----------------------------
  final int id;
  final String title;
  final String slug;
  final String permalink;

  // ----------------------------
  // ✅ キャラ属性（meta想定）
  // ----------------------------
  final String charName;
  final String rarity;
  final String badge;

  // ----------------------------
  // ✅ 表示用（meta想定）
  // ----------------------------
  final String portrait;
  final String element;
  final String weapon;
  final String weaponType;
  final String role;

  // ----------------------------
  // ✅ 詳細（data想定）
  // ----------------------------
  final List<dynamic> materials;
  final List<dynamic> weaponsFull;
  final List<dynamic> artifacts;

  final Map<String, dynamic> stats;

  final List<dynamic> teams;
  final List<dynamic> passives;
  final List<dynamic> consts;
  final List<dynamic> talents;
  final List<dynamic> ascensionItems;

  final String ascensionHtml;
  final String youtubeId;

  const GwcCharacter({
    required this.id,
    required this.title,
    required this.slug,
    required this.permalink,
    required this.charName,
    required this.rarity,
    required this.badge,
    required this.portrait,
    required this.element,
    required this.weapon,
    required this.weaponType,
    required this.role,
    required this.materials,
    required this.weaponsFull,
    required this.artifacts,
    required this.stats,
    required this.teams,
    required this.passives,
    required this.consts,
    required this.talents,
    required this.ascensionItems,
    required this.ascensionHtml,
    required this.youtubeId,
  });

  factory GwcCharacter.fromJson(Map<String, dynamic> json) {
    // ✅ ルート / meta / data を取り出す（無ければ空）
    final meta = _toMap(json['meta']);
    final data = _toMap(json['data']);

    // ✅ 「どこからでも拾える」(優先: meta → data → root)
    dynamic pick3(String key) {
      if (meta.containsKey(key)) return meta[key];
      if (data.containsKey(key)) return data[key];
      return json[key];
    }

    // ✅ 互換キー（APIが揺れても耐える）
    dynamic pickAny(List<String> keys) {
      for (final k in keys) {
        final v = pick3(k);
        if (v != null) return v;
      }
      return null;
    }

    // ✅ リストは必ず「空文字/空Map/null」を除去してから使う
    List<dynamic> cleanList(dynamic v) => _cleanList(_toList(v));

    return GwcCharacter(
      // ---- 基本
      id: _toInt(pickAny(['id', 'ID'])),
      title: _toStr(pickAny(['title', 'post_title'])),
      slug: _toStr(pickAny(['slug', 'post_name'])),
      permalink: _toStr(pickAny(['permalink', 'link'])),

      // ---- meta
      charName: _toStr(pickAny(['char_name', 'charName'])),
      rarity: _toStr(pickAny(['rarity', 'star'])),
      badge: _toStr(pickAny(['badge', 'label'])),

      portrait: _toStr(pickAny(['portrait', 'image'])),
      element: _toStr(pickAny(['element', 'element_key'])),
      weapon: _toStr(pickAny(['weapon', 'weapon_name'])),
      weaponType: _toStr(pickAny(['weapon_type', 'weaponType'])),
      role: _toStr(pickAny(['role', 'position'])),

      // ---- data
      materials: cleanList(pickAny(['materials'])),
      weaponsFull: cleanList(pickAny(['weapons', 'weaponsFull'])),
      artifacts: cleanList(pickAny(['artifacts'])),

      stats: _toMap(pickAny(['stats', 'status'])),

      teams: cleanList(pickAny(['teams'])),
      passives: cleanList(pickAny(['passives'])),
      consts: cleanList(pickAny(['consts', 'constellations'])),
      talents: cleanList(pickAny(['talents'])),

      // asc_items は [""] が来るから、ここで必ず掃除する
      ascensionItems: cleanList(
        pickAny(['asc_items', 'ascension_items', 'ascensionItems']),
      ),

      ascensionHtml: _toStr(
        pickAny(['asc_html', 'ascension_html', 'ascensionHtml']),
      ),
      youtubeId: _toStr(pickAny(['youtube_id', 'youtubeId'])),
    );
  }

  @override
  String toString() {
    return 'GwcCharacter(id=$id, name=$charName, weaponType=$weaponType, rarity=$rarity)';
  }

  // ----------------------------
  // ✅ 安全変換
  // ----------------------------
  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static String _toStr(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }

  static List<dynamic> _toList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v;
    return const [];
  }

  static Map<String, dynamic> _toMap(dynamic v) {
    if (v == null) return const {};
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return const {};
  }

  // ✅ 【重要】[""] や null を消して “本当にあるデータだけ” にする
  static List<dynamic> _cleanList(List<dynamic> list) {
    return list.where((e) {
      if (e == null) return false;
      if (e is String) return e.trim().isNotEmpty; // ← teams:[""] 対策
      if (e is Map) return e.isNotEmpty;
      return true;
    }).toList();
  }
}
