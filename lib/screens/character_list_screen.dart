// lib/screens/character_list_screen.dart
//
// ✅ キャラ一覧画面（GWC API）
//
// - API: /wp-json/gwc/v1/characters
// - 一覧は “軽く” するため full=false / includeHtml=false 推奨
//
// ✅ 今回の目的（重要）
// ------------------------------------------------------------
// 1) EN/JA を混ぜて表示しない（重複を出さない）
// 2) Flutter側で slug を見て間引かない（不安定だから）
// 3) /characters?lang=en|ja を送ってWP側で分離させる
//
// → なので、この画面は「言語状態 _lang」を持ち、
//    fetchCharacters() に lang: _lang を渡すだけでOK。
// ------------------------------------------------------------
//
// できること：
// - 検索（debounce付き）
// - フィルタ（元素 / 武器 / レア）
// - ソート（name / rarity / updated）
// - 無限スクロール（末尾付近で次ページ）
//
// 使うもの：
// - lib/service/wp_api_service.dart の class GwcApi
// - lib/model/gwc_character.dart の class GwcCharacter
// - constants.dart（wpBaseUrl / AppLang がある前提）

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../constants.dart';
import '../model/gwc_character.dart';
import '../service/wp_api_service.dart';
import 'character_detail_screen.dart';

class CharacterListScreen extends StatefulWidget {
  const CharacterListScreen({super.key});

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen> {
  // ==========================================================
  // ✅ APIクライアント
  // ==========================================================
  late final GwcApi _api;

  // ==========================================================
  // ✅ 一覧状態（ページング）
  // ==========================================================
  final List<GwcCharacter> _items = [];
  int _page = 1;
  final int _perPage = 20;

  bool _isLoading = false;
  bool _hasMore = true; // 0件になったら false

  // ==========================================================
  // ✅ UI入力（検索/フィルタ/ソート/言語）
  // ==========================================================
  final TextEditingController _searchCtl = TextEditingController();
  Timer? _debounce;

  // ✅ 追加：言語状態（ここが今回の肝）
  // EN/JA を切り替えたら _load(reset:true) を呼ぶ。
  AppLang _lang = AppLang.en;

  String? _filterElement; // 例: "hydro"
  String? _filterWeaponType; // 例: "sword"
  String? _filterRarity; // "4" or "5"

  String _sort = 'name'; // "name" | "rarity" | "updated"
  String _order = 'asc'; // "asc" | "desc"

  // ✅ 無限スクロール用
  final ScrollController _sc = ScrollController();

  @override
  void initState() {
    super.initState();

    // ✅ baseUrl はドメイン（例: https://gamewidth.net）が必要
    // wpBaseUrl が "https://.../wp-json/wp/v2" でも
    // ここでは scheme + host のみ抜くのでOK
    _api = GwcApi();

    // 初回ロード
    _load(reset: true);

    // 無限スクロール：末尾近くで次ページ
    _sc.addListener(() {
      if (_sc.position.pixels >= _sc.position.maxScrollExtent - 300) {
        _load(); // reset=false（追加読み込み）
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    _sc.dispose();
    super.dispose();
  }

  // ==========================================================
  // ✅ wpBaseUrl からドメインだけ抜く（例: https://gamewidth.net）
  // ==========================================================

  // ==========================================================
  // ✅ データ取得（reset=true で最初から取り直し）
  //
  // ★重要：
  // - EN/JA はここで lang: _lang を送って「サーバ側で分離」する。
  // - Flutter側で slug 判定などをして間引かない。
  // ==========================================================
  Future<void> _load({bool reset = false}) async {
    if (_isLoading) return;
    if (!reset && !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      if (reset) {
        _page = 1;
        _hasMore = true;
        _items.clear();
      }

      // ✅ 一覧は軽く（full/includeHtml は false）
      final list = await _api.fetchCharacters(
        page: _page,
        perPage: _perPage,
        full: false,
        includeHtml: false,

        // filters
        search: _searchCtl.text.trim().isEmpty ? null : _searchCtl.text.trim(),
        element: _filterElement,
        weaponType: _filterWeaponType,
        rarity: _filterRarity,

        // sort
        sort: _sort,
        order: _order,

        // ★今回の目的：言語指定を必ず送る（サーバ側でEN/JA分離）
        lang: _lang,
      );

      if (list.isEmpty) {
        _hasMore = false;
      } else {
        _items.addAll(list);
        _page += 1;
      }

      setState(() {});
    } catch (e) {
      // ✅ 初心者向け：エラーは画面に出す（原因が分かる）
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('読み込みエラー: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================================
  // ✅ 検索（debounce：入力停止してからAPIを叩く）
  // ==========================================================
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _load(reset: true);
    });
  }

  // ==========================================================
  // ✅ フィルタUI（ボトムシート）
  // ==========================================================
  Future<void> _openFilterSheet() async {
    String? element = _filterElement;
    String? weapon = _filterWeaponType;
    String? rarity = _filterRarity;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              Widget dd<T>({
                required String label,
                required T? value,
                required List<DropdownMenuItem<T>> items,
                required void Function(T?) onChanged,
              }) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<T>(
                      value: value,
                      items: items,
                      onChanged: onChanged,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'フィルタ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),

                  dd<String>(
                    label: '元素 (element)',
                    value: element,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('指定なし')),
                      DropdownMenuItem(value: 'pyro', child: Text('pyro')),
                      DropdownMenuItem(value: 'hydro', child: Text('hydro')),
                      DropdownMenuItem(value: 'anemo', child: Text('anemo')),
                      DropdownMenuItem(
                        value: 'electro',
                        child: Text('electro'),
                      ),
                      DropdownMenuItem(value: 'cryo', child: Text('cryo')),
                      DropdownMenuItem(value: 'dendro', child: Text('dendro')),
                      DropdownMenuItem(value: 'geo', child: Text('geo')),
                    ],
                    onChanged: (v) => setModal(() => element = v),
                  ),

                  dd<String>(
                    label: '武器タイプ (weapon_type)',
                    value: weapon,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('指定なし')),
                      DropdownMenuItem(value: 'sword', child: Text('sword')),
                      DropdownMenuItem(
                        value: 'claymore',
                        child: Text('claymore'),
                      ),
                      DropdownMenuItem(
                        value: 'polearm',
                        child: Text('polearm'),
                      ),
                      DropdownMenuItem(value: 'bow', child: Text('bow')),
                      DropdownMenuItem(
                        value: 'catalyst',
                        child: Text('catalyst'),
                      ),
                    ],
                    onChanged: (v) => setModal(() => weapon = v),
                  ),

                  dd<String>(
                    label: 'レアリティ (rarity)',
                    value: rarity,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('指定なし')),
                      DropdownMenuItem(value: '4', child: Text('4')),
                      DropdownMenuItem(value: '5', child: Text('5')),
                    ],
                    onChanged: (v) => setModal(() => rarity = v),
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModal(() {
                              element = null;
                              weapon = null;
                              rarity = null;
                            });
                          },
                          child: const Text('クリア'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('適用'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (ok == true) {
      setState(() {
        _filterElement = element;
        _filterWeaponType = weapon;
        _filterRarity = rarity;
      });
      _load(reset: true);
    }
  }

  // ==========================================================
  // ✅ ソート変更
  // ==========================================================
  void _setSort(String sort, String order) {
    setState(() {
      _sort = sort;
      _order = order;
    });
    _load(reset: true);
  }

  // ==========================================================
  // ✅ 言語切替（EN / JA）
  //
  // - ここを押す → _lang が変わる → resetで取り直し
  // - これだけで “混在・重複” は出なくなる（サーバ側絞り込み）
  // ==========================================================
  void _setLang(AppLang lang) {
    if (_lang == lang) return;
    setState(() => _lang = lang);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 今の条件を見える化（初心者が迷わない）
    final cond = <String>[
      'lang=${_lang == AppLang.ja ? "ja" : "en"}',
      if (_searchCtl.text.trim().isNotEmpty)
        'search="${_searchCtl.text.trim()}"',
      if (_filterElement != null) 'element=$_filterElement',
      if (_filterWeaponType != null) 'weapon=$_filterWeaponType',
      if (_filterRarity != null) 'rarity=$_filterRarity',
      'sort=$_sort ($_order)',
    ].join(' / ');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _lang == AppLang.ja ? 'Characters (JA)' : 'Characters (EN)',
        ),
        actions: [
          // ✅ 言語切替（最短で入るUI）
          PopupMenuButton<AppLang>(
            tooltip: 'Language',
            onSelected: _setLang,
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppLang.en, child: Text('EN')),
              PopupMenuItem(value: AppLang.ja, child: Text('JA')),
            ],
            icon: const Icon(Icons.language),
          ),

