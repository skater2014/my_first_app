// lib/widgets/wp_html_view.dart
//
// ==============================
// 目的：WpHtmlView とは何か？
// ==============================
//
// WordPress（またはAPI）から取得した「本文HTML文字列」を
// Flutterアプリの画面に“見た目付きで”表示するためのウィジェットです。
//
// - flutter_html を使って HTML を Flutter のWidgetに変換して表示します。
// - <img> タグだけは、そのままだと「横にはみ出す」「重い」などが起きやすいので、
//   CachedNetworkImage に置き換えて、表示幅を制限しつつキャッシュします。
//
// ✅このファイルは「本文（見出し/段落/画像）」専用。
// ✅テーブルは別ファイル（wp_tables.dart）で処理する想定。
// ==============================

import 'package:flutter/material.dart';
// ↑ Flutterの基本UI部品（Widget / Colors / TextStyle / MediaQueryなど）を使うため

import 'package:flutter_html/flutter_html.dart';
// ↑ HTML文字列を解析して、FlutterのWidgetツリーとして描画してくれるライブラリ

import 'package:cached_network_image/cached_network_image.dart';
// ↑ ネット画像を表示しつつキャッシュ（保存）するライブラリ
//   - 同じ画像を再表示しても再ダウンロードしにくくなる（速い/通信節約）
//   - ローディング表示やエラー表示も簡単に付けられる

// ==============================
// WpHtmlView：本文HTMLを表示するWidget
// ==============================
//
// StatelessWidget：状態（State）を持たない、固定表示向きのWidget。
// - 入力（html）が変われば、再ビルドされて表示が変わる。
// - 画面内で「ページング」「ボタンで状態変化」などが無い限り Stateless でOK。
class WpHtmlView extends StatelessWidget {
  // ------------------------------
  // 表示するHTML本文（外から渡される）
  // ------------------------------
  //
  // 例：post.content.rendered みたいなやつ
  final String html;

  // ------------------------------
  // ✅ static const の意味（超重要）
  // ------------------------------
  //
  // const：コンパイル時に確定する「固定値」。毎回newしないので軽い。
  // static：クラスのインスタンスではなく「クラスに属する値」になる。
  //
  // つまり：
  // - WpHtmlViewを何個作ってもこの値は1個だけ
  // - 実行中に変わらない
  //
  // ✅ _horizontalPadding = 16.0 は何のため？
  // PostDetailScreen 側で左右に Padding(horizontal: 16) を付けている前提で、
  // 「本文が実際に表示される幅」を計算するために使います。
  //
  // なぜ必要？
  // - 画像 <img> が画面幅いっぱいで表示されると左右の余白を無視してはみ出すから。
  //
  // 16.0 は「16px相当（論理ピクセル）」です。
  static const double _horizontalPadding = 16.0;

  // ------------------------------
  // コンストラクタ
  // ------------------------------
  //
  // required this.html
  // → WpHtmlView を使う側が必ず html を渡す必要がある、という意味。
  //
  // super.key
  // → FlutterがWidgetを識別するためのkey（通常はそのまま付けておく）
  const WpHtmlView({super.key, required this.html});

