// search_screen.dart
// このファイルは検索画面を提供します。
// 主に検索の入力、メインタブ（All、Genshin、Tekken）の切り替え、サブタブの切り替え（Timeline、Characterなど）、
// そしてフィルタリング機能（Genshinフィルター）などを管理しています。
// また、検索結果のリスト表示やエラーハンドリング、リフレッシュ機能も含まれています。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_first_app/screens/search/gw_search_controller.dart'; // GwSearchControllerのインポート
import 'package:my_first_app/screens/search/genshin_filter_summary_bar.dart'; // GenshinFilterSummaryBarのインポート
import 'package:my_first_app/screens/search/search_widgets.dart'; // SearchWidgetのインポート
import 'package:my_first_app/screens/search/search_genshin_characters.dart'; // Genshin Charactersのインポート
import 'package:my_first_app/screens/search/tekken_characters_screen.dart'; // Tekken Charactersのインポート
import 'package:my_first_app/screens/search/search_repository.dart'; // SearchRepositoryのインポート
import 'package:my_first_app/screens/search/search_models.dart'; // SearchModelのインポート
import 'package:my_first_app/screens/search/genshin_filter_controller.dart'; // GenshinFilterControllerのインポート（ある場合）

// サブタブ（Timeline、Back、Character）の定義
enum _SubTab { timeline, back, character }

