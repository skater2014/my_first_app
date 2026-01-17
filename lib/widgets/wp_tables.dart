// lib/widgets/wp_tables.dart
// WordPress本文から抜き出した <table> を “ネイティブ風カードテーブル” で描画

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

// ============================================================
// Public Widget
// ============================================================
class WpTablesView extends StatelessWidget {
  final String tableHtml;
  const WpTablesView({super.key, required this.tableHtml});

  @override
  Widget build(BuildContext context) {
    final dom.DocumentFragment frag = html_parser.parseFragment(tableHtml);
    final dom.Element? tableEl = frag.querySelector('table');
    if (tableEl == null) return const SizedBox.shrink();

    final _TableData data = _parseTableAndTransform(tableEl);
    if (data.headers.isEmpty || data.rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return _WpTableWidget(data: data);
  }

  // ============================================================
  // Parse + Transform
  // - header role guess
  // - Element列 -> Characterセルへ統合（バッジ）＆列削除
  // ============================================================
  static _TableData _parseTableAndTransform(dom.Element tableEl) {
    final trs = tableEl.querySelectorAll('tr');
    if (trs.isEmpty) {
      return const _TableData(headers: [], rows: [], roles: []);
    }

    // ✅ 1行目が <th> を持つならヘッダー行、そうでなければデータ行として扱う
    final firstHasTh = trs.first.querySelectorAll('th').isNotEmpty;

    List<String> headers = [];
    int startRowIndex = 0;

    if (firstHasTh) {
      // header
      final ths = trs.first.querySelectorAll('th');
      headers = ths.map((e) => e.text.replaceAll('\n', ' ').trim()).toList();
      startRowIndex = 1;
    }

    int maxCols = headers.length;
    final rawRows = <List<_CellData>>[];

    // rows（ヘッダーが無い場合は 0 行目から）
    for (int i = startRowIndex; i < trs.length; i++) {
      final cells = trs[i].querySelectorAll('th,td');
      if (cells.isEmpty) continue;

      final row = <_CellData>[];
      for (final cell in cells) {
        final img = cell.querySelector('img');
        final imgUrl = img?.attributes['src']?.trim();

        final text = cell.text.replaceAll('\n', ' ').trim();
        row.add(_CellData(text: text, imageUrl: imgUrl));
      }

      if (row.isNotEmpty && !row.every((c) => c.isEmpty)) {
        rawRows.add(row);
        if (row.length > maxCols) maxCols = row.length;
      }
    }

    if (rawRows.isEmpty) {
      return const _TableData(headers: [], rows: [], roles: []);
    }

    // ✅ ヘッダーが無いテーブルは Col 1.. を生成（データ1行目を消さない）
    if (!firstHasTh) {
      headers = List.generate(maxCols, (i) => 'Col ${i + 1}');
    } else {
      // pad headers（ヘッダー数 < 実データ列数）
      if (headers.length < maxCols) {
        final add = maxCols - headers.length;
        headers = [
          ...headers,
          ...List.generate(add, (i) => 'Col ${headers.length + i + 1}'),
        ];
      }
    }

    // normalize rows to header length
    final normalized = rawRows.map((row) {
      final out = List<_CellData>.from(row);
      if (out.length > headers.length) {
        out.removeRange(headers.length, out.length);
      }
      if (out.length < headers.length) {
        out.addAll(
          List.generate(
            headers.length - out.length,
            (_) => const _CellData(text: ''),
          ),
        );
      }
      return out;
    }).toList();

    // roles
    final roles = headers.map(_guessRoleFromHeader).toList();

    // Element -> Character badge
    final charIdx = roles.indexOf(_ColRole.character);
    final elemIdx = roles.indexOf(_ColRole.element);

    if (charIdx >= 0 &&
        elemIdx >= 0 &&
        charIdx < headers.length &&
        elemIdx < headers.length) {
      for (final row in normalized) {
        final elemCell = row[elemIdx];

        row[charIdx] = row[charIdx].copyWith(
          badgeImageUrl:
              (elemCell.imageUrl != null &&
                  elemCell.imageUrl!.trim().isNotEmpty)
              ? elemCell.imageUrl
              : null,
          badgeText:
              (elemCell.imageUrl == null || elemCell.imageUrl!.trim().isEmpty)
              ? (elemCell.text.trim().isEmpty ? null : elemCell.text.trim())
              : null,
        );
      }

      headers.removeAt(elemIdx);
      roles.removeAt(elemIdx);
      for (final row in normalized) {
        row.removeAt(elemIdx);
      }
    }

    return _TableData(headers: headers, rows: normalized, roles: roles);
  }

  static _ColRole _guessRoleFromHeader(String h) {
    final t = h.trim().toLowerCase();

    if (t.contains('banner') || t.contains('ガチャ') || t.contains('バナー')) {
      return _ColRole.banner;
    }
    if (t.contains('character') || t.contains('キャラ') || t.contains('キャラクター')) {
      return _ColRole.character;
    }
    if (t.contains('element') || t.contains('元素') || t.contains('属性')) {
      return _ColRole.element;
    }
    if (t.contains('quality') ||
        t.contains('rarity') ||
        t.contains('レア') ||
        t.contains('星')) {
      return _ColRole.quality;
    }

    return _ColRole.unknown;
  }
}

enum _ColRole { banner, character, element, quality, unknown }

class _CellData {
  final String text;
  final String? imageUrl;

