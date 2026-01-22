// search_genshin_characters.dart
// このファイルは、Genshin Impactキャラクターの検索と表示を行うウィジェット（SearchGenshinCharacters）を定義しています。
// APIからキャラクター情報を取得し、ユーザーが指定した名前に基づいて結果をフィルタリングして表示します。
// また、リフレッシュ機能やエラーハンドリングも提供します。

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// SearchGenshinCharacters：Genshin Impactキャラクターの検索
class SearchGenshinCharacters extends StatefulWidget {
  const SearchGenshinCharacters({super.key, required this.nameQuery});

  final String nameQuery; // 検索クエリ（キャラクター名）

  @override
  State<SearchGenshinCharacters> createState() =>
      _SearchGenshinCharactersState();
}

class _SearchGenshinCharactersState extends State<SearchGenshinCharacters> {
  static const String _endpoint =
      'https://gamewidth.net/wp-json/gwc/v1/characters?lang=ja&full=false'; // APIエンドポイント

  late Future<List<_GenshinChar>> _future; // キャラクター情報を保持するFuture

  @override
  void initState() {
    super.initState();
    _future = _fetch(); // 初期データを非同期に取得
  }

  // キャラクター情報をAPIから取得する非同期メソッド
  Future<List<_GenshinChar>> _fetch() async {
    final res = await http.get(Uri.parse(_endpoint)); // APIからデータを取得
    if (res.statusCode != 200) {
      throw Exception('API error: ${res.statusCode}'); // エラーハンドリング
    }
    final data = jsonDecode(res.body); // レスポンスのJSONをデコード
    final list = (data is List)
        ? data
        : (data['items'] as List? ?? []); // アイテムのリストを取得
    return list
        .map((e) => _GenshinChar.fromJson(e))
        .toList(); // キャラクター情報をモデルに変換
  }

  // リフレッシュ時に再度データを取得
  Future<void> _refresh() async {
    setState(() => _future = _fetch()); // 新しいデータを取得
    await _future; // データが取得されるまで待機
  }

  // 検索クエリに基づいてキャラクターリストをフィルタリング
  List<_GenshinChar> _applyName(List<_GenshinChar> all) {
    final q = widget.nameQuery.trim().toLowerCase(); // 検索クエリを小文字に変換
    if (q.isEmpty) return all; // クエリが空ならすべてのキャラクターを表示
    return all
        .where((c) => c.name.toLowerCase().contains(q))
        .toList(); // 名前にクエリが含まれるキャラクターをフィルタリング
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh, // リフレッシュ時の処理
      child: FutureBuilder<List<_GenshinChar>>(
        future: _future, // 非同期で取得したキャラクターリスト
        builder: (context, snap) {
          // 非同期処理中
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(),
            ); // ローディングインジケーター
          }
          // エラー発生時
          if (snap.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(child: Text('Error: ${snap.error}')), // エラーメッセージ
                const SizedBox(height: 12),
                Center(
                  child: FilledButton(
                    onPressed: _refresh, // 再試行ボタン
                    child: const Text('Retry'),
                  ),
                ),
              ],
            );
          }

          final all =
              snap.data ?? const <_GenshinChar>[]; // データがnullの場合は空リストを使用
          final view = _applyName(all); // 検索クエリに基づいてキャラクターをフィルタリング

          // 結果がない場合の表示
          if (view.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No characters')), // キャラクターが見つからなかった場合
              ],
            );
          }

          // キャラクター一覧のグリッド表示
          return GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              MediaQuery.of(context).padding.bottom + 90,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // 横3列で表示
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1, // アイコンのアスペクト比
            ),
            itemCount: view.length, // 表示するアイテム数
            itemBuilder: (context, i) {
              final c = view[i]; // キャラクター情報
              return _IconTile(
                name: c.name,
                iconUrl: c.iconUrl,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('tap: ${c.name} (id=${c.id})'),
                    ), // タップしたキャラクターの情報を表示
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// アイコンタイルウィジェット：キャラクターのアイコンと名前を表示
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.name,
    required this.iconUrl,
    required this.onTap,
  });

  final String name;
  final String? iconUrl; // アイコンURL
  final VoidCallback onTap; // タップ時のコールバック

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; // テーマから色を取得
    final url = (iconUrl ?? '').trim(); // アイコンURLがない場合は空文字列

    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14), // アイコンの角を丸くする
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap, // アイコンがタップされたときの処理
        child: Tooltip(
          message: name, // アイコンにマウスオーバーしたときのツールチップ
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: cs.surfaceContainerHighest,
              ),
              clipBehavior: Clip.antiAlias,
              child: url.isEmpty
                  ? Icon(
                      Icons.person,
                      color: cs.onSurfaceVariant,
                    ) // アイコンがない場合はデフォルトのアイコン
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.broken_image,
                        color: cs.onSurfaceVariant,
                      ), // 画像の読み込み失敗時
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// Genshin Impactキャラクターを表すモデルクラス
class _GenshinChar {
  final int id;
  final String name;
  final String? iconUrl;

  const _GenshinChar({
    required this.id,
    required this.name,
    required this.iconUrl,
  });

  // JSONから_GenshinCharオブジェクトを生成するファクトリメソッド
  factory _GenshinChar.fromJson(Map<String, dynamic> j) {
    int toInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    String toStr(dynamic v) => (v == null) ? '' : v.toString();

    return _GenshinChar(
      id: toInt(j['id']),
      name: toStr(j['name'] ?? j['title']),
      iconUrl: (j['icon'] ?? j['thumb'] ?? j['image'])
          ?.toString(), // アイコンURLを取得
    );
  }
}
