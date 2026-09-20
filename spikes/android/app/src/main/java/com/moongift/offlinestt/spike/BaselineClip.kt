package com.moongift.offlinestt.spike

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * test-assets/baseline-audio 配下の各 .json ファイルを読み込むためのデータ型。
 * app/build.gradle.kts の sourceSets 設定により、このディレクトリの内容はコピーなしで
 * そのままアプリの assets として参照できる (Issue #11/#12/#13 用、main sourceSet)。
 */
data class BaselineClip(
    val clipId: String,
    val locale: String,
    val transcript: String,
    /** 各要素は String、または許容表記を列挙した List<String> のいずれか (design.md §7)。 */
    val keywords: List<Any>,
    val sampleRate: Int,
    val channels: Int,
)

object BaselineAssets {

    /**
     * `<clipId>.json` と `<clipId>.wav` を assets から読み込む。存在しない・スキーマ不正な場合は
     * 明確に例外を投げる (フォールバックしない)。
     */
    fun loadClip(context: Context, clipId: String): BaselineClip {
        val jsonName = "$clipId.json"
        SpikeLog.info("BaselineAssets: $jsonName を読み込む。")
        val text = context.assets.open(jsonName).use { it.readBytes().toString(Charsets.UTF_8) }
        val obj = JSONObject(text)

        val locale = obj.getString("locale")
        val transcript = obj.getString("transcript")
        val keywordsArray = obj.getJSONArray("keywords")
        val keywords = mutableListOf<Any>()
        for (i in 0 until keywordsArray.length()) {
            when (val item = keywordsArray.get(i)) {
                is JSONArray -> {
                    val variants = mutableListOf<String>()
                    for (j in 0 until item.length()) variants.add(item.getString(j))
                    keywords.add(variants)
                }
                else -> keywords.add(item.toString())
            }
        }
        val sampleRate = obj.getInt("sample_rate")
        val channels = obj.getInt("channels")

        SpikeLog.ok("BaselineAssets: $jsonName 読み込み成功 (locale=$locale, keywords=${keywords.size}件)")
        return BaselineClip(clipId, locale, transcript, keywords, sampleRate, channels)
    }

    fun openWav(context: Context, clipId: String) = context.assets.open("$clipId.wav")

    fun openM4a(context: Context, clipId: String) = context.assets.open("$clipId.m4a")

    /** androidTest/main どちらの assets からも見える基準クリップの一覧 (design.md §7 / tasks.md M0)。 */
    val ALL_CLIP_IDS = listOf("jaJP_10s", "jaJP_3m", "enUS_10s", "enUS_3m")
}