/// SearchScreen：検索とタブの管理
// メインタブ（All、Genshin、Tekken）の切り替えや検索クエリの処理を行う画面のウィジェット
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final GwSearchController _c; // GwSearchControllerのインスタンス（検索機能の状態管理）
  final _textController = TextEditingController(); // 検索バーのコントローラー

  // メインタブ（All、Genshin、Tekken）を管理
  YourSearchTabClass _tab = YourSearchTabClass.all; // 初期メインタブ
  _SubTab _subTab = _SubTab.timeline; // 初期サブタブ（タイムライン）

  // Genshinフィルター用のコントローラーをProviderから取得
  late GenshinFilterController _gf;

  @override
  void initState() {
    super.initState();
    _c = GwSearchController()..boot(); // GwSearchControllerの初期化
    _gf = Provider.of<GenshinFilterController>(
      context,
      listen: false,
    ); // GenshinFilterControllerの取得
  }

  @override
  void dispose() {
    _textController.dispose(); // テキストコントローラーの破棄
    _c.disposeController(); // GwSearchControllerの破棄
    _c.dispose(); // GwSearchControllerのdisposeを呼び出す
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 複数のリスナーを統合（検索状態、テキスト入力、フィルタ）
    final listen = Listenable.merge([_c, _textController, _gf]);

    return AnimatedBuilder(
      animation: listen,
      builder: (context, _) {
        final s = _c.state; // 現在の検索状態
        final showSub = s.tab != YourSearchTabClass.all; // サブタブが表示されるかどうか
        final effectiveTab = showSub
            ? _subTab
            : _SubTab.timeline; // サブタブとメインタブのロジック

        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                // タイムラインタブのリフレッシュ
                if (effectiveTab == _SubTab.timeline) {
                  await _c.refresh();
                }
              },
              child: NestedScrollView(
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverAppBar(
                    pinned: true,
                    automaticallyImplyLeading: false,
                    toolbarHeight: 0,
                    collapsedHeight: _headerHeight(s, showSub, effectiveTab),
                    expandedHeight: _headerHeight(s, showSub, effectiveTab),
                    flexibleSpace: Container(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextField(
                            controller: _textController, // 検索バーの設定
                            onChanged: (v) {
                              // クエリが変更されたとき、検索を更新
                              if (effectiveTab == _SubTab.timeline) {
                                _c.setQuery(v);
                              }
                            },
                            decoration: InputDecoration(
                              prefixIcon: const Icon(Icons.search),
                              hintText: 'Search',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              isDense: true,
                              suffixIcon: _textController.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        _textController.clear();
                                        if (effectiveTab == _SubTab.timeline) {
                                          _c.clearQuery(); // クエリをクリア
                                        }
                                      },
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (!showSub) ...[
                            // メインタブの選択（All、Genshin、Tekken）
                            SegmentedButton<YourSearchTabClass>(
                              segments: const [
                                ButtonSegment(
                                  value: YourSearchTabClass.all,
                                  label: Text('All'),
                                ),
                                ButtonSegment(
                                  value: YourSearchTabClass.genshin,
                                  label: Text('Genshin'),
                                ),
                                ButtonSegment(
                                  value: YourSearchTabClass.tekken,
                                  label: Text('Tekken'),
                                ),
                              ],
                              selected: {s.tab},
                              onSelectionChanged: (set) {
                                final v = set.first;
                                setState(() => _tab = v); // メインタブの切り替え
                                _textController.clear();
                                _c.clearQuery();
                                _c.switchTab(v);
                                _gf.clear(); // Genshinフィルターのクリア
                              },
                            ),
                          ] else ...[
                            // サブタブの選択（Back、Timeline、Character）
                            SegmentedButton<_SubTab>(
                              segments: const [
                                ButtonSegment(
                                  value: _SubTab.back,
                                  label: Text('Back'),
                                ),
                                ButtonSegment(
                                  value: _SubTab.timeline,
                                  label: Text('Timeline'),
                                ),
                                ButtonSegment(
                                  value: _SubTab.character,
                                  label: Text('Character'),
                                ),
                              ],
                              selected: {_subTab},
                              onSelectionChanged: (set) {
                                final v = set.first;
                                if (v == _SubTab.back) {
                                  // サブタブがBackの場合はメインタブに戻る
                                  setState(() {
                                    _subTab = _SubTab.timeline;
                                    _c.switchTab(YourSearchTabClass.all);
                                  });
                                  _textController.clear();
                                  _c.clearQuery();
                                  _gf.clear();
                                  return;
                                }
                                setState(() => _subTab = v);
                                if (v == _SubTab.timeline) {
                                  _c.setQuery(_textController.text);
                                }
                              },
                            ),
                          ],
                          if (_subTab == _SubTab.character &&
                              s.tab == YourSearchTabClass.genshin)
                            GenshinFilterSummaryBar(
                              c: _gf,
                              onOpen: () => _openGenshinFiltersSheet(context),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                body: _buildBody(context, s, _subTab), // 検索結果表示の構築
              ),
            ),
          ),
        );
      },
    );
  }

  // Genshinフィルターフィルターシートを開くメソッド
  void _openGenshinFiltersSheet(BuildContext context) {
    final c = _gf;
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Filters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(onPressed: c.clear, child: const Text('Clear')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  child: GenshinIconFiltersBar(c: c), // Genshinのアイコンフィルター
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ヘッダーの高さを計算するメソッド
  double _headerHeight(SearchState s, bool showSub, _SubTab sub) {
    double h = 10 + 56 + 8 + 40;
    if (sub == _SubTab.character && s.tab == YourSearchTabClass.genshin) {
      h += 44;
    }
    return h;
  }

  // 検索結果の本体を構築するメソッド
  Widget _buildBody(BuildContext context, SearchState s, _SubTab sub) {
    if (sub == _SubTab.timeline) {
      if (s.loading && s.allItems.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (s.error != null && s.allItems.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(child: Text(s.error!)),
            const SizedBox(height: 12),
            Center(
              child: FilledButton(
                onPressed: _c.boot,
                child: const Text('Retry'),
              ),
            ),
          ],
        );
      }
      return YourSearchGridClass(
        items: s.viewItems, // 検索結果のアイテムリスト
        loading: s.loading && s.allItems.isNotEmpty,
        onTapItem: (item) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('tap: ${item.name}')));
        },
      );
    }

    if (s.tab == YourSearchTabClass.genshin) {
      return GenshinCharactersBody(
        nameQuery: _textController.text,
        rarities: _gf.rarities,
        elements: _gf.elements,
        weapons: _gf.weapons,
        sort: GenshinSortMode.name,
      );
    }

    if (s.tab == YourSearchTabClass.tekken) {
      return TekkenCharactersBody(); // Tekkenキャラクターの表示
    }

    return const Center(child: Text('Select Genshin/Tekken'));
  }
}
