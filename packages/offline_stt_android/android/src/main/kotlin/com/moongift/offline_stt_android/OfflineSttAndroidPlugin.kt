package com.moongift.offline_stt_android

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * offline_stt のAndroidネイティブ側エントリポイント(雛形)。
 *
 * Pigeon生成コード(`pigeons/offline_stt_events.dart` から生成、Issue #24)の
 * `OfflineSttHostApi`(MethodChannel)・`OfflineSttStreamEvents`
 * (EventChannel、design.md §2.3)は同パッケージ内の [Pigeon.g.kt] を参照。
 * ML Kit GenAI Speech Recognition連携の実装本体はM3で行う(design.md §4.3)。
 */
class OfflineSttAndroidPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // TODO(M3): `OfflineSttHostApi` を実装したクラスを
        // `OfflineSttHostApi.setUp(binding.binaryMessenger, ...)` で登録する。
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // TODO(M3): リソース解放。
    }
}
