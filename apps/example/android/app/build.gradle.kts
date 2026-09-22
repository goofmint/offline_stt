plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.moongift.example"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.moongift.example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        //
        // minSdk は `flutter.minSdkVersion`(Flutter 3.41.9 の既定は 24)では
        // なく 31 を直接指定する。offline_stt が
        // requirements.md NFR-4(Android 12 / API 31 以上)に従って
        // `minSdk 31` を宣言しており、24 のままだとマニフェストのマージが
        //   uses-sdk:minSdkVersion 24 cannot be smaller than version 31
        //   declared in library [:offline_stt]
        // で失敗する(CI で実際に発生した。Issue #82。当時はライブラリ名が
        // `[:offline_stt_android]` だった。Issue #91 で単一パッケージへ
        // 統合したため現在は `[:offline_stt]` になる)。
        //
        // なお API 31/32 では `checkRecognitionSupport()`(API 33 で追加)が
        // 無いため `checkModel()` は常に `unavailable` を返す。すなわち
        // ビルドできる下限は 31 だが、実際に文字起こしできるのは API 33 以上
        // である(packages/offline_stt_android/README.md §2)。
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
