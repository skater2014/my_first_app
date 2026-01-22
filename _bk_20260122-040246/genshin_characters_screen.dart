import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

;

// ============================================================
// GameWidth theme icons (Genshin)
// ============================================================
const String _gwGenshinIconRoot =
    'https://gamewidth.net/wp-content/themes/Xiaoyu%20Tekken7/images/genshin/';

String? _iconUrlFromFile(String? filename) {
  if (filename == null || filename.trim().isEmpty) return null;
  final url = '$_gwGenshinIconRoot$filename';
  // スペース等の事故を減らす
  return Uri.encodeFull(url);
}

const Map<int, String> _rarityIconFile = {5: 'rarity_5.png', 4: 'rarity_4.png'};

const Map<int, String> _rarityBgFile = {5: '5_sm.png', 4: '4_sm.png'};

const Map<int, String> _elementIconFile = {
  1: 'element_anemo.png',
  2: 'element_cryo.png',
  3: 'element_electro.png',
  4: 'element_dendro.png',
  5: 'element_geo.png',
  6: 'element_hydro.png',
  7: 'element_pyro.png',
};

/// weaponId: 1..5（あなたの定義）
/// 1: Bow, 2: Catalyst, 3: Claymore, 4: Polearm, 5: Sword
const Map<int, String> _weaponIconFile = {
  1: 'weapon_bow.png',
  2: 'weapon_catalyst.png',
  3: 'weapon_claymore.png',
  4: 'weapon_polearm.png',
  5: 'weapon_sword.png',
};

String? _rarityIconUrl(int rarity) => _iconUrlFromFile(_rarityIconFile[rarity]);
String? _rarityBgUrl(int rarity) => _iconUrlFromFile(_rarityBgFile[rarity]);
String? _elementIconUrl(int elementId) =>
    _iconUrlFromFile(_elementIconFile[elementId]);
String? _weaponIconUrl(int weaponId) =>
    _iconUrlFromFile(_weaponIconFile[weaponId]);

// ============================================================
// Screen
// ============================================================
enum _SortMode { name, rarityDesc, elementThenName, weaponThenName }

class GenshinCharactersScreen extends StatefulWidget {
  const GenshinCharactersScreen({super.key});

  @override
  State<GenshinCharactersScreen> createState() =>
      _GenshinCharactersScreenState();
}

class _GenshinCharactersScreenState extends State<GenshinCharactersScreen> {
  final Set<int> _rarities = {};
  final Set<int> _elements = {};
  final Set<int> _weapons = {};
  String _nameQuery = '';
  _SortMode _sort = _SortMode.name;

