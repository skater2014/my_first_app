/// キャラクター情報を表示するウィジェット
/// `TekkenCharactersBody`クラスは、Tekkenキャラクターの情報をAPIから取得し、
/// `GridView`を使用して画面にキャラクター名と画像を表示するためのウィジェットです。


import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../service/wp_api_service.dart'; // WpApiServiceを使ってデータを取得

/// キャラクター情報を表示するウィジェット
class TekkenCharactersBody extends StatefulWidget {
  const TekkenCharactersBody({super.key});

  @override
  _TekkenCharactersBodyState createState() => _TekkenCharactersBodyState();
}

class _TekkenCharactersBodyState extends State<TekkenCharactersBody> {
  late Future<List<Map<String, String>>> characters;

  // APIからデータを取得する非同期関数
  Future<List<Map<String, String>>> fetchCharacters() async {
    final wpApiService = WpApiService(); // WpApiServiceを使ってデータを取得
    return await wpApiService
        fetchTekken7Characters(); // 名前と画像のみ取得
  }

  @override
  void initState() {
    super.initState();
    characters = fetchCharacters(); // APIからデータを取得
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, String>>>(
      future: characters,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator()); // ローディング中
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}')); // エラー表示
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No characters found'),
          ); // キャラクターがない場合
        } else {
          List<Map<String, String>> charactersData = snapshot.data!;

          return GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, // 3カラム
              childAspectRatio: 0.7, // カードの縦横比
              crossAxisSpacing: 10, // カラム間の間隔
              mainAxisSpacing: 10, // 行間の間隔
            ),
            itemCount: charactersData.length,
            itemBuilder: (context, index) {
              var character = charactersData[index];
              return Card(
                color: Colors.black54,
                elevation: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CachedNetworkImage(
                      imageUrl: character['image']!,
                      width: double.infinity,
                      height: 120,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const CircularProgressIndicator(),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error, color: Colors.red),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        character['name']!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        }
      },
    );
  }
}

/// 単独画面として使う場合の Scaffold 版
class TekkenCharactersScreen extends StatelessWidget {
  const TekkenCharactersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tekken Characters')),
      body: const TekkenCharactersBody(),
    );
  }
}
