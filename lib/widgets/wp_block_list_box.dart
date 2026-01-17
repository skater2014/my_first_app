import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:my_first_app/widgets/wp_html_view.dart';

/// WordPress の `wp-block-list`（ul/ol）を、
/// 「枠（点線）＋左に丸番号（または●）＋項目ごと点線区切り」
/// の UI に整形して表示するコンポーネント。
class WpBlockListBox extends StatelessWidget {
  const WpBlockListBox({
    super.key,
    required this.itemHtml,
    required this.ordered,
  });

  /// <li> の innerHtml を配列で渡す（liタグ自体は不要）
  final List<String> itemHtml;

  /// <ol> なら true / <ul> なら false
  final bool ordered;

  @override
  Widget build(BuildContext context) {
    if (itemHtml.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    // withOpacity が deprecated なので withValues を使う（あなたの環境で警告が出てるため）
    final borderColor = theme.dividerColor.withValues(alpha: 0.90);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DottedBorder(
        options: RoundedRectDottedBorderOptions(
          radius: const Radius.circular(14),
          color: borderColor,
          strokeWidth: 1,
          dashPattern: const <double>[4, 3], // 点4 / 間3
          padding: EdgeInsets.zero, // 内側余白は Container 側で管理
          borderPadding: EdgeInsets.zero,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: List.generate(itemHtml.length, (i) {
              return Column(
                children: [
                  _RowItem(index: i, ordered: ordered, html: itemHtml[i]),
                  if (i != itemHtml.length - 1) ...const [
                    SizedBox(height: 10),
                    _DottedDivider(),
                    SizedBox(height: 10),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  const _RowItem({
    required this.index,
    required this.ordered,
    required this.html,
  });

  final int index;
  final bool ordered;
  final String html;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final label = ordered ? '${index + 1}' : '•';

    final circleBg = theme.colorScheme.surfaceContainerHighest;
    final circleFg = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: circleBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: circleFg,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
        const SizedBox(width: 10),

        // ✅ WpHtmlView には style 引数が無いので渡さない（ここが analyzer の error 原因）
        Expanded(child: WpHtmlView(html: '<div>$html</div>')),
      ],
    );
  }
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).dividerColor.withValues(alpha: 0.80);

    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DottedDividerPainter(color: color)),
    );
  }
}

class _DottedDividerPainter extends CustomPainter {
  _DottedDividerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const dotRadius = 1.2;
    const gap = 6.0;

    double x = 0;
    final y = size.height / 2;

    while (x <= size.width) {
      canvas.drawCircle(Offset(x, y), dotRadius, paint);
      x += gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedDividerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
