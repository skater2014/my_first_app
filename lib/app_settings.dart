import 'package:flutter/material.dart';

/// ============================================================
/// AppSettings（アプリ全体で共有する設定・状態）
///
/// ✅ 目的
/// - 画面をまたいで共通で使う状態を「1箇所」で管理する
///   例）
///   - 言語（EN/JP）
///   - ダークモード（ThemeMode）
///   - 検索バーの開閉状態（searchOpen）
///   - 検索文字列（searchQuery）
///   - コンテンツ切替（Genshin/Tekken/All）
///
/// ✅ なぜ必要？
/// - Flutterでは、各画面が別Widgetになるため
///   そのままだと「画面ごとに状態がバラバラ」になりがち。
/// - AppSettingsを Provider でアプリ全体に配ることで
///   どの画面でも同じ状態（言語/ダーク/検索）を参照・更新できる。
///
/// ✅ 仕組み
/// - ChangeNotifier を継承しているので
///   状態が変わったら notifyListeners() を呼ぶ
/// - notifyListeners() が呼ばれると
///   context.watch<AppSettings>() しているWidgetが再描画される
/// ============================================================

/// アプリの言語（将来：多言語に増やしてもOK）
enum AppLang { en, jp }

/// トグルの範囲（All / Genshin / Tekken）
/// 将来：他ゲーム追加するならここに追加
enum ContentScope { all, genshin, tekken }

class AppSettings extends ChangeNotifier {
  /// ------------------------------
  /// 共有したい状態（アプリ全体で共通）
  /// ------------------------------

  /// 言語（デフォルトEN）
  AppLang language = AppLang.en;

  /// テーマモード（light/dark）
  /// - ThemeMode.system にするとOSの設定に追従できる
  ThemeMode themeMode = ThemeMode.light;

  /// 検索バーが開いているか（ヘッダーの🔍で切替）
  bool searchOpen = false;

  /// 検索文字列（検索フォームの中身）
  String searchQuery = '';

  /// コンテンツ範囲（All / Genshin / Tekken）
  ContentScope scope = ContentScope.all;

  /// ------------------------------
  /// 状態を更新するメソッド（UIから呼ぶ）
  /// ------------------------------

  /// ダークモードを切り替える
  /// on=true -> dark, false -> light
  void toggleDark(bool on) {
    themeMode = on ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  /// 言語を変更する
  void setLanguage(AppLang v) {
    language = v;
    notifyListeners();
  }

  /// 範囲トグルを変更する（All/Genshin/Tekken）
  void setScope(ContentScope v) {
    scope = v;
    notifyListeners();
  }

  /// 検索バーの開閉を切り替える
  /// 閉じるときは検索文字も消す（好みで変更OK）
  void toggleSearch() {
    searchOpen = !searchOpen;
    if (!searchOpen) {
      searchQuery = '';
    }
    notifyListeners();
  }

  /// 検索バーを強制的に閉じる（×ボタン用）
  void closeSearch() {
    searchOpen = false;
    searchQuery = '';
    notifyListeners();
  }

  /// 検索文字を更新する（TextFieldの onChanged から呼ぶ）
  void setSearchQuery(String v) {
    searchQuery = v;
    notifyListeners();
  }
}
