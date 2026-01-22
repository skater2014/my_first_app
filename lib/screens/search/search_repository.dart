import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../constants.dart'; // wpV2BaseUrl（WordPress APIのベースURL）

class TaxonomyResult {
  final int genshinCategoryId;
  final int tekkenCategoryId;
  final Map<String, int> rarityTagId;
  final Map<String, int> elementTagId;
  final Map<String, int> weaponTagId;

  const TaxonomyResult({
    required this.genshinCategoryId,
    required this.tekkenCategoryId,
    required this.rarityTagId,
    required this.elementTagId,
    required this.weaponTagId,
  });
}

class SearchRepository {
  final List<String> bases = const [
    'posts',
    'genshin_updated',
    'genshin_updated_jp',
    'artifacts',
    'gu',
  ];

  Future<int> _resolveCategoryIdBySlug(String slug) async {
    final uri = Uri.parse(
      '$wpV2BaseUrl/categories',
    ).replace(queryParameters: {'slug': slug, 'per_page': '1'});
    final res = await http.get(uri);

    if (res.statusCode != 200) return 0;
    final decoded = jsonDecode(res.body);
    if (decoded is! List || decoded.isEmpty) return 0;
    final first = decoded.first;
    if (first is Map && first['id'] != null) {
      final v = first['id'];
      return v is int ? v : int.tryParse('$v') ?? 0;
    }
    return 0;
  }

  Future<TaxonomyResult> resolveTaxonomy({
    required String genshinCategorySlug,
    required String tekkenCategorySlug,
  }) async {
    final gi = await _resolveCategoryIdBySlug(genshinCategorySlug);
    final tk = await _resolveCategoryIdBySlug(tekkenCategorySlug);

    return TaxonomyResult(
      genshinCategoryId: gi,
      tekkenCategoryId: tk,
      rarityTagId: const {},
      elementTagId: const {},
      weaponTagId: const {},
    );
  }

  Future<List<dynamic>> _fetchAllPagesRaw({
    required String base,
    int perPage = 50,
    int maxPages = 10,
  }) async {
    final out = <dynamic>[];

    for (var page = 1; page <= maxPages; page++) {
      final uri = Uri.parse('$wpV2BaseUrl/$base').replace(
        queryParameters: {
          'per_page': '$perPage',
          'page': '$page',
          '_embed': '1',
          '_fields':
              'id,title,link,date,categories,tags,meta,featured_media,_links,_embedded',
        },
      );

      final res = await http.get(uri);

      if (res.statusCode == 404) return out;
      if (res.statusCode != 200) return out;

      final decoded = jsonDecode(res.body);
      if (decoded is! List || decoded.isEmpty) return out;

      out.addAll(decoded);
      if (decoded.length < perPage) return out;
    }
    return out;
  }

  Future<List<SearchItem>> loadAllPosts() async {
    final all = <SearchItem>[];

    for (final base in bases) {
      final raw = await _fetchAllPagesRaw(base: base);
      for (final e in raw) {
        all.add(SearchItem.fromWpPostJson(e, base: base));
      }
    }

    final seen = <String>{};
    final unique = <SearchItem>[];
    for (final x in all) {
      final k = '${x.base}:${x.id}';
      if (seen.add(k)) unique.add(x);
    }

    unique.sort((a, b) => b.date.compareTo(a.date));
    return unique;
  }
}
