import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart'; // キャッシュされたネットワーク画像のためのインポート
import 'package:my_first_app/screens/utils/gw_url.dart'; // URLユーティリティ
import 'package:my_first_app/screens/utils/gw_youtube.dart'; // YouTubeユーティリティ
import 'package:my_first_app/screens/widgets/gw_youtube_player.dart'; // YouTubeプレーヤーウィジェット
import 'package:my_first_app/screens/search/gw_search_controller.dart'; // GwSearchControllerのインポート

// ============================================================
// ✅ Web(HTML) の filters-list を Flutter で再現するための定義
// ============================================================
const String _gwGenshinIconRoot =
    'https://gamewidth.net/wp-content/themes/Xiaoyu%20Tekken7/images/genshin/';

String _gwIconUrl(String file) => Uri.encodeFull('$_gwGenshinIconRoot$file');

class _FilterDef {
  const _FilterDef({
    required this.id,
    required this.name, // HTML data-filter/alt 相当
    required this.iconFile,
  });
  final int id; // アプリ内部用（Set<int>で管理）
  final String name; // 表示/tooltip 用（HTMLと一致）
  final String iconFile;
}

const List<_FilterDef> _rarityDefs = [
  _FilterDef(id: 4, name: '4', iconFile: 'rarity_4.png'),
  _FilterDef(id: 5, name: '5', iconFile: 'rarity_5.png'),
];

const List<_FilterDef> _elementDefs = [
  _FilterDef(id: 1, name: 'Anemo', iconFile: 'element_anemo.png'),
  _FilterDef(id: 2, name: 'Cryo', iconFile: 'element_cryo.png'),
  _FilterDef(id: 3, name: 'Electro', iconFile: 'element_electro.png'),
  _FilterDef(id: 4, name: 'Dendro', iconFile: 'element_dendro.png'),
  _FilterDef(id: 5, name: 'Geo', iconFile: 'element_geo.png'),
  _FilterDef(id: 6, name: 'Hydro', iconFile: 'element_hydro.png'),
  _FilterDef(id: 7, name: 'Pyro', iconFile: 'element_pyro.png'),
];

const List<_FilterDef> _weaponDefs = [
  _FilterDef(id: 1, name: 'Bow', iconFile: 'weapon_bow.png'),
  _FilterDef(id: 2, name: 'Catalyst', iconFile: 'weapon_catalyst.png'),
  _FilterDef(id: 3, name: 'Claymore', iconFile: 'weapon_claymore.png'),
  _FilterDef(id: 4, name: 'Polearm', iconFile: 'weapon_polearm.png'),
  _FilterDef(id: 5, name: 'Sword', iconFile: 'weapon_sword.png'),
];

// ============================================================
// ✅ フィルター状態は SearchScreen ではなく “ここ” が管理
// ============================================================
class GenshinFilterController extends ChangeNotifier {
  final Set<int> rarities = {};
  final Set<int> elements = {};
  final Set<int> weapons = {};

  bool get hasAny =>
      rarities.isNotEmpty || elements.isNotEmpty || weapons.isNotEmpty;

  void clear() {
    rarities.clear();
    elements.clear();
    weapons.clear();
    notifyListeners();
  }

  void toggleRarity(int v) {
    rarities.contains(v) ? rarities.remove(v) : rarities.add(v);
    notifyListeners();
  }

  void toggleElement(int v) {
    elements.contains(v) ? elements.remove(v) : elements.add(v);
    notifyListeners();
  }

  void toggleWeapon(int v) {
    weapons.contains(v) ? weapons.remove(v) : weapons.add(v);
    notifyListeners();
  }
}

// ============================================================
// ✅ Webの <div class="filters-list"> を Flutter で再現
// ============================================================
class GenshinIconFiltersBar extends StatelessWidget {
  const GenshinIconFiltersBar({super.key, required this.c});

  final GenshinFilterController c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.hasAny)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: c.clear,
                    child: const Text('Clear'),
                  ),
                ),

              _group(
                title: 'Rarity',
                defs: _rarityDefs,
                selected: c.rarities,
                onTap: c.toggleRarity,
                cs: cs,
              ),
              const SizedBox(height: 8),

              _group(
                title: 'Element',
                defs: _elementDefs,
                selected: c.elements,
                onTap: c.toggleElement,
                cs: cs,
              ),
              const SizedBox(height: 8),

              _group(
                title: 'Weapon',
                defs: _weaponDefs,
                selected: c.weapons,
                onTap: c.toggleWeapon,
                cs: cs,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _group({
    required String title,
    required List<_FilterDef> defs,
    required Set<int> selected,
    required void Function(int) onTap,
    required ColorScheme cs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final d in defs)
              Tooltip(
                message: d.name, // HTML alt と一致
                child: InkWell(
                  onTap: () => onTap(d.id),
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        width: 2,
                        color: selected.contains(d.id)
                            ? Colors.blueAccent
                            : Colors.transparent,
                      ),
                      color: selected.contains(d.id)
                          ? cs.primaryContainer.withValues()(0.25)
                          : cs.surfaceContainerHighest.withValues()(0.20),
                    ),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CachedNetworkImage(
                        imageUrl: _gwIconUrl(d.iconFile),
                        fit: BoxFit.contain,
                        memCacheWidth: 96,
                        placeholder: (_, __) => const SizedBox.shrink(),
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 18),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
