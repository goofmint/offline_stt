package com.moongift.offlinestt.spike

import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * M0 Android 検証ハーネス (Issue #11 / #12 / #13) の単一 Activity UI。
 * spikes/web/index.html の「ボタン + 逐次ログ表示領域」方針を踏襲する。
 *
 * 対象クリップは固定で "jaJP_10s" とする (Issue #13 の CodeRabbit プランが明示する最小範囲。
 * design.md §7 の全クリップ評価は Issue #11 の本実装(M3)側の対象であり、本スパイクは
 * パイプライン受理可否とモード挙動の確認に主眼を置く)。
 */
class MainActivity : AppCompatActivity() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var harness: RecognitionHarness
    private lateinit var textLog: TextView
    private lateinit var textResult: TextView

    private val targetClipId = "jaJP_10s"
    private val targetLocale = "ja-JP"

    /**
     * SpikeLog.sink に代入するログ出力先。プロパティとして切り出すことで、onDestroy() で
     * 「自分が設定した sink かどうか」を参照同一性(===)で判定できるようにする (画面回転時に
     * 新しい Activity が既に上書きした sink を誤って null にしないため)。
     */
    private val logSink: (SpikeLog.Level, String) -> Unit = { level, message ->
        runOnUiThread {
            val prefix = when (level) {
                SpikeLog.Level.OK -> "[OK] "
                SpikeLog.Level.NG -> "[NG] "
                SpikeLog.Level.WARN -> "[WARN] "
                SpikeLog.Level.INFO -> ""
            }
            textLog.append("$prefix$message\n")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        harness = RecognitionHarness(applicationContext)
        textLog = findViewById(R.id.text_log)
        textResult = findViewById(R.id.text_result)

        SpikeLog.sink = logSink

        val envText = "Build.MODEL=${Build.MODEL} / Build.MANUFACTURER=${Build.MANUFACTURER} / " +
            "SDK_INT=${Build.VERSION.SDK_INT} / FINGERPRINT=${Build.FINGERPRINT}"
        findViewById<TextView>(R.id.text_env).text = envText
        SpikeLog.info("環境情報: $envText")

        if (!ErrorMapping.deviceApiLevelSupported(Build.VERSION.SDK_INT)) {
            SpikeLog.ng("SDK_INT=${Build.VERSION.SDK_INT} は minSdk 31 未満相当。DeviceUnsupported。")
        }

        findViewById<Button>(R.id.btn_check_basic).setOnClickListener { onCheckBasicStatus() }
        findViewById<Button>(R.id.btn_run_basic).setOnClickListener { onRunBasicRecognition() }
        findViewById<Button>(R.id.btn_run_advanced).setOnClickListener { onRunAdvancedFallbackCheck() }
        findViewById<Button>(R.id.btn_cancel).setOnClickListener { onCancel() }
    }

    /** Issue #11: MODE_BASIC + ja-JP の checkStatus() のみを確認する (認識は実行しない)。 */
    private fun onCheckBasicStatus() {
        scope.launch {
            SpikeLog.info("=== Basic 状態確認開始 ===")
            try {
                val options = withContext(Dispatchers.Default) {
                    com.google.mlkit.genai.speechrecognition.speechRecognizerOptions {
                        locale = java.util.Locale.forLanguageTag(targetLocale)
                        preferredMode = SpeechRecognizerOptions.Mode.MODE_BASIC
                    }
                }
                val recognizer = com.google.mlkit.genai.speechrecognition.SpeechRecognition.getClient(options)
                val status = recognizer.checkStatus()
                SpikeLog.info("checkStatus() = ${ErrorMapping.featureStatusName(status)}")
                textResult.text = "Basic checkStatus() = ${ErrorMapping.featureStatusName(status)}"
                recognizer.close()
            } catch (e: Exception) {
                SpikeLog.ng("Basic 状態確認で例外: ${e.javaClass.simpleName}: ${e.message}")
                textResult.text = "エラー: ${e.message}"
            }
            SpikeLog.info("=== Basic 状態確認終了 ===")
        }
    }

    /** Issue #11 + #13: PFDパイプ + 実時間ポンプ経由で Basic + ja-JP 認識を実行し、包含率を判定する。 */
    private fun onRunBasicRecognition() {
        scope.launch {
            SpikeLog.info("=== Basic 認識実行開始 (clip=$targetClipId) ===")
            try {
                val clip = withContext(Dispatchers.IO) {
                    BaselineAssets.loadClip(applicationContext, targetClipId)
                }
                val result = harness.runRecognition(
                    locale = clip.locale,
                    mode = SpeechRecognizerOptions.Mode.MODE_BASIC,
                    clipId = targetClipId,
                )
                reportSessionResult("Basic", clip, result)
            } catch (e: Exception) {
                SpikeLog.ng("Basic 認識実行で例外: ${e.javaClass.simpleName}: ${e.message}")
                textResult.text = "エラー: ${e.message}"
            }
            SpikeLog.info("=== Basic 認識実行終了 ===")
        }
    }

    /** Issue #12: Advanced 指定時のフォールバック挙動確認 + Basic 手動リトライ。 */
    private fun onRunAdvancedFallbackCheck() {
        scope.launch {
            SpikeLog.info("=== Advanced フォールバック検証開始 (clip=$targetClipId) ===")
            try {
                val clip = withContext(Dispatchers.IO) {
                    BaselineAssets.loadClip(applicationContext, targetClipId)
                }
                val result = harness.runAdvancedFallbackCheck(clip.locale, targetClipId)
                SpikeLog.info("--- Advanced経路の包含率評価 ---")
                reportSessionResult("Advanced", clip, result.advanced)
                SpikeLog.info("--- Basic手動リトライ経路の包含率評価 ---")
                reportSessionResult("BasicRetry", clip, result.basicRetry)
            } catch (e: Exception) {
                SpikeLog.ng("Advanced フォールバック検証で例外: ${e.javaClass.simpleName}: ${e.message}")
                textResult.text = "エラー: ${e.message}"
            }
            SpikeLog.info("=== Advanced フォールバック検証終了 ===")
        }
    }

    private fun onCancel() {
        scope.launch {
            harness.cancelActiveSession()
        }
    }

    override fun onDestroy() {
        // Activity破棄後も残る子コルーチンが旧textResult/textLogへ書き込み続けないよう、
        // superより先にscopeをキャンセルする (design.md記載の破棄処理とは別に、CodeRabbit指摘対応)。
        scope.cancel()
        // 画面回転時は新しいActivityのonCreate()が既にSpikeLog.sinkを自分のlogSinkへ
        // 上書き済みのため、無条件にnullを代入すると新Activityのログ出力を壊す。
        // 自分が設定したsinkのときだけnullに戻す。
        if (SpikeLog.sink === logSink) {
            SpikeLog.sink = null
        }
        super.onDestroy()
    }

    private fun reportSessionResult(label: String, clip: BaselineClip, result: RecognitionHarness.SessionResult) {
        if (!result.accepted) {
            SpikeLog.ng("$label: 受理不成立。error=${result.error}")
            textResult.text = "$label: 受理不成立"
            return
        }
        val text = result.finalText ?: result.partials.lastOrNull() ?: ""
        if (text.isEmpty()) {
            SpikeLog.warn("$label: 受理は成立したが最終/部分テキストが空。")
            textResult.text = "$label: 受理成立だがテキスト空"
            return
        }
        val score = KeywordScoring.score(clip.locale, clip.keywords, text)
        textResult.text = "$label: ${score.matched.size}/${clip.keywords.size} = " +
            "${"%.1f".format(score.ratePercent)}% → ${score.verdict.label} " +
            "(pumpBytes=${result.pumpBytesSent}, firstResponseMs=${result.firstResponseLatencyMs})"
    }
}
