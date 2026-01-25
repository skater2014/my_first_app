// lib/main.dart
import 'package:flutter/material.dart';

// Provider
import 'package:provider/provider.dart';
import 'app_settings.dart';

// Firebase（GA4）
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';

// 共通ヘッダー / Drawer
import 'widgets/gw_top_header.dart';
import 'widgets/gw_side_drawer.dart';

// ▼ BottomNavigationBar で切り替える各画面
import 'screens/timeline_screen.dart';
import 'screens/search_screen.dart';
import 'screens/category_posts_screen.dart';
import 'screens/likes_screen.dart';
import 'screens/profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ AppSettings を全体に供給
  runApp(ChangeNotifierProvider(create: (_) => AppSettings(), child: const GameWidthApp()));
}

/// アプリ全体の設定（MaterialApp）
class GameWidthApp extends StatelessWidget {
  const GameWidthApp({super.key});

  static final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return MaterialApp(
      title: 'GameWidth',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: settings.themeMode,
      home: const MainShell(),
    );
  }
}

/// BottomNavigationBar で画面を切り替える「殻」
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final _screens = const [
    TimelineScreen(),
    SearchScreen(),
    CategoriesScreen(),
    LikesScreen(),
    ProfileScreen(),
  ];

  // ✅ GA4 に送る screen_name（分析用）
  static const _screenNames = ['home', 'search', 'categories', 'likes', 'profile'];

  // ✅ GA4 に送る screen_class（分析用）
  static const _screenClasses = [
    'TimelineScreen',
    'SearchScreen',
    'CategoriesScreen',
    'LikesScreen',
    'ProfileScreen',
  ];

  // ✅ 画面に表示するタイトル（UI用）
  static const _titles = ['Timeline', 'Search', 'Categories', 'Likes', 'Profile'];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _logScreenView(_index));
  }

  Future<void> _logScreenView(int index) async {
    await GameWidthApp.analytics.logScreenView(
      screenName: _screenNames[index],
      screenClass: _screenClasses[index],
    );
  }

  Future<void> _logTabClick(int index) async {
    await GameWidthApp.analytics.logEvent(
      name: 'tab_click',
      parameters: {'tab': _screenNames[index], 'index': index},
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProfile = (_index == 4); // Profile は5番目なので index=4

    return Scaffold(
      // ✅ Profile だけトップヘッダーを消す
      appBar: isProfile ? null : GwTopHeader(title: _titles[_index]),

      // ✅ Profile だけ Drawer（ハンバーガー）も消す（必要なら残してもOK）
      drawer: isProfile ? null : GwSideDrawer(),

      body: _screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        type: BottomNavigationBarType.fixed,
        onTap: (i) async {
          if (i == _index) return;
          setState(() => _index = i);
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