  @override
  Widget build(BuildContext context) {
    // ------------------------------
    // screenW：端末の画面幅
    // ------------------------------
    //
    // MediaQuery は「画面サイズや文字倍率」など、端末の表示情報を取る仕組み。
    // size.width は画面の横幅。
    final screenW = MediaQuery.of(context).size.width;

    // ------------------------------
    // contentW：本文が表示される“実際の幅”
    // ------------------------------
    //
    // PostDetailScreen 側で左右に 16px 余白がある前提なら、
    // 本文の実幅は「画面幅 - 左右余白(16*2)」になる。
    //
    // clamp(0.0, screenW)
    // → マイナスになるなどの異常値を防ぐため、
    //    0〜screenW の範囲に丸める。
    final contentW = (screenW - (_horizontalPadding * 2)).clamp(0.0, screenW);

    // ------------------------------
    // Html：flutter_html の本体Widget
    // ------------------------------
    //
    // data: html でHTML文字列を渡すと、
    // flutter_html が <p> <h1> <img> などを解析して表示してくれる。
    return Html(
      data: html,

      // ==============================
      // style：HTMLタグごとの見た目設定
      // ==============================
      //
      // 例： "p" は段落、 "h1" は見出し、 "img" は画像
      // ここで「フォントサイズ」「余白」「色」などを調整できる。
      style: {
        // body：HTML全体の基準スタイル
        "body": Style(
          // HTMLのデフォルト余白が付くことがあるので 0 にする
          margin: Margins.zero,
          padding: HtmlPaddings.zero,

          // 文字サイズ（本文のベース）
          fontSize: FontSize(15),

          // 行間（1.6倍）
          lineHeight: LineHeight.number(1.6),

          // 文字色
          color: Colors.black87,
        ),

        // p：段落（下に少し余白を入れて読みやすくする）
        "p": Style(margin: Margins.only(bottom: 12)),

        // 見出し：太め＆サイズ大きめ、上下に余白
        "h1": Style(
          fontSize: FontSize(24),
          fontWeight: FontWeight.w800,
          margin: Margins.only(top: 18, bottom: 10),
        ),
        "h2": Style(
          fontSize: FontSize(21),
          fontWeight: FontWeight.w800,
          margin: Margins.only(top: 18, bottom: 10),
        ),
        "h3": Style(
          fontSize: FontSize(18),
          fontWeight: FontWeight.w700,
          margin: Margins.only(top: 16, bottom: 8),
        ),

        // ul / ol：リスト（左にインデント、上下に余白）
        "ul": Style(
          padding: HtmlPaddings.only(left: 18),
          margin: Margins.only(top: 8, bottom: 12),
        ),
        "ol": Style(
          padding: HtmlPaddings.only(left: 18),
          margin: Margins.only(top: 8, bottom: 12),
        ),
        "li": Style(margin: Margins.only(bottom: 6)),

        // img：ここにも保険で設定しておく（本命は extensions 側）
        "img": Style(
          // 本文幅に合わせる（はみ出し防止）
          width: Width(contentW),

          // 高さは自動（縦横比を保つ）
          height: Height.auto(),

          // 上下に余白
          margin: Margins.only(top: 10, bottom: 10),

          // ブロック要素扱い（行の中に埋まらないようにする）
          display: Display.block,
        ),
      },

      // ==============================
      // extensions：特定タグの描画を“差し替える”
      // ==============================
      //
      // なぜ差し替える？
      // flutter_html のデフォルトimg表示は
      // - 画像が大きいと崩れる
      // - キャッシュが効かない
      // - 読み込み中/失敗時のUIが弱い
      //
      // だから <img> を CachedNetworkImage に置き換えている。
      extensions: [
        TagExtension(
          // 対象タグ：img
          tagsToExtend: {"img"},

          // builder：imgタグが出てきたら、ここでWidgetを返す
          builder: (ctx) {
            // ctx.attributes は <img src="..."> の属性を持つ
            // src を取得してトリム（空白除去）
            final src = (ctx.attributes["src"] ?? "").trim();

            // srcが無いimgは表示しない
            if (src.isEmpty) return const SizedBox.shrink();

            // devicePixelRatio：端末の解像度倍率
            // iPhone/高精細端末では 2.0, 3.0 などになる
            // → memCacheWidth を “表示幅×倍率” にすることで
            //   余計にデカい画像デコードを避けて軽くできる
            final dpr = MediaQuery.of(context).devicePixelRatio;
            final memW = (contentW * dpr).round();

            // ここが “画像を画面内に収める” ための構造：
            //
            // ClipRRect：角丸で切り抜く
            // ConstrainedBox(maxWidth: contentW)：横幅の上限を本文幅に固定
            // CachedNetworkImage：ネット画像表示＋キャッシュ
            //
            // fit: BoxFit.contain
            // → 画像を切らずに「全体が収まる」ように縮小して表示する
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentW),
                child: CachedNetworkImage(
                  imageUrl: src,

                  // 画像の収め方（切らない）
                  fit: BoxFit.contain,

                  // メモリキャッシュ用にデコード幅を指定（重さ対策）
                  memCacheWidth: memW,

                  // 読み込み中の表示（ぐるぐる）
                  placeholder: (_, __) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  ),

                  // 失敗時の表示（壊れた画像アイコン）
                  errorWidget: (_, __, ___) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