  final String? badgeImageUrl;
  final String? badgeText;

  const _CellData({
    required this.text,
    this.imageUrl,
    this.badgeImageUrl,
    this.badgeText,
  });

  bool get isEmpty =>
      text.trim().isEmpty &&
      (imageUrl == null || imageUrl!.trim().isEmpty) &&
      (badgeImageUrl == null || badgeImageUrl!.trim().isEmpty) &&
      (badgeText == null || badgeText!.trim().isEmpty);

  _CellData copyWith({
    String? text,
    String? imageUrl,
    String? badgeImageUrl,
    String? badgeText,
  }) {
    return _CellData(
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      badgeImageUrl: badgeImageUrl ?? this.badgeImageUrl,
      badgeText: badgeText ?? this.badgeText,
    );
  }
}

class _TableData {
  final List<String> headers;
  final List<List<_CellData>> rows;
  final List<_ColRole> roles;

  const _TableData({
    required this.headers,
    required this.rows,
    required this.roles,
  });

  int get colCount => headers.length;
}

// ============================================================
// Render widget with paging + horizontal scroll
// ============================================================
class _WpTableWidget extends StatefulWidget {
  final _TableData data;
  const _WpTableWidget({required this.data});

  @override
  State<_WpTableWidget> createState() => _WpTableWidgetState();
}

class _WpTableWidgetState extends State<_WpTableWidget> {
  static const int _pageSize = 10;
  int _page = 0;

  int get _totalPages =>
      (widget.data.rows.length / _pageSize).ceil().clamp(1, 9999);

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    // ✅ rowsが変動してもページが死なないように安全化
    final safePage = _page.clamp(0, _totalPages - 1);
    final start = safePage * _pageSize;
    final end = (start + _pageSize).clamp(0, data.rows.length);
    final pageRows = data.rows.sublist(start, end);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: _tableCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final shouldScroll = data.colCount >= 3;

            final table = _buildTable(
              maxWidth: maxWidth,
              headers: data.headers,
              roles: data.roles,
              rows: pageRows,
            );

