// lib/model/comment.dart

/// WordPress のコメント 1件分
class Comment {
  final int id;
  final int postId;
  final String authorName;
  final String content; // ← ここは「タグを剥がしたテキスト」
  final DateTime date;

  Comment({
    required this.id,
    required this.postId,
    required this.authorName,
    required this.content,
    required this.date,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    // WordPress から来る HTML 付き本文
    final raw = (json['content']?['rendered'] ?? '') as String;

    // ★ ここで <p> や <br> などを処理
    final cleaned = raw
        // <br> → 改行
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        // </p> → 改行
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        // 残りの <タグ> を全部削除
        .replaceAll(RegExp(r'<[^>]+>'), '')
        // 改行などを整える
        .replaceAll('\r', '')
        .replaceAll('\n\n', '\n')
        .trim();

    return Comment(
      id: json['id'] as int,
      postId: json['post'] as int,
      authorName: (json['author_name'] ?? '名無しさん') as String,
      content: cleaned, // ★ タグを剥がしたテキストだけ入れる
      date: DateTime.parse(json['date'] as String),
    );
  }
}
