import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

class GenshinCharactersBody extends StatefulWidget {
  const GenshinCharactersBody({
    super.key,
    required this.nameQuery,
    required this.rarities,
    required this.elements,
    required this.weapons,
    this.onTapCharacter,
  });

  final String nameQuery;
  final Set<int> rarities;
  final Set<int> elements; // 1..7
  final Set<int> weapons; // 1..5
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
    if (res.statusCode != 200) throw Exception('API error: ${res.statusCode}');

    final data = jsonDecode(res.body);
    final list = (data is List) ? data : (data['items'] as List? ?? []);

    final raw = list.map((e) => GenshinCharLite.fromJson(e)).toList();

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

    final out = byName.values.toList();
    out.sort((a, b) => a.charName.compareTo(b.charName));
    return out;
  }

  Future<void> _refresh() async {
    setState(() {
      _cache = null;
      _future = _cache ??= _fetch();
    });
    await _future;
  }

  List<GenshinCharLite> _applyFilters(List<GenshinCharLite> all) {
    final q = widget.nameQuery.trim().toLowerCase();

    return all.where((c) {
      if (widget.rarities.isNotEmpty && !widget.rarities.contains(c.rarity))
        return false;
      if (widget.elements.isNotEmpty && !widget.elements.contains(c.elementId))
        return false;
      if (widget.weapons.isNotEmpty && !widget.weapons.contains(c.weaponId))
        return false;
      if (q.isNotEmpty && !c.charName.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
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
          final view = _applyFilters(all);

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

class GenshinCharLite {
  final int id;
  final String charName;
  final int rarity;
  final int elementId;
  final int weaponId;

  final String? portraitUrl;
  final String? elementIconUrl;

  const GenshinCharLite({
    required this.id,
    required this.charName,
    required this.rarity,
    required this.elementId,
    required this.weaponId,
    required this.portraitUrl,
    required this.elementIconUrl,
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

  static String? _safeUrl(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
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
      (m['portrait'] ?? m['icon'] ?? m['thumb'] ?? m['image'])?.toString(),
    );
    final elementIcon = _safeUrl(m['element']?.toString());
    final elementId = _elementIdFrom(m['element']);
    final weaponId = _weaponIdFrom(
      m['weapon'],
      weaponType: m['weapon_type']?.toString(),
    );

    return GenshinCharLite(
      id: id,
      charName: charName,
      rarity: rarity,
      elementId: elementId,
      weaponId: weaponId,
      portraitUrl: portrait,
      elementIconUrl: elementIcon,
    );
  }
}

class _CharTile extends StatelessWidget {
  const _CharTile({required this.c, required this.onTap});
  final GenshinCharLite c;
  final VoidCallback? onTap;

  Color _rarityBorder(ColorScheme cs) {
    if (c.rarity >= 5) return cs.tertiary;
    if (c.rarity == 4) return cs.primary;
    return cs.outline;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final portrait = (c.portraitUrl ?? '').trim();
    final eIcon = (c.elementIconUrl ?? '').trim();

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _rarityBorder(cs), width: 1.4),
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
                  if (portrait.isEmpty)
                    Container(
                      color: cs.surfaceVariant,
                      child: Icon(Icons.person, color: cs.onSurfaceVariant),
                    )
                  else
                    CachedNetworkImage(
                      imageUrl: portrait,
                      fit: BoxFit.cover,
                      memCacheWidth: 320,
                      placeholder: (_, __) =>
                          Container(color: cs.surfaceVariant),
                      errorWidget: (_, __, ___) => Container(
                        color: cs.surfaceVariant,
                        child: Icon(
                          Icons.broken_image,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (eIcon.isNotEmpty)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: CachedNetworkImage(
                          imageUrl: eIcon,
                          fit: BoxFit.contain,
                          memCacheWidth: 64,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
}
