plugins {
    id("com.android.application")
    id("kotlin-android")

    // ✅ google-services.json を読む
    id("com.google.gms.google-services")

    // ✅ Flutter Gradle Plugin は最後
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ✅ ここは applicationId と一致させる
    namespace = "com.gamewidth.app"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.gamewidth.app"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // 何も書かなくてもOK（明示したいならここに書く）
        }
        release {
            // 今は仮でOK（公開時はrelease keystoreに切替）
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // ✅ Firebase BoM（互換バージョンをまとめて管理）
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))

    // ✅ GA4 / Firebase Analytics
    implementation("com.google.firebase:firebase-analytics")
}

flutter {
    source = "../.."
}