          IconButton(
            tooltip: 'フィルタ',
            onPressed: _openFilterSheet,
            icon: const Icon(Icons.tune),
          ),

          PopupMenuButton<String>(
            tooltip: '並び替え',
            onSelected: (v) {
              final parts = v.split(':'); // 例: "name:asc"
              _setSort(parts[0], parts[1]);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'name:asc', child: Text('名前（昇順）')),
              PopupMenuItem(value: 'name:desc', child: Text('名前（降順）')),
              PopupMenuItem(value: 'rarity:desc', child: Text('レア（高い順）')),
              PopupMenuItem(value: 'rarity:asc', child: Text('レア（低い順）')),
              PopupMenuItem(value: 'updated:desc', child: Text('更新（新しい順）')),
              PopupMenuItem(value: 'updated:asc', child: Text('更新（古い順）')),
            ],
          ),
        ],
      ),

      body: Column(
        children: [
          // ✅ 検索バー
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search (例: ayaka)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchCtl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtl.clear();
                          _load(reset: true);
                        },
                      ),
              ),
            ),
          ),

          // ✅ 条件表示
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(cond, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),

          const Divider(height: 1),

          // ✅ 一覧
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView.builder(
                controller: _sc,
                itemCount: _items.length + 1,
                itemBuilder: (context, index) {
                  // 末尾：ローディング or 終端
                  if (index == _items.length) {
                    if (_isLoading) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (!_hasMore) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('これ以上ありません')),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final c = _items[index];

                  return ListTile(
                    leading: _Portrait(url: c.portrait),
                    title: Text(
                      c.charName.isNotEmpty ? c.charName : c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      [
                        if (c.element.isNotEmpty) c.element,
                        if (c.weaponType.isNotEmpty) c.weaponType,
                        if (c.rarity.isNotEmpty) '★${c.rarity}',
                        if (c.role.isNotEmpty) c.role,
                      ].join(' / '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      // ✅ タップで詳細へ（これが目的）
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CharacterDetailScreen(characterId: c.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ 画像が空でも落ちないポートレート表示
class _Portrait extends StatelessWidget {
  final String url;
  const _Portrait({required this.url});

  @override
  Widget build(BuildContext context) {
    const size = 44.0;

    if (url.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.person),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            Container(width: size, height: size, color: Colors.black12),
        errorWidget: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.black12,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
