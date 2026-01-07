// lib/main.dart
//
// 目的（初心者向け）
// ✅ Firebase（= GA4 / Analytics）をアプリ起動時に初期化する
// ✅ Web/Android/iOS/macOS/windows どれでも同じコードで初期化できるようにする
// ✅ BottomNavigationBar のタブ切替を GA4 に「画面表示」として送る（screen_view）
// ✅ タブクリックイベントも送る（tab_click）
//
// ポイント
// - 以前は「Webだと options が無いので落ちる」→ kIsWeb でスキップしていた
// - 今は flutterfire configure で lib/firebase_options.dart が生成されたので
//   Webでも options を渡して初期化できる（＝WebでもGA4計測できる）

import 'package:flutter/material.dart';

// Firebase（GA4）
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

// ✅ flutterfire configure で自動生成された設定ファイル
// ここに Web/Android/iOS... のFirebase設定が入っている
import 'firebase_options.dart';

// ▼ BottomNavigationBar で切り替える各画面
import 'screens/timeline_screen.dart';
import 'screens/search_screen.dart';
import 'screens/category_posts_screen.dart';
import 'screens/likes_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  // Flutterアプリ起動前に「ネイティブ側の準備」を完了させるお決まりの行
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ ここが最重要：Firebase初期化
  //
  // なぜ options が必要？
  // - Webは Firebase の設定(apiKey など)をコードで渡さないと初期化できない
  // - Android/iOSは google-services.json / plist で補えることが多いが、
  //   どのプラットフォームでも確実に動くのがこの書き方
  //
  // DefaultFirebaseOptions.currentPlatform が
  // 「今動いてる端末(Web/Android/iOS...)」に合った設定を自動で選んでくれる
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Firebaseの準備ができてからアプリUIを起動
  runApp(const GameWidthApp());
}

/// アプリ全体の設定（MaterialApp）
class GameWidthApp extends StatelessWidget {
  const GameWidthApp({super.key});

  // ✅ Analytics インスタンス（GA4へイベント送信に使う）
  static final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GameWidth',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

/// BottomNavigationBar で画面を切り替える「殻」
/// - ここは index 管理 + 画面切替 + GA4 計測だけ担当
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // ✅ 現在選択中のタブ index
  int _index = 0;

  // ✅ タブと画面の対応（順番は items と一致）
  final _screens = const [
    TimelineScreen(), // 0: Home
    SearchScreen(), // 1: Search
    CategoriesScreen(), // 2: Categories
    LikesScreen(), // 3: Likes
    ProfileScreen(), // 4: Profile
  ];

  // ✅ GA4 に送る screen_name（分析で使いやすい名前）
  static const _screenNames = [
    'home',
    'search',
    'categories',
    'likes',
    'profile',
  ];

  // ✅ GA4 に送る screen_class（画面の種類）
  // 画面レポートで見分けやすくするために分ける
  static const _screenClasses = [
    'TimelineScreen',
    'SearchScreen',
    'CategoriesScreen',
    'LikesScreen',
    'ProfileScreen',
  ];

  @override
  void initState() {
    super.initState();

    // ✅ 起動直後の初期タブも "画面表示(screen_view)" を送る
    // build前に呼ぶため、microtaskで1テンポ遅らせる
    Future.microtask(() => _logScreenView(_index));
  }

  /// ✅ タブ切替時の screen_view を送る
  /// - BottomNavigationBar の切替は Navigator の画面遷移ではないので手動で送る
  Future<void> _logScreenView(int index) async {
    await GameWidthApp.analytics.logScreenView(
      screenName: _screenNames[index], // GA4での "screen_name"
      screenClass: _screenClasses[index], // GA4での "screen_class"
    );
  }

  /// ✅ タブクリックイベント（任意）
  /// - 画面表示とは別に「どのタブが押されたか」をイベントとして残す
  Future<void> _logTabClick(int index) async {
    await GameWidthApp.analytics.logEvent(
      name: 'tab_click',
      parameters: {'tab': _screenNames[index], 'index': index},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) async {
          // 同じタブを押しただけなら何もしない（無駄な計測も防ぐ）
          if (i == _index) return;

          // 画面切替（UI更新）
          setState(() => _index = i);

          // 画面切替後に計測（GA4に送信）
          await _logScreenView(i);
          await _logTabClick(i);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.apps), label: 'Categories'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Likes'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
