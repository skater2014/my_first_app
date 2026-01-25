import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:my_first_app/service/wp_api_service.dart';
import 'package:my_first_app/model/character.dart';
import 'package:my_first_app/screens/genshin_character_detail_screen.dart';

/// ============================================================
/// GenshinCharacterListScreen
/// - 原神キャラ一覧（Grid）
/// - フィルター（Element / Rarity / Weapon）
/// - 🔄リセットボタン（ALL|ALL|ALL|🔄）
/// - 無限スクロール（ページ分割をユーザーに見せない）
/// - フィルターで件数が少なくなりスクロールできない → 自動で次ページも取りにいく
/// - JP記事（slug/permalink に -jp 含む）を一覧から除外（ENだけ表示）
/// ============================================================
class GenshinCharacterListScreen extends StatefulWidget {
  const GenshinCharacterListScreen({super.key});

  @override
  State<GenshinCharacterListScreen> createState() =>
      _GenshinCharacterListScreenState();
}

class _GenshinCharacterListScreenState
    extends State<GenshinCharacterListScreen> {
  // ------------------------------------------------------------
  // API / Scroll
  // ------------------------------------------------------------
  final _api = WpApiService();
  final _scroll = ScrollController();

  // ------------------------------------------------------------
  // Pagination（無限スクロール用）
  // ------------------------------------------------------------
  static const int _perPage = 100; // 1回で取る数（将来増えても無限スクロールで吸収）
  int _page = 1; // 次に取りに行くページ番号
  bool _loading = false; // 初回ロード中
  bool _loadingMore = false; // 追加ロード中
  bool _hasMore = true; // まだ続きがあるか

  // ------------------------------------------------------------
  // Data（これに全部ためる）
  // ------------------------------------------------------------
  final List<GenshinCharacter> _all = [];

  // ------------------------------------------------------------
  // Filters（UIの状態）
  // ------------------------------------------------------------
  String _selectedElement = 'All';
  String _selectedRarity = 'All';
  String _selectedWeapon = 'All';

  @override
  void initState() {
    super.initState();

    // 初回ロード
    _loadFirstPage();

    // スクロール末尾付近で次ページ読み込み
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
        _loadMoreIfNeeded();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ==========================================================
  // A) 初回ロード（1ページ目から取り直す）
  // - pull-to-refresh でも使う
  // - フィルターリセットボタンでも使う
  // ==========================================================
  Future<void> _loadFirstPage() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _page = 1;
      _hasMore = true;
      _all.clear();
    });

    // ✅ ここに入れる（追加直後）
    debugPrint(
      'FIRST: ALL len=${_all.length}, '
      'uniqueById=${_all.map((e) => e.id).toSet().length}, '
      'uniqueByName=${_all.map((e) => e.name.toLowerCase()).toSet().length}',
    );

    try {
      final chunk = await _api.fetchGenshinCharacters(
        perPage: _perPage,
        page: 1,
      );

      if (!mounted) return;
      setState(() {
        _all.addAll(chunk);
        _hasMore = chunk.length >= _perPage;
        _page = 2; // 次は2ページ目
      });

      // フィルター結果が少なくてスクロールできない場合の保険
      await _ensureEnoughForFilter();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================================================
  // B) 追加ロード（次ページ）
  // ==========================================================
  Future<void> _loadMoreIfNeeded() async {
    if (_loadingMore || _loading || !_hasMore) return;

    setState(() => _loadingMore = true);

    try {
      final chunk = await _api.fetchGenshinCharacters(
        perPage: _perPage,
        page: _page,
      );

      if (!mounted) return;
      setState(() {
        _all.addAll(chunk);
        if (chunk.length < _perPage) _hasMore = false;
        _page += 1;
      });
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ==========================================================
  // C) フィルター適用後、件数が少なすぎるなら自動で追加ロード
  // - 「該当が少なくてスクロールできない」問題を潰す
  // ==========================================================
  Future<void> _ensureEnoughForFilter() async {
    const int wantAtLeast = 24; // グリッド2〜3行分くらい（適当でOK）

    while (mounted) {
      final filtered = _applyFilter(_all);
      if (filtered.length >= wantAtLeast) return; // もう十分
      if (!_hasMore) return; // これ以上ない
      if (_loadingMore || _loading) return; // 読み込み中なら待つ
      await _loadMoreIfNeeded();
    }
  }

  // ==========================================================
  // D) フィルター全リセット + データ更新（🔄ボタン用）
  // ==========================================================
  Future<void> _resetAllFiltersAndRefresh() async {
    setState(() {
      _selectedElement = 'All';
      _selectedRarity = 'All';
      _selectedWeapon = 'All';
    });
    await _loadFirstPage();
  }

  // ==========================================================
  // E) 詳細へ（IDで遷移）
  // - slug が EN/JP で混ざっても、ID遷移なら詰まりにくい
  // ==========================================================
  void _openDetail(BuildContext context, GenshinCharacter c) {
    if (c.id <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('詳細ページのIDが取得できませんでした')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GenshinCharacterDetailScreen(
          character: c,
          base: 'wp/v2/my-genshin-builds', // ✅ キャラ詳細CPT
        ),
      ),
    );
  }

  // ==========================================================
  // F) フィルター本体
  // - JP除外（ENのみ） → c.isJp を使う
  // ==========================================================
  List<GenshinCharacter> _applyFilter(List<GenshinCharacter> src) {
    return src
        .where((c) => !c.isJp) // ✅ JP除外（ENだけ）
        .where((c) {
          final matchesElement =
              _selectedElement == 'All' || c.elementType == _selectedElement;
          final matchesRarity =
              _selectedRarity == 'All' || c.rarity == _selectedRarity;
          final matchesWeapon =
              _selectedWeapon == 'All' || c.weaponType == _selectedWeapon;
          return matchesElement && matchesRarity && matchesWeapon;
        })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // 初回ロード中の表示
    if (_loading && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // ------------------------------------------------------------
    // ドロップダウン用アイコンURLを「今ある分だけ」自動収集
    // - 最初の100件に無い要素は、追加ロードされるまで出ない（仕様でOK）
    // ------------------------------------------------------------
    final elementIconByType = <String, String>{};
    final weaponIconByType = <String, String>{};

    for (final c in _all) {
      final et = c.elementType;
      if (et.isNotEmpty && c.elementIconUrl.isNotEmpty) {
        elementIconByType.putIfAbsent(et, () => c.elementIconUrl);
      }

      final wt = c.weaponType;
      if (wt.isNotEmpty && c.weaponIconUrl.isNotEmpty) {
        weaponIconByType.putIfAbsent(wt, () => c.weaponIconUrl);
      }
    }

    // 表示対象（JP除外 + フィルター済み）
    final filtered = _applyFilter(_all);

    return Column(
      children: [
        // ======================================================
        // 1) フィルター行（ALL|ALL|ALL|🔄）
        // ======================================================
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            // Wrap = 画面幅が狭いと勝手に折り返してくれる
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                _IconDropdown(
                  value: _selectedElement,
                  items: ['All', ...elementIconByType.keys.toList()..sort()],
                  iconUrlOf: (v) => elementIconByType[v] ?? '',
                  onChanged: (v) async {
                    setState(() => _selectedElement = v ?? 'All');
                    await _ensureEnoughForFilter(); // ✅ 足りなければ自動追加ロード
                  },
                ),

                _IconDropdown(
                  value: _selectedRarity,
                  items: const ['All', '4', '5'],
                  iconUrlOf: (_) => '',
                  onChanged: (v) async {
                    setState(() => _selectedRarity = v ?? 'All');
                    await _ensureEnoughForFilter();
                  },
                ),

                _IconDropdown(
                  value: _selectedWeapon,
                  items: ['All', ...weaponIconByType.keys.toList()..sort()],
                  iconUrlOf: (v) => weaponIconByType[v] ?? '',
                  onChanged: (v) async {
                    setState(() => _selectedWeapon = v ?? 'All');
                    await _ensureEnoughForFilter();
                  },
                ),

                // ✅ リフレッシュ（ドロップダウンの外に置く）
                IconButton(
                  tooltip: 'Reset filters',
                  onPressed: _resetAllFiltersAndRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),

        // ======================================================
        // 2) グリッド（無限スクロール + Pull to refresh）
        // ======================================================
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadFirstPage, // 引っ張って更新も可能
            child: GridView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.78,
              ),

              // +1 は末尾にローダー枠を入れるため
              itemCount: filtered.length + 1,
              itemBuilder: (context, index) {
                // 末尾ローダー表示
                if (index == filtered.length) {
                  if (!_hasMore) return const SizedBox.shrink();
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _loadingMore
                          ? const CircularProgressIndicator()
                          : const SizedBox.shrink(),
                    ),
                  );
                }

                final c = filtered[index];

                // ✅ これを追加（rarityBg 未定義を潰す）
                final rarityBg = c.rarityBgUrl;

                final elementIcon = c.elementIconUrl.trim();
                final weaponIcon = c.weaponIconUrl.trim();

                return InkWell(
                  onTap: () => _openDetail(context, c),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        // ✅ rarity背景（画像）
                        Positioned.fill(
                          child: CachedNetworkImage(
                            imageUrl: rarityBg,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: Colors.black12),
                            errorWidget: (_, __, ___) =>
                                Container(color: Colors.black12),
                          ),
                        ),

                        // ✅ rarityグラデ（上に重ねる）
                        Positioned.fill(
                          child: IgnorePointer(
                            // ←タップ邪魔しない保険
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: c.rarityGradientColors,
                                  stops: c.rarityGradientStops,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // キャラ画像
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 28),
                            child: CachedNetworkImage(
                              imageUrl: c.portraitUrl,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),

                        // 右上：element / weapon
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Column(
                            children: [
                              if (elementIcon.isNotEmpty)
                                _TopRightIcon(url: elementIcon),
                              if (elementIcon.isNotEmpty &&
                                  weaponIcon.isNotEmpty)
                                const SizedBox(height: 4),
                              if (weaponIcon.isNotEmpty)
                                _TopRightIcon(url: weaponIcon),
                            ],
                          ),
                        ),

                        // 下：名前バー
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            color: Colors.black.withOpacity(0.55),
                            child: Text(
                              c.name,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// ============================================================
/// 右上アイコン（Element / Weapon）
/// ============================================================
class _TopRightIcon extends StatelessWidget {
  final String url;
  const _TopRightIcon({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    if (u.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 22,
        height: 22,
        color: Colors.black.withOpacity(0.35),
        padding: const EdgeInsets.all(2),
        child: CachedNetworkImage(
          imageUrl: u,
          fit: BoxFit.contain,
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => const Icon(Icons.help_outline, size: 16),
        ),
      ),
    );
  }
}

/// ============================================================
/// ドロップダウン（画像つき）
/// - Element / Weapon のアイコン表示に使う
/// ============================================================
class _IconDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final String Function(String) iconUrlOf;
  final ValueChanged<String?> onChanged;

  const _IconDropdown({
    required this.value,
    required this.items,
    required this.iconUrlOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      onChanged: onChanged,
      items: items.map((v) {
        final icon = iconUrlOf(v);
        return DropdownMenuItem(
          value: v,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: CachedNetworkImage(
                    imageUrl: icon,
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) =>
                        const SizedBox(width: 18, height: 18),
                  ),
                ),
              Text(v),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// ============================================================
/// GenshinCharacter の「言語判定」ヘルパー
///
/// ✅ なぜ必要？
/// - WordPress 側で同じキャラが EN/JP 2記事ある（重複表示になる）
/// - JP記事の slug が 2パターン存在する
///    1) 「-jp」が付く（例: genshin-impact-sucrose-build-jp）
///    2) 日本語slugが URLエンコードされる（例: %e5%8e%9f%e7%a5%9e-...）
/// - どちらも確実に検出しないと「JP除外」が効かない
///
/// ✅ これでできること
/// - c.isJp で JP記事を判定して除外できる
/// - c.isEn で EN記事を優先するロジックが書ける
/// ============================================================
extension GenshinCharacterLang on GenshinCharacter {
  /// ------------------------------------------------------------
  /// slug が URLエンコードされている場合に decode して文字列として判定する
  ///
  /// 例:
  /// - raw:  "%e5%8e%9f%e7%a5%9e-sayu-%e6%9c%80%e5%bc%b7..."
  /// - decoded: "原神-sayu-最強..."
  ///
  /// decode に失敗してもアプリが落ちないように try/catch で保護。
  /// ------------------------------------------------------------
  String get _decodedSlug {
    final s = resolvedSlug.trim();
    if (s.isEmpty) return '';
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      // decode失敗（壊れたURLなど）でも判定処理を続けられるよう、そのまま返す
      return s;
    }
  }

  /// ------------------------------------------------------------
  /// ✅ JP判定
  ///
  /// JP記事の slug が次のどれかに当てはまれば JP とみなす：
  /// 1) "-jp" が含まれる
  ///    例: genshin-impact-sucrose-build-jp
  ///
  /// 2) "%e" が含まれる（URLエンコードされた日本語slugの典型パターン）
  ///    例: %e5%8e%9f%e7%a5%9e-lynette-%e6%9c%80...
  ///
  /// 3) decode後の slug に日本語文字（ひらがな/カタカナ/漢字）が含まれる
  ///    - 3040-30FF: ひらがな・カタカナ
  ///    - 3400-9FFF: 漢字の範囲（CJK）
  ///
  /// ※ 2) が無くても 3) で拾えるが、2) があると速い＆確実なので残している。
  /// ------------------------------------------------------------
  bool get isJp {
    final s = resolvedSlug.toLowerCase();

    // 1) -jp を含むならJP
    if (s.contains('-jp')) return true;

    // 2) URLエンコードされた日本語slugの典型（%e...）ならJP
    if (s.contains('%e')) return true;

    // 3) decode後に日本語が含まれるならJP
    final d = _decodedSlug;
    return RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(d);
  }

  /// ------------------------------------------------------------
  /// ✅ EN判定（EN優先ロジック用）
  ///
  /// EN記事は次のどれかに当てはまることが多い：
  /// - "-en" を含む
  ///   例: genshin-impact-sayu-build-en
  /// - "genshin-impact-" で始まる（あなたの英語slug規則）
  ///
  /// ※ 将来 slug規則が変わるなら、ここだけ修正すれば全体が追従できる。
  /// ------------------------------------------------------------
  bool get isEn {
    final s = resolvedSlug.toLowerCase();
    return s.contains('-en') || s.startsWith('genshin-impact-');
  }
}