            final tableView = shouldScroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: maxWidth),
                      child: table,
                    ),
                  )
                : table;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                tableView,
                if (data.rows.length > _pageSize) ...[
                  const SizedBox(height: 10),
                  _pager(safePage),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pager(int safePage) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: safePage > 0
              ? () => setState(() => _page = safePage - 1)
              : null,
          child: const Text('Prev'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('${safePage + 1} / $_totalPages'),
        ),
        TextButton(
          onPressed: (safePage + 1) < _totalPages
              ? () => setState(() => _page = safePage + 1)
              : null,
          child: const Text('Next'),
        ),
      ],
    );
  }

  Widget _tableCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD0D5DD)),
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFFF7F7F9),
        ),
        child: child,
      ),
    );
  }

  Widget _buildTable({
    required double maxWidth,
    required List<String> headers,
    required List<_ColRole> roles,
    required List<List<_CellData>> rows,
  }) {
    final colWidths = <int, TableColumnWidth>{};

    if (headers.length == 2) {
      colWidths[0] = FixedColumnWidth(maxWidth * 0.42);
      colWidths[1] = const FlexColumnWidth();
    } else {
      for (int i = 0; i < headers.length; i++) {
        switch (roles[i]) {
          case _ColRole.quality:
            colWidths[i] = const FixedColumnWidth(110);
            break;
          case _ColRole.character:
            colWidths[i] = const FixedColumnWidth(170);
            break;
          case _ColRole.banner:
            colWidths[i] = const FixedColumnWidth(200);
            break;
          default:
            colWidths[i] = const FixedColumnWidth(180);
        }
      }
    }

    return Table(
      columnWidths: colWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      border: const TableBorder(
        horizontalInside: BorderSide(color: Color(0xFFD0D5DD), width: 1),
        verticalInside: BorderSide(color: Color(0xFFD0D5DD), width: 1),
      ),
      children: [_headerRow(headers), ...rows.map((r) => _dataRow(r, roles))],
    );
  }

  TableRow _headerRow(List<String> headers) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFEFEFF2)),
      children: headers
          .map(
            (h) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                h,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  TableRow _dataRow(List<_CellData> cells, List<_ColRole> roles) {
    return TableRow(
      children: List.generate(cells.length, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: _cellWidget(cells[i], roles[i]),
        );
      }),
    );
  }

  Widget _cellWidget(_CellData cell, _ColRole role) {
    double imgW = 56, imgH = 56;
    BoxFit fit = BoxFit.cover;

    if (role == _ColRole.banner) {
      imgW = 110;
      imgH = 62;
    } else if (role == _ColRole.quality) {
      imgW = 44;
      imgH = 44;
      fit = BoxFit.contain;
    }

    Widget? imageWidget;
    if (cell.imageUrl != null && cell.imageUrl!.trim().isNotEmpty) {
      imageWidget = Stack(
        clipBehavior: Clip.none,
        children: [
          _netImage(cell.imageUrl!, w: imgW, h: imgH, radius: 12, fit: fit),
          if (cell.badgeImageUrl != null &&
              cell.badgeImageUrl!.trim().isNotEmpty)
            Positioned(
              top: -6,
              right: -6,
              child: _netImage(
                cell.badgeImageUrl!,
                w: 22,
                h: 22,
                radius: 11,
                fit: BoxFit.cover,
              ),
            ),
          if ((cell.badgeImageUrl == null ||
                  cell.badgeImageUrl!.trim().isEmpty) &&
              cell.badgeText != null &&
              cell.badgeText!.trim().isNotEmpty)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  cell.badgeText!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1.1,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    final hasText = cell.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageWidget != null) ...[
          imageWidget,
          if (hasText) const SizedBox(height: 8),
        ],
        if (hasText)
          Text(
            cell.text,
            softWrap: true,
            style: const TextStyle(fontSize: 15, height: 1.35),
          ),
      ],
    );
  }

  Widget _netImage(
    String url, {
    required double w,
    required double h,
    required double radius,
    required BoxFit fit,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: url,
        width: w,
        height: h,
        fit: fit,
        placeholder: (context, _) =>
            Container(width: w, height: h, color: const Color(0xFFE5E7EB)),
        errorWidget: (context, _, __) => Container(
          width: w,
          height: h,
          color: const Color(0xFFE5E7EB),
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }
}
