import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:html/dom.dart' as dom;

// ✅ 必ずトップレベル（WpHtmlView の外）に置く
class _CellData {
  final String text;
  final String? imageUrl;
  const _CellData({required this.text, required this.imageUrl});
}

class _TableData {
  final List<String> headers;
  final List<List<_CellData>> rows;
  const _TableData({required this.headers, required this.rows});
}

class WpHtmlView extends StatelessWidget {
  final String html;
  const WpHtmlView({super.key, required this.html});

  double _toPx(dynamic v, {double fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    final s = v.toString();
    if (s.contains('%')) return fallback;
    final m = RegExp(r'(-?\d+(\.\d+)?)').firstMatch(s);
    return m == null ? fallback : double.parse(m.group(1)!);
  }

  bool _isAvif(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.avif') || u.contains('.avif?');
  }

  String _cleanText(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  String? _extractFirstImgUrl(dom.Element cell) {
    final img = cell.querySelector('img');
    if (img == null) return null;
    final src = (img.attributes['src'] ?? '').trim();
    if (src.isEmpty) return null;
    if (_isAvif(src)) return null;
    return src;
  }

  _TableData _extractTable(dom.Element table) {
    final headers = <String>[];
    final rows = <List<_CellData>>[];

    final theadTr = table.querySelector('thead tr');
    if (theadTr != null) {
      final ths = theadTr.querySelectorAll('th,td');
      for (final cell in ths) {
        headers.add(_cleanText(cell.text));
      }
    }

    final bodyTrs = table.querySelectorAll('tbody tr');
    final trs = bodyTrs.isNotEmpty ? bodyTrs : table.querySelectorAll('tr');

    for (final tr in trs) {
      if (theadTr != null && tr == theadTr) continue;

      final cells = tr.querySelectorAll('th,td');
      if (cells.isEmpty) continue;

      final row = <_CellData>[];
      for (final c in cells) {
        row.add(
          _CellData(text: _cleanText(c.text), imageUrl: _extractFirstImgUrl(c)),
        );
      }
      rows.add(row);
    }

    if (headers.isEmpty) {
      final colCount = rows.isNotEmpty ? rows.first.length : 0;
      for (int i = 0; i < colCount; i++) {
        headers.add('Col ${i + 1}');
      }
    }

    final colCount = headers.length;
    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      if (row.length < colCount) {
        rows[r] = [
          ...row,
          ...List.generate(
            colCount - row.length,
            (_) => const _CellData(text: '', imageUrl: null),
          ),
        ];
      } else if (row.length > colCount) {
        rows[r] = row.sublist(0, colCount);
      }
    }

    return _TableData(headers: headers, rows: rows);
  }

  Widget _buildCellWidget(_CellData cell) {
    final hasImg = cell.imageUrl != null && cell.imageUrl!.isNotEmpty;
    final hasText = cell.text.isNotEmpty;

    if (!hasImg && !hasText) return const SizedBox.shrink();
    if (!hasImg) return Text(cell.text, softWrap: true);

    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 84,
        height: 56,
        child: CachedNetworkImage(
          imageUrl: cell.imageUrl!,
          fit: BoxFit.cover, // 切り抜き嫌なら BoxFit.contain に変更
          placeholder: (_, __) => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (_, __, ___) =>
              const Center(child: Icon(Icons.broken_image, size: 18)),
        ),
      ),
    );

    if (!hasText) return thumb;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        thumb,
        const SizedBox(width: 10),
        Flexible(child: Text(cell.text, softWrap: true)),
      ],
    );
  }

  Widget _buildDataTable(dom.Element tableEl) {
    final data = _extractTable(tableEl);
    if (data.headers.isEmpty || data.rows.isEmpty)
      return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // ✅ overflow撲滅
        child: DataTable(
          columnSpacing: 18,
          headingRowHeight: 44,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 120,
          columns: [
            for (final h in data.headers)
              DataColumn(
                label: Text(
                  h,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          rows: [
            for (final r in data.rows)
              DataRow(
                cells: [
                  for (int i = 0; i < data.headers.length; i++)
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _buildCellWidget(
                          i < r.length
                              ? r[i]
                              : const _CellData(text: '', imageUrl: null),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Html(
      data: html,
      style: {
        "table": Style(margin: Margins.zero, padding: HtmlPaddings.zero),
        "img": Style(width: Width(100, Unit.percent)),
      },
      extensions: [
        // ✅ ctx.buildContext は nullable なので使わない。element だけでOK
        TagExtension(
          tagsToExtend: {"table"},
          builder: (ctx) {
            final el = ctx.element;
            if (el == null) return const SizedBox.shrink();
            return _buildDataTable(el);
          },
        ),

        // テーブル外 img
        TagExtension(
          tagsToExtend: {"img"},
          builder: (ctx) {
            final src = (ctx.attributes["src"] ?? "").trim();
            if (src.isEmpty) return const SizedBox.shrink();
            if (_isAvif(src)) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  "この画像は AVIF 形式のためアプリ側で表示できません。\n"
                  "WordPress側で JPG/PNG/WebP に変換してください。",
                ),
              );
            }

            final w = _toPx(ctx.attributes["width"], fallback: 0);
            final h = _toPx(ctx.attributes["height"], fallback: 0);

            final image = CachedNetworkImage(
              imageUrl: src,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, __, ___) => Container(
                height: 140,
                alignment: Alignment.center,
                child: const Text("画像を読み込めません"),
              ),
            );

            if (w > 0 && h > 0) {
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(width: w, height: h, child: image),
              );
            }

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              constraints: const BoxConstraints(minHeight: 140),
              width: double.infinity,
              child: image,
            );
          },
        ),
      ],
    );
  }
}
