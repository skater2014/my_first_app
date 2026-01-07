// android/settings.gradle.kts
//
// 目的：
// - Flutter が使う Gradle プラグインを読み込む
// - 使う Gradle プラグイン（Android/Kotlin/Google Services 等）の
//   「入手先(repositories)」と「バージョン(version)」をここで宣言する
//   → app/build.gradle.kts の plugins { id(...) } が解決できるようになる

pluginManagement {
    // 目的：Flutter SDK の場所を local.properties から取得して、
    // Flutter が提供する Gradle プラグインを includeBuild で読み込む
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    // 目的：Flutter の Gradle プラグイン（dev.flutter.*）を使えるようにする
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    // 目的：Gradle がプラグインを探しに行く場所
    // （google-services プラグインは google() が必須）
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// 目的：プロジェクトで使う Gradle プラグインのバージョンをここで一括管理する
// apply false を付けたものは「各モジュール(app)側で必要なときに適用する」方式
plugins {
    // Flutter 側のプラグインローダー（Flutterテンプレ）
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"

    // Android Gradle Plugin
    id("com.android.application") version "8.11.1" apply false

    // Kotlin Android Plugin
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false

    // ✅ 追加：Google Services Gradle Plugin
    // 目的：android/app/google-services.json を読み取り、
    // Firebase(Analytics/GA4など)の設定値をビルドに取り込むため
    // → app/build.gradle.kts で id("com.google.gms.google-services") を書けるようにする
    id("com.google.gms.google-services") version "4.4.4" apply false
}

// 目的：アプリモジュールを含める（FlutterのAndroidは基本 :app）
include(":app")
