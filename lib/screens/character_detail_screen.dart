// lib/screens/character_detail_screen.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_html/flutter_html.dart';

import '../widgets/gw_youtube_player.dart';

import '../constants.dart';
import '../model/gwc_character.dart';
import '../service/wp_api_service.dart';

class CharacterDetailScreen extends StatefulWidget {
  final int characterId;
  final AppLang lang;

  const CharacterDetailScreen({
    super.key,
    required this.characterId,
    this.lang = AppLang.en,
  });

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  late final GwcApi _api;

  bool _loading = true;
  String? _error;
  GwcCharacter? _char;

  final _kTop = GlobalKey();
  final _kWeapons = GlobalKey();
  final _kArtifacts = GlobalKey();
  final _kMaterials = GlobalKey();
  final _kTeams = GlobalKey();
  final _kAscension = GlobalKey();

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _api = GwcApi();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final c = await _api.fetchCharacterById(
        widget.characterId,
        full: true,
        includeHtml: true,
        lang: widget.lang,
      );

      if (!mounted) return;
      setState(() => _char = c);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _jumpTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (_char?.charName.isNotEmpty == true)
        ? _char!.charName
        : 'Character';

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null)
            ? _errorView()
            : (_char == null)
            ? const Center(child: Text('No data'))
            : _body(_char!),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Failed: $_error'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _body(GwcCharacter c) {
    final videoId = _youtubeIdOrEmpty(c.youtubeId);
    final hasYoutube = videoId.isNotEmpty;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Container(key: _kTop),
        _header(c),
        const SizedBox(height: 12),

        if (hasYoutube) ...[
          // ✅ 画面側は GwYoutubePlayer だけ。controllerは一切持たない。
          GwYoutubePlayer(videoId: videoId),
          const SizedBox(height: 12),
        ],

        _tabs(c),
        const SizedBox(height: 12),
        const Divider(),

        _sectionAnchor(_kWeapons, 'Weapons (${c.weaponsFull.length})'),
        _listCards(c.weaponsFull),
        const SizedBox(height: 16),

        _sectionAnchor(_kArtifacts, 'Artifacts (${c.artifacts.length})'),
        _listCards(c.artifacts),
        const SizedBox(height: 16),

        _sectionAnchor(_kMaterials, 'Materials (${c.materials.length})'),
        _listCards(c.materials),
        const SizedBox(height: 16),

        _sectionAnchor(_kTeams, 'Teams (${c.teams.length})'),
        if (c.teams.isEmpty)
          const Text('No teams yet.')
        else
          _listCards(c.teams),
        const SizedBox(height: 16),

        _sectionAnchor(_kAscension, 'Ascension'),
        if (c.ascensionHtml.trim().isEmpty)
          const Text('No ascension html.')
        else
          _AscensionView(fragmentHtml: c.ascensionHtml),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionAnchor(GlobalKey key, String title) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _tabs(GwcCharacter c) {
    final tabs = <({String label, GlobalKey key})>[
      (label: 'Top', key: _kTop),
      (label: 'Weapons (${c.weaponsFull.length})', key: _kWeapons),
      (label: 'Artifacts (${c.artifacts.length})', key: _kArtifacts),
      (label: 'Materials (${c.materials.length})', key: _kMaterials),
      (label: 'Teams (${c.teams.length})', key: _kTeams),
      (label: 'Ascension', key: _kAscension),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs
            .map(
              (t) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(t.label),
                  onPressed: () => _jumpTo(t.key),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _header(GwcCharacter c) {
    final elementLabel = _deriveElementKey(c.element);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _portrait(c.portrait),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.charName.isNotEmpty ? c.charName : c.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (elementLabel.isNotEmpty) Chip(label: Text(elementLabel)),
                  if (c.weaponType.isNotEmpty) Chip(label: Text(c.weaponType)),
                  if (c.rarity.isNotEmpty) Chip(label: Text('★${c.rarity}')),
                  if (c.role.isNotEmpty) Chip(label: Text(c.role)),
                ],
              ),
              if (c.badge.isNotEmpty) ...[
                const SizedBox(height: 8),
                Chip(label: Text(c.badge)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _listCards(List<dynamic> items) {
    if (items.isEmpty) return const Text('—');
    return Column(children: items.map((it) => _itemCard(it)).toList());
  }

  Widget _itemCard(dynamic it) {
    if (it is Map) {
      final m = it.cast<String, dynamic>();
      final name = (m['name'] ?? m['title'] ?? '').toString();
      final icon = (m['icon'] ?? m['image'] ?? '').toString();
      final subtitle = (m['subtitle'] ?? '').toString();
      final desc = (m['desc'] ?? m['description'] ?? '').toString();

      final rank = m['rank']?.toString();
      final count = m['count']?.toString();
      final rarity = m['rarity']?.toString();

      final meta = <String>[
        if (rank != null && rank.isNotEmpty) 'rank:$rank',
        if (count != null && count.isNotEmpty) 'count:$count',
        if (rarity != null && rarity.isNotEmpty) 'rarity:$rarity',
      ].join(' / ');

      return Card(
        child: ListTile(
          leading: _smallIcon(icon),
          title: Text(
            subtitle.isNotEmpty
                ? '$subtitle  $name'
                : (name.isNotEmpty ? name : '—'),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (meta.isNotEmpty) Text(meta),
                if (desc.isNotEmpty) ...[const SizedBox(height: 6), Text(desc)],
              ],
            ),
          ),
        ),
      );
    }

    final s = it.toString().trim();
    if (s.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(padding: const EdgeInsets.all(12), child: Text(s)),
    );
  }

  Widget _smallIcon(String url) {
    if (url.trim().isEmpty) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Icon(Icons.image_not_supported_outlined),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }

  String _youtubeIdOrEmpty(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';

    final idLike = RegExp(r'^[A-Za-z0-9_-]{11}$');
    if (idLike.hasMatch(t)) return t;

    final m1 = RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})').firstMatch(t);
    if (m1 != null) return m1.group(1) ?? '';

    final m2 = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})').firstMatch(t);
    if (m2 != null) return m2.group(1) ?? '';

    final m3 = RegExp(r'youtube\.com/embed/([A-Za-z0-9_-]{11})').firstMatch(t);
    if (m3 != null) return m3.group(1) ?? '';

    return t;
  }

  String _deriveElementKey(String elementValue) {
    final v = elementValue.trim();
    if (v.isEmpty) return '';

    if (v.startsWith('http')) {
      final lower = v.toLowerCase();
      const keys = [
        'anemo',
        'pyro',
        'hydro',
        'electro',
        'cryo',
        'dendro',
        'geo',
      ];
      for (final k in keys) {
        if (lower.contains(k)) return k;
      }
      return 'element';
    }

    return v;
  }

  Widget _portrait(String url) {
    const size = 72.0;

    if (url.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.person),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Colors.black12,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _AscensionView extends StatelessWidget {
  final String fragmentHtml;
  const _AscensionView({required this.fragmentHtml});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Html(data: fragmentHtml),
        ),
      );
    }
    return _AscensionWebView(fragmentHtml: fragmentHtml);
  }
}

