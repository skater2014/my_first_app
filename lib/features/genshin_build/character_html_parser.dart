// lib/features/genshin_build/character_html_parser.dart
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import 'models.dart';

String _t(dom.Element? e) => (e?.text ?? '').trim();
String _attr(dom.Element? e, String key) => (e?.attributes[key] ?? '').trim();

String _imgSrc(dom.Element? img) {
  final s = _attr(img, 'src');
  if (s.isNotEmpty) return s;
  final ds = _attr(img, 'data-src');
  return ds;
}

dom.Element? _findSectionByTitleContains(dom.Document doc, String keyword) {
  for (final s in doc.querySelectorAll('.character-build-section')) {
    final title = _t(s.querySelector('.character-build-section-title'));
    if (title.toLowerCase().contains(keyword.toLowerCase())) return s;
  }
  return null;
}

List<RankedData> _parseRankedList(dom.Element section) {
  final out = <RankedData>[];

  for (final w in section.querySelectorAll('.character-build-weapon')) {
    final rankStr = _t(w.querySelector('.character-build-weapon-rank'));
    final rank = int.tryParse(rankStr) ?? 0;

    final icon = _imgSrc(w.querySelector('img'));
    final nm = _t(w.querySelector('.character-build-weapon-name'));

    final countStr = _t(w.querySelector('.character-build-weapon-count'));
    final count = int.tryParse(countStr);

    if (rank > 0 && nm.isNotEmpty) {
      out.add(RankedData(rank: rank, name: nm, iconUrl: icon, count: count));
    }
  }
  return out;
}

CharacterPageData parseCharacterHtml(String html) {
  final doc = html_parser.parse(html);

  final name = _t(doc.querySelector('.character-name'));
  final portraitUrl = _imgSrc(doc.querySelector('.character-portrait'));

  final pills = <PillData>[];
  for (final p in doc.querySelectorAll('.character-data-wrapper .character-pill')) {
    final spanText = _t(p.querySelector('span'));
    final text = spanText.isNotEmpty ? spanText : _t(p);
    final icon = _imgSrc(p.querySelector('img'));
    if (text.isNotEmpty) pills.add(PillData(text: text, iconUrl: icon));
  }

  final materials = <IconNameData>[];
  for (final item in doc.querySelectorAll('.character-materials-item')) {
    final icon = _imgSrc(item.querySelector('img'));
    final nm = _t(item.querySelector('.character-materials-name'));
    if (nm.isNotEmpty) materials.add(IconNameData(name: nm, iconUrl: icon));
  }

  final weaponsSection = _findSectionByTitleContains(doc, 'Best Weapons');
  final artifactsSection = _findSectionByTitleContains(doc, 'Best Artifacts');

  final bestWeapons = weaponsSection != null ? _parseRankedList(weaponsSection) : <RankedData>[];
  final bestArtifacts = artifactsSection != null ? _parseRankedList(artifactsSection) : <RankedData>[];

  final bestStatsLines = doc
      .querySelectorAll('.character-stats .character-stats-item')
      .map((e) => _t(e).replaceAll(RegExp(r'\s+'), ' '))
      .where((s) => s.isNotEmpty)
      .toList();

  // ✅ Ascension table
  AscensionTableData? ascension;
  final rt = doc.querySelector('#ascension .ReactTable');
  if (rt != null) {
    final headers = rt
        .querySelectorAll('.rt-thead.-header .rt-th div')
        .map((e) => _t(e))
        .where((s) => s.isNotEmpty)
        .toList();

    final rows = <List<AscensionCell>>[];
    for (final tr in rt.querySelectorAll('.rt-tbody .rt-tr-group .rt-tr')) {
      final cells = <AscensionCell>[];

      for (final td in tr.querySelectorAll('.rt-td')) {
        final imgEl = td.querySelector('.table-image-wrapper img');
        final countEl = td.querySelector('.table-image-wrapper .table-image-count');

        final imgUrl = _imgSrc(imgEl);
        final cnt = int.tryParse(_t(countEl));

        final text = _t(td).replaceAll(RegExp(r'\s+'), ' ');
        cells.add(
          AscensionCell(
            text: text,
            image: imgUrl.isEmpty ? null : TableImage(url: imgUrl, count: cnt),
          ),
        );
      }

      if (cells.isNotEmpty) rows.add(cells);
    }

    if (headers.isNotEmpty && rows.isNotEmpty) {
      ascension = AscensionTableData(headers: headers, rows: rows);
    }
  }

  // ✅ Talents / Passives / Constellations
  final groups = <SkillGroupData>[];
  for (final g in doc.querySelectorAll('.character-skills')) {
    final id = (g.attributes['id'] ?? '').trim();
    final title = _t(g.querySelector('.character-category'));

    final items = <SkillItemData>[];
    for (final s in g.querySelectorAll('.character-skill')) {
      final icon = _imgSrc(s.querySelector('.character-skill-icon'));
      final t = _t(s.querySelector('.character-skill-title'));
      final nm = _t(s.querySelector('.character-skill-name'));
      final desc = _t(s.querySelector('.character-skill-description'))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // ほぼ空のものは弾く
      if ((t + nm + desc).trim().isEmpty) continue;

      items.add(SkillItemData(
        title: t,
        name: nm,
        iconUrl: icon,
        description: desc,
      ));
    }

    if (items.isNotEmpty) {
      groups.add(SkillGroupData(id: id, title: title, items: items));
    }
  }

  return CharacterPageData(
    showcaseVideoId: _extractShowcaseVideoId(doc),
    name: name,
    portraitUrl: portraitUrl,
    pills: pills,
    materials: materials,
    bestWeapons: bestWeapons,
    bestArtifacts: bestArtifacts,
    bestStatsLines: bestStatsLines,
    ascension: ascension,
    skillGroups: groups,
  );
}

String _extractShowcaseVideoId(dynamic doc) {
  try {
    final lite = doc.querySelector('lite-youtube');
    final v = (lite?.attributes['videoid'] ?? '').toString().trim();
    if (v.isNotEmpty) return v;

    final iframe = doc.querySelector('iframe[src*="youtube"]');
    final src = (iframe?.attributes['src'] ?? '').toString();
    final m1 = RegExp(r'/embed/([A-Za-z0-9_-]{6,})').firstMatch(src);
    if (m1 != null) return (m1.group(1) ?? '').trim();

    final m2 = RegExp(r'[?&]v=([A-Za-z0-9_-]{6,})').firstMatch(src);
    if (m2 != null) return (m2.group(1) ?? '').trim();
  } catch (_) {}
  return '';
}
