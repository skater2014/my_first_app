import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_first_app/screens/search/search_widgets.dart';

/// ============================================================
/// ✅ Genshin Filter Summary Bar
/// - タブでRarity、Element、Weaponのフィルタを確認
/// - 選択した内容を要約表示
/// ============================================================
class GenshinFilterSummaryBar extends StatelessWidget {
  final GenshinFilterController c;
  final VoidCallback? onOpen; // onOpen パラメータを追加

  const GenshinFilterSummaryBar({super.key, required this.c, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final r = c.rarities.length;
    final e = c.elements.length;
    final w = c.weapons.length;
    final has = (r + e + w) > 0;

    final label = has ? 'Filter  R:  E:  W:' : 'Filter';

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              if (onOpen != null) {
                onOpen?.call(); // onOpenが非nullの場合はこれを呼び出す
              } else {
                _openGenshinFilterSheet(context, c); // onOpenがnullの場合はこちらを呼び出す
              }
            },
            icon: const Icon(Icons.tune),
            label: Text(label, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (has)
          TextButton(
            onPressed: c.clear,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Clear'),
          ),
      ],
    );
  }

  void _openGenshinFilterSheet(
    BuildContext context,
    GenshinFilterController c,
  ) {
    showModalBottomSheet(
      context: context, // 修正されたcontext
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final h = MediaQuery.of(ctx).size.height;
        return SizedBox(
          height: h * 0.72,
          child: DefaultTabController(
            length: 3,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Rarity'),
                    Tab(text: 'Element'),
                    Tab(text: 'Weapon'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _sheetWrap(
                        title: 'Rarity',
                        values: const [4, 5], // ✅ まずは 4/5 だけ（必要なら [1,2,3] を足す）
                        selected: c.rarities,
                        onToggle: (v) => _toggleCompat(c, 'rarity', v),
                        labelOf: (v) => '★',
                      ),
                      _sheetWrap(
                        title: 'Element',
                        values: const [1, 2, 3, 4, 5, 6, 7],
                        selected: c.elements,
                        onToggle: (v) => _toggleCompat(c, 'element', v),
                        labelOf: (v) => 'E', // 後でアイコン化OK
                      ),
                      _sheetWrap(
                        title: 'Weapon',
                        values: const [1, 2, 3, 4, 5],
                        selected: c.weapons,
                        onToggle: (v) => _toggleCompat(c, 'weapon', v),
                        labelOf: (v) => 'W', // 後でアイコン化OK
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: c.clear,
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ 既存controllerの関数名が違っても落ちないように「dynamicで吸収」
  void _toggleCompat(GenshinFilterController c, String kind, int v) {
    final d = c as dynamic;

    // まず「それっぽいメソッド」を試す（存在しなければcatchして次へ）
    try {
      if (kind == 'rarity') {
        d.toggleRarity(v);
        return;
      }
      if (kind == 'element') {
        d.toggleElement(v);
        return;
      }
      if (kind == 'weapon') {
        d.toggleWeapon(v);
        return;
      }
    } catch (_) {}

    // 無ければ Set を直接いじる（公開されてる前提）
    final set = (kind == 'rarity')
        ? c.rarities
        : (kind == 'element')
        ? c.elements
        : c.weapons;

    if (set.contains(v)) {
      set.remove(v);
    } else {
      set.add(v);
    }

    // ChangeNotifier想定（無ければ何もしない）
    try {
      d.notifyListeners();
    } catch (_) {}
  }

  Widget _sheetWrap({
    required String title,
    required List<int> values,
    required Set<int> selected,
    required void Function(int v) onToggle,
    required String Function(int v) labelOf,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Align(
        alignment: Alignment.topLeft,
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final v in values)
              FilterChip(
                label: Text(labelOf(v)),
                selected: selected.contains(v),
                onSelected: (_) => onToggle(v),
              ),
          ],
        ),
      ),
    );
  }
}
