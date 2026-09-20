// spikes/android/app — M0 Android 検証スパイク本体。
//
// 対応 Issue: #11 (Basic + ja-JP)、#12 (Advanced フォールバック)、#13 (PFDパイプ + 実時間ポンプ)、
//             #14 (MediaCodec デコード出力レート調査、androidTest)。
// 対応する設計: design.md §4.3 Android、§5 エラーマッピング、§6 並行性、§7 評価基準、§8 未決事項5・6。
//
// 方針: フォールバック処理を書かない。取得できない・対応していない場合は明確にエラーにする
// (ユーザーのグローバル指示 CLAUDE.md にも準拠)。

plugins {
    id("com.android.application")
    // NOTE: org.jetbrains.kotlin.android は AGP 9.0 以降は不要 (AGP自体にKotlinサポートが
    // 組み込まれた)。付けるとプラグイン適用時にエラーになるため外している
    // (https://issuetracker.google.com/438678642)。
}

android {
    namespace = "com.moongift.offlinestt.spike"
    compileSdk = 36
    buildToolsVersion = "36.1.0"

    defaultConfig {
        applicationId = "com.moongift.offlinestt.spike"
        // requirements.md NFR-4: Android 12 / API 31 以上。
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.1-m0-spike"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        debug {
            // 検証スパイクなので難読化はしない。ログのシンボルをそのまま追える状態を保つ。
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // NOTE: AGP 9 の組み込み Kotlin サポートでは `kotlinOptions {}` DSL が無い。
    // jvmTarget は compileOptions の source/targetCompatibility (VERSION_17) から
    // 組み込みサポートが自動的に解決する。

    buildFeatures {
        viewBinding = false
    }

    // 基準音声 (test-assets/baseline-audio/) をリポジトリ内にコピーせず、そのまま
    // assets ソースディレクトリとして参照する。main には手動実行ハーネス (Issue #11/#12/#13) が、
    // androidTest には Instrumentation Test (Issue #14) が、同じディレクトリを参照する。
    //
    // androidTest には加えて fixtures/generated/ (Issue #14: 実環境相当音源。
    // fixtures/generate-rate-fixtures.sh の生成物。コミット対象外) も参照する。基準音声のみが
    // 16kHz・モノラルで生成されたものであり、それだけでは手持ち音源(44.1kHz/48kHzステレオ等)に
    // 対するリサンプリング要否を判定できない(循環論法になる)ため、実環境相当音源を追加している。
    sourceSets {
        getByName("main") {
            assets.srcDirs("../../../test-assets/baseline-audio")
        }
        getByName("androidTest") {
            assets.srcDirs("../../../test-assets/baseline-audio", "../fixtures/generated")
        }
    }

    packaging {
        resources {
            // ML Kit / Play Services / Firebase の推移的依存が META-INF にライセンス等の
            // 重複ファイルを持ち込むことがあるため、ビルド失敗を避けるために除外する。
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "META-INF/LICENSE*"
            excludes += "META-INF/NOTICE*"
            excludes += "META-INF/DEPENDENCIES"
        }
    }
}

dependencies {
    // ML Kit GenAI Speech Recognition (alpha)。バージョン固定 (design.md リスク表参照)。
    implementation("com.google.mlkit:genai-speech-recognition:1.0.0-alpha1")

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // Issue #14: Instrumentation Test (MediaExtractor/MediaCodec 実測)。
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
}