class _AscensionWebView extends StatefulWidget {
  final String fragmentHtml;
  const _AscensionWebView({required this.fragmentHtml});

  @override
  State<_AscensionWebView> createState() => _AscensionWebViewState();
}

class _AscensionWebViewState extends State<_AscensionWebView> {
  late final WebViewController _c;

  @override
  void initState() {
    super.initState();

    _c = WebViewController()..setJavaScriptMode(JavaScriptMode.disabled);

    final html =
        '''
<!doctype html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body { margin: 0; padding: 12px; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #ffffff; color: #111; }
  .character-category { margin: 0 0 12px; font-size: 18px; }
  .rt-table { border: 1px solid #e5e7eb; border-radius: 12px; overflow: hidden; }
  .rt-thead { background: #f3f4f6; font-weight: 600; }
  .rt-tr { display: flex; border-bottom: 1px solid #e5e7eb; }
  .rt-th, .rt-td { padding: 10px; box-sizing: border-box; font-size: 13px; }
  .rt-td { background: #fff; }
  .rt-tr.-odd .rt-td { background: #ffffff; }
  .rt-tr.-even .rt-td { background: #fafafa; }
  .table-image-wrapper { display: inline-flex; align-items: center; gap: 8px; margin-right: 8px; }
  .table-image { width: 34px; height: 34px; object-fit: cover; border-radius: 8px; background: #f3f4f6; }
  .table-image-count { font-size: 12px; color: #111; background: #e5e7eb; padding: 2px 6px; border-radius: 999px; }
  .ReactTable, .rt-table { overflow-x: auto; -webkit-overflow-scrolling: touch; }
</style>
</head>
<body>
${widget.fragmentHtml}
</body>
</html>
''';

    _c.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 520,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: WebViewWidget(controller: _c),
      ),
    );
  }
}