  void _clear() {
    setState(() {
      _rarities.clear();
      _elements.clear();
      _weapons.clear();
      _nameQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAny =
        _rarities.isNotEmpty ||
        _elements.isNotEmpty ||
        _weapons.isNotEmpty ||
        _nameQuery.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Genshin'),
        actions: [
          PopupMenuButton<_SortMode>(
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _SortMode.name,
                child: Text('Sort: Name (A→Z)'),
              ),
              PopupMenuItem(
                value: _SortMode.rarityDesc,
                child: Text('Sort: Rarity (5→4)'),
              ),
              PopupMenuItem(
                value: _SortMode.elementThenName,
                child: Text('Sort: Element → Name'),
              ),
              PopupMenuItem(
                value: _SortMode.weaponThenName,
                child: Text('Sort: Weapon → Name'),
              ),
            ],
            icon: const Icon(Icons.sort),
          ),
          if (hasAny)
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.filter_alt_off),
            ),
        ],
      ),
      body: GenshinCharactersBody(
        nameQuery: _nameQuery,
        rarities: _rarities,
        elements: _elements,
        weapons: _weapons,
        sort: _sort,
        onTapCharacter: (c) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('tap: ${c.charName}')));
        },
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: TextField(
          onChanged: (v) => setState(() => _nameQuery = v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Filter by name',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// ✅ SearchScreen からも呼べる “Scaffold無しBody”
// ============================================================
class GenshinCharactersBody extends StatefulWidget {
  const GenshinCharactersBody({
    super.key,
    required this.nameQuery,
    required this.rarities,
    required this.elements,
    required this.weapons,
    required this.sort,
    this.onTapCharacter,
  });

  final String nameQuery;
  final Set<int> rarities; // 5/4
  final Set<int> elements; // 1..7
  final Set<int> weapons; // 1..5
  final _SortMode sort;
  final void Function(GenshinCharLite c)? onTapCharacter;

  @override
  State<GenshinCharactersBody> createState() => _GenshinCharactersBodyState();
}

class _GenshinCharactersBodyState extends State<GenshinCharactersBody> {
  static const String _endpoint =
      'https://gamewidth.net/wp-json/gwc/v1/characters?lang=ja&full=false';

  static Future<List<GenshinCharLite>>? _cache;
  late Future<List<GenshinCharLite>> _future;

  @override
  void initState() {
    super.initState();
    _future = _cache ??= _fetch();
  }

  Future<List<GenshinCharLite>> _fetch() async {
    final res = await http.get(Uri.parse(_endpoint));
    if (res.statusCode != 200) {
      throw Exception('API error: ${res.statusCode}');
    }

    final data = jsonDecode(res.body);
    final list = (data is List) ? data : (data['items'] as List? ?? []);

    final raw = list.map((e) => GenshinCharLite.fromJson(e)).toList();

    // 同名は1つに（JP優先）
    final byName = <String, GenshinCharLite>{};
    for (final c in raw) {
      final key = c.charName.trim().toLowerCase();
      final prev = byName[key];
      if (prev == null) {
        byName[key] = c;
        continue;
      }
      final prevJp = prev.isLikelyJp;
      final curJp = c.isLikelyJp;
      if (!prevJp && curJp) byName[key] = c;
    }

    return byName.values.toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _cache = null;
      _future = _cache ??= _fetch();
    });
    await _future;
  }

  List<GenshinCharLite> _applyFiltersAndSort(List<GenshinCharLite> all) {
    final q = widget.nameQuery.trim().toLowerCase();

    final filtered = all.where((c) {
      if (widget.rarities.isNotEmpty && !widget.rarities.contains(c.rarity)) {
        return false;
      }
      if (widget.elements.isNotEmpty &&
          !widget.elements.contains(c.elementId)) {
        return false;
      }
      if (widget.weapons.isNotEmpty && !widget.weapons.contains(c.weaponId)) {
        return false;
      }
      if (q.isNotEmpty && !c.charName.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    int cmpStr(String a, String b) => a.compareTo(b);
    int cmpInt(int a, int b) => a.compareTo(b);

    switch (widget.sort) {
      case _SortMode.name:
        filtered.sort((a, b) => cmpStr(a.charName, b.charName));
        break;
      case _SortMode.rarityDesc:
        filtered.sort((a, b) {
          final r = (b.rarity).compareTo(a.rarity);
          if (r != 0) return r;
          return cmpStr(a.charName, b.charName);
        });
        break;
      case _SortMode.elementThenName:
        filtered.sort((a, b) {
          final e = cmpInt(a.elementId, b.elementId);
          if (e != 0) return e;
          return cmpStr(a.charName, b.charName);
        });
        break;
      case _SortMode.weaponThenName:
        filtered.sort((a, b) {
          final w = cmpInt(a.weaponId, b.weaponId);
          if (w != 0) return w;
          return cmpStr(a.charName, b.charName);
        });
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<GenshinCharLite>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(child: Text('Error: ${snap.error}')),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ),
              ],
            );
          }

          final all = snap.data ?? const <GenshinCharLite>[];
          final view = _applyFiltersAndSort(all);

          if (view.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No characters')),
              ],
            );
          }

          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.90,
            ),
            itemCount: view.length,
            itemBuilder: (context, i) {
              final c = view[i];
              return _CharTile(
                c: c,
                onTap: () => widget.onTapCharacter?.call(c),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================
// Model
// ============================================================
class GenshinCharLite {
  final int id;
  final String charName;
  final int rarity; // 5/4
  final int elementId; // 1..7
  final int weaponId; // 1..5

  final String? portraitUrl;
  final String? elementIconUrl; // APIからURLで来る場合もある
  final String? slug;

  const GenshinCharLite({
    required this.id,
    required this.charName,
    required this.rarity,
    required this.elementId,
    required this.weaponId,
    required this.portraitUrl,
    required this.elementIconUrl,
    required this.slug,
  });

  bool get isLikelyJp {
    final s = (slug ?? '').toLowerCase();
    if (s.contains('-jp')) return true;
    if (s.contains('%e')) return true;
    return false;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _toStr(dynamic v) => (v == null) ? '' : v.toString();

  static String? _safeUrl(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final fixed = gwFixMediaUrl(s) ?? s;
    return Uri.encodeFull(fixed);
  }

  static int _elementIdFrom(dynamic v) {
    final s = _toStr(v).toLowerCase();
    if (s.contains('anemo')) return 1;
    if (s.contains('cryo')) return 2;
    if (s.contains('electro')) return 3;
    if (s.contains('dendro')) return 4;
    if (s.contains('geo')) return 5;
    if (s.contains('hydro')) return 6;
    if (s.contains('pyro')) return 7;
    final n = int.tryParse(s);
    return n ?? 0;
  }

  static int _weaponIdFrom(dynamic v, {String? weaponType}) {
    final s0 = _toStr(v).toLowerCase();
    final s = (weaponType ?? s0).toLowerCase();

    if (s.contains('bow')) return 1;
    if (s.contains('catalyst')) return 2;
    if (s.contains('claymore')) return 3;
    if (s.contains('polearm') || s.contains('spear')) return 4;
    if (s.contains('sword')) return 5;

    if (s0.contains('weapon_bow')) return 1;
    if (s0.contains('weapon_catalyst')) return 2;
    if (s0.contains('weapon_claymore')) return 3;
    if (s0.contains('weapon_polearm')) return 4;
    if (s0.contains('weapon_sword')) return 5;

    return 0;
  }

  factory GenshinCharLite.fromJson(dynamic json) {
    final m = (json is Map<String, dynamic>) ? json : <String, dynamic>{};

    final id = _toInt(m['id']);

    final charName = _toStr(m['char_name'] ?? m['name'] ?? m['title']);
    final rarity = _toInt(m['rarity']);

    final portrait = _safeUrl(
      m['portrait'] ?? m['icon'] ?? m['thumb'] ?? m['image'],
    );

    // element: 文字列/URL/数字が混在
    final elementRaw = m['element'];
    final elementId = _elementIdFrom(elementRaw);

    // APIが elementの「アイコンURL」を返す場合だけ拾う（拾えなければUI側で theme icon を使う）
    final elementIcon = _safeUrl(m['element_icon'] ?? elementRaw);

    // weapon: URL / weapon_type
    final weaponId = _weaponIdFrom(
      m['weapon'],
      weaponType: m['weapon_type']?.toString(),
    );

    final slug = m['slug']?.toString();

    return GenshinCharLite(
      id: id,
      charName: charName,
      rarity: rarity,
      elementId: elementId,
      weaponId: weaponId,
      portraitUrl: portrait,
      elementIconUrl: elementIcon,
      slug: slug,
    );
  }
}

// ============================================================
// Tile UI (rarity background + icons)
// ============================================================
class _CharTile extends StatelessWidget {
  const _CharTile({required this.c, required this.onTap});
  final GenshinCharLite c;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final portrait = (c.portraitUrl ?? '').trim();

    // ✅ Webと同じ “レア背景”
    final bg = _rarityBgUrl(c.rarity);

    // ✅ 右上：元素（APIのURLがあればそれを優先、無ければテーマ画像）
    final elementIcon = (c.elementIconUrl ?? '').trim().isNotEmpty
        ? c.elementIconUrl
        : _elementIconUrl(c.elementId);

    // ✅ 右下：武器（テーマ画像）
    final weaponIcon = _weaponIconUrl(c.weaponId);

    // ✅ 左上：レア（テーマ画像）
    final rarityIcon = _rarityIconUrl(c.rarity);

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // ✅ 背景（5_sm / 4_sm）
                  if (bg != null)
                    Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: bg,
                        fit: BoxFit.cover, // 好みで contain に変更OK
                        memCacheWidth: 512,
                        placeholder: (_, __) =>
                            Container(color: cs.surfaceContainerHighest),
                        errorWidget: (_, __, ___) =>
                            Container(color: cs.surfaceContainerHighest),
                      ),
                    )
                  else
                    Positioned.fill(child: Container(color: cs.surfaceContainerHighest)),

                  // ✅ ポートレート（背景の上）
                  if (portrait.isEmpty)
                    Positioned.fill(
                      child: Center(
                        child: Icon(Icons.person, color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: portrait,
                        fit: BoxFit.cover,
                        memCacheWidth: 320,
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),

                  // ✅ 左上：レア
                  if (rarityIcon != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _badgeIcon(rarityIcon, size: 20),
                    ),

                  // ✅ 右上：元素
                  if (elementIcon != null)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: _badgeIcon(elementIcon, size: 20),
                    ),

                  // ✅ 右下：武器
                  if (weaponIcon != null)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _badgeIcon(weaponIcon, size: 20),
                    ),
                ],
              ),
            ),

            // name
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
              child: Text(
                c.charName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeIcon(String url, {required double size}) {
    return Container(
      width: size + 6,
      height: size + 6,
      decoration: BoxDecoration(
        color: Colors.black.withValues()(0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.all(3),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        memCacheWidth: 96,
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
