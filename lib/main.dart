import 'package:flutter/material.dart';

// Firebase（GA4）
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';

// ▼ BottomNavigationBar で切り替える各画面
import 'screens/timeline_screen.dart';
import 'screens/search_screen.dart';
import 'screens/category_posts_screen.dart';
import 'screens/likes_screen.dart';
import 'screens/profile_screen.dart';

// ✅ 追加
import 'store/theme_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const GameWidthApp());
}

class GameWidthApp extends StatelessWidget {
  const GameWidthApp({super.key});

  static final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeStore.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'GameWidth',

          // ✅ ここが追加
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
            brightness: Brightness.light,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            brightness: Brightness.dark,
          ),

          home: const MainShell(),
        );
      },
    );
  }
}

// MainShell はそのままでOK
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  final List<Widget> _screens = const [
    TimelineScreen(),
    SearchScreen(),
    CategoriesScreen(),
    LikesScreen(),
    ProfileScreen(),
  ];

  static const _screenNames = [
    'home',
    'search',
    'categories',
    'likes',
    'profile',
  ];
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
    return Scaffold(
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
