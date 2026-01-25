import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_settings.dart';

/// ============================================================
/// GwTopHeader（共通ヘッダー）
/// - ハンバーガー（Drawerを開く）
// --- 検索（AppSettings.searchQuery に反映）
/// - ダークモード、言語
///
/// ✅重要：TextEditingController を build で new しない
/// → buildのたびに初期化されると「カーソルが戻る」「逆方向入力」になる
/// ============================================================
class GwTopHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  const GwTopHeader({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();

    return AppBar(
      // ハンバーガー（Drawerを開く）
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => Scaffold.of(ctx).openDrawer(),
          tooltip: 'Menu',
        ),
      ),

      // タイトル or 検索欄
      title: s.searchOpen
          ? _SearchField(
              value: s.searchQuery,
              onChanged: (v) => context.read<AppSettings>().setSearchQuery(v),
              onClose: () => context.read<AppSettings>().closeSearch(),
            )
          : Text(title),

      actions: [
        // 検索バー開閉
        IconButton(
          icon: Icon(s.searchOpen ? Icons.close : Icons.search),
          onPressed: () => context.read<AppSettings>().toggleSearch(),
          tooltip: 'Search',
        ),

        // ダークモード
        IconButton(
          icon: Icon(s.themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
          onPressed: () {
            final on = s.themeMode != ThemeMode.dark;
            context.read<AppSettings>().toggleDark(on);
          },
          tooltip: 'Theme',
        ),

        // 言語
        DropdownButtonHideUnderline(
          child: DropdownButton<AppLang>(
            value: s.language,
            onChanged: (v) {
              if (v != null) context.read<AppSettings>().setLanguage(v);
            },
            items: const [
              DropdownMenuItem(value: AppLang.en, child: Text('🇺🇸 EN')),
              DropdownMenuItem(value: AppLang.jp, child: Text('🇯🇵 JP')),
            ],
          ),
        ),

        // SNS（仮）
        IconButton(icon: const Icon(Icons.share), onPressed: () {}, tooltip: 'SNS'),
      ],
    );
  }
}

/// ✅ ここが「逆方向」バグの修正ポイント
/// - controller を build のたびに作らない
/// - 外から value が変わった時だけ text を反映し、カーソルを末尾に維持
class _SearchField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _SearchField({required this.value, required this.onChanged, required this.onClose});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
    _c.selection = TextSelection.collapsed(offset: _c.text.length);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Provider側の値が変わった時だけ反映
    if (widget.value != oldWidget.value && widget.value != _c.text) {
      _c.text = widget.value;
      _c.selection = TextSelection.collapsed(offset: _c.text.length);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _c,
        autofocus: true,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: 'Search…',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(icon: const Icon(Icons.close), onPressed: widget.onClose),
        ),
      ),
    );
  }
}
