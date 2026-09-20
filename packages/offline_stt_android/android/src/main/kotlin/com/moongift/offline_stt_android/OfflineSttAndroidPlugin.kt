package com.moongift.offline_stt_android

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * offline_stt のAndroidネイティブ側エントリポイント(雛形)。
 *
 * Pigeonスキーマ確定(design.md §2.3)後、MethodChannel/EventChannelの
 * ハンドラ登録・ML Kit GenAI Speech Recognition連携をここに実装する
 * (design.md §4.3、M3)。
 */
class OfflineSttAndroidPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // TODO(M3): Pigeon生成のAPI実装をここに接続する。
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // TODO(M3): リソース解放。
    }
}
