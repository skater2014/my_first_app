// lib/utils/gw_url.dart

// このファイルは、メディアURLや相対URLを処理するための関数を提供します。
// 主に、画像や動画のURLを正しい形式に変換するために使用されます。
// また、httpsへの変換やavif形式の回避など、URLの整形を行います。

// ベースとなるURL。これを使って相対URLを絶対URLに変換する。
const String gwWpOrigin = 'https://gamewidth.net';

// メディアURLを修正する関数。
// 入力されたURLが無効であればnullを返し、有効な場合は必要に応じてURLを整形します。
String? gwFixMediaUrl(String? url) {
  // urlがnullまたは空文字列の場合はそのままnullを返す
  if (url == null) return null;
  final s = url.trim();
  if (s.isEmpty) return null;

  // avif形式の画像を回避。avifが含まれているURLはnullを返す
  final noQuery = s.toLowerCase().split('?').first; // クエリパラメータを除いたURLを取得
  if (noQuery.endsWith('.avif')) return null;

  // URLが'//'で始まっている場合、https://を追加して返す
  if (s.startsWith('//')) return 'https:$s';

  // URLが'/'で始まっている相対URLの場合、ベースURLを付け加えて完全なURLを返す
  if (s.startsWith('/')) return '$gwWpOrigin$s';

  // 'http://'で始まっている場合、'https://'に置き換えて返す
  if (s.startsWith('http://')) return s.replaceFirst('http://', 'https://');

  // その他のURLはそのまま返す
  return s;
}
