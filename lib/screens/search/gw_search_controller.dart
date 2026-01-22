import 'package:flutter/foundation.dart';
import 'search_repository.dart';

class YourSearchTabClass {
  static const all = YourSearchTabClass._('all');
  static const genshin = YourSearchTabClass._('genshin');
  static const tekken = YourSearchTabClass._('tekken');

  final String name;

  const YourSearchTabClass._(this.name);
}

class SearchState {
  final bool loading;
  final String? error;
  final YourSearchTabClass tab;
  final String query;
  final bool taxonomyReady;
  final int genshinCategoryId;
  final int tekkenCategoryId;
  final Map<String, int> rarityTagId;
  final Map<String, int> elementTagId;
  final Map<String, int> weaponTagId;
  final Set<int> selRarityTags;
  final Set<int> selElementTags;
  final Set<int> selWeaponTags;
  final List<SearchItem> allItems;
  final List<SearchItem> viewItems;

  const SearchState({
    required this.loading,
    required this.error,
    required this.tab,
    required this.query,
    required this.taxonomyReady,
    required this.genshinCategoryId,
    required this.tekkenCategoryId,
    required this.rarityTagId,
    required this.elementTagId,
    required this.weaponTagId,
    required this.selRarityTags,
    required this.selElementTags,
    required this.selWeaponTags,
    required this.allItems,
    required this.viewItems,
  });

  factory SearchState.initial() => const SearchState(
    loading: false,
    error: null,
    tab: YourSearchTabClass.all,
    query: '',
    taxonomyReady: false,
    genshinCategoryId: 0,
    tekkenCategoryId: 0,
    rarityTagId: {},
    elementTagId: {},
    weaponTagId: {},
    selRarityTags: {},
    selElementTags: {},
    selWeaponTags: {},
    allItems: [],
    viewItems: [],
  );

  SearchState copyWith({
    bool? loading,
    String? error,
    YourSearchTabClass? tab,
    String? query,
    bool? taxonomyReady,
    int? genshinCategoryId,
    int? tekkenCategoryId,
    Map<String, int>? rarityTagId,
    Map<String, int>? elementTagId,
    Map<String, int>? weaponTagId,
    Set<int>? selRarityTags,
    Set<int>? selElementTags,
    Set<int>? selWeaponTags,
    List<SearchItem>? allItems,
    List<SearchItem>? viewItems,
  }) {
    return SearchState(
      loading: loading ?? this.loading,
      error: error,
      tab: tab ?? this.tab,
      query: query ?? this.query,
      taxonomyReady: taxonomyReady ?? this.taxonomyReady,
      genshinCategoryId: genshinCategoryId ?? this.genshinCategoryId,
      tekkenCategoryId: tekkenCategoryId ?? this.tekkenCategoryId,
      rarityTagId: rarityTagId ?? this.rarityTagId,
      elementTagId: elementTagId ?? this.elementTagId,
      weaponTagId: weaponTagId ?? this.weaponTagId,
      selRarityTags: selRarityTags ?? this.selRarityTags,
      selElementTags: selElementTags ?? this.selElementTags,
      selWeaponTags: selWeaponTags ?? this.selWeaponTags,
      allItems: allItems ?? this.allItems,
      viewItems: viewItems ?? this.viewItems,
    );
  }
}

class GwSearchController extends ChangeNotifier {
  final SearchRepository _repo;
  SearchState _s = SearchState.initial();
  int _token = 0;

  GwSearchController({SearchRepository? repo})
    : _repo = repo ?? SearchRepository();

  SearchState get state => _s;

  Future<void> boot() async {
    final token = ++_token;
    _set(_s.copyWith(loading: true, error: null, taxonomyReady: false));

    try {
      final tax = await _repo.resolveTaxonomy(
        genshinCategorySlug: 'genshin-impact',
        tekkenCategorySlug: 'tekken7',
      );

      if (token != _token) return;

      _set(
        _s.copyWith(
          taxonomyReady: true,
          genshinCategoryId: tax.genshinCategoryId,
          tekkenCategoryId: tax.tekkenCategoryId,
          rarityTagId: tax.rarityTagId,
          elementTagId: tax.elementTagId,
          weaponTagId: tax.weaponTagId,
        ),
      );

      final all = await _repo.loadAllPosts();
      if (token != _token) return;

      final sorted = [...all]..sort((a, b) => b.date.compareTo(a.date));
      _set(_s.copyWith(allItems: sorted));
      _applyView();
    } catch (e) {
      if (token != _token) return;
      _set(_s.copyWith(error: 'Boot failed: $e'));
    } finally {
      if (token != _token) return;
      _set(_s.copyWith(loading: false));
    }
  }

  void _set(SearchState next) {
    _s = next;
    notifyListeners();
  }

  void _applyView() {
    var out = [..._s.allItems];

    if (_s.tab == YourSearchTabClass.genshin) {
      final cat = _s.genshinCategoryId;
      if (cat != 0) {
        out = out
            .where((x) => x.categoryIds.contains(cat) || x.isGenshin)
            .toList();
      } else {
        out = out.where((x) => x.isGenshin).toList();
      }
    } else if (_s.tab == YourSearchTabClass.tekken) {
      final cat = _s.tekkenCategoryId;
      if (cat != 0) {
        out = out
            .where((x) => x.categoryIds.contains(cat) || x.isTekken)
            .toList();
      } else {
        out = out.where((x) => x.isTekken).toList();
      }
    }

    final q = _s.query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((x) => x.name.toLowerCase().contains(q)).toList();
    }

    if (_s.selRarityTags.isNotEmpty) {
      out = out.where((x) => x.tagIds.any(_s.selRarityTags.contains)).toList();
    }

    if (_s.selElementTags.isNotEmpty) {
      out = out.where((x) => x.tagIds.any(_s.selElementTags.contains)).toList();
    }

    if (_s.selWeaponTags.isNotEmpty) {
      out = out.where((x) => x.tagIds.any(_s.selWeaponTags.contains)).toList();
    }

    out.sort((a, b) => b.date.compareTo(a.date));
    _set(_s.copyWith(viewItems: out));
  }
}
