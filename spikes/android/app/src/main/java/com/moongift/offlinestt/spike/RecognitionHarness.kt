package com.moongift.offlinestt.spike

import android.content.Context
import android.os.ParcelFileDescriptor
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.common.audio.AudioSource
import com.google.mlkit.genai.speechrecognition.SpeechRecognition
import com.google.mlkit.genai.speechrecognition.SpeechRecognizer
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerResponse
import com.google.mlkit.genai.speechrecognition.speechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.speechRecognizerRequest
import java.util.Locale
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Issue #11 (MODE_BASIC + ja-JP)、#12 (MODE_ADVANCED フォールバック)、#13 (PFDパイプ + 実時間ポンプ)
 * の実行ロジック本体。design.md §4.3 のパイプライン (デコード→PFDパイプ→実時間ポンプ→
 * AudioSource.fromPfd()→SpeechRecognizer.startRecognition()) のうち、デコード部分は Issue #13
 * の指示により「事前生成の16kHzモノラル16-bit raw PCM」(= 基準wavのヘッダを飛ばして読んだもの)
 * に固定し、パイプ+ポンプ+fromPfd()の受理可否とMODE挙動の検証に集中する。
 *
 * フォールバック処理は書かない: 想定外の状態はすべて例外またはログとして顕在化させる。
 */
class RecognitionHarness(private val context: Context) {

    /** 受理成立の判定基準 (Issue #13 の指示に基づき、本スパイクで明確に定義する):
     *  1. `AudioSource.fromPfd()` が例外を投げずにソースを生成できる
     *  2. `startRecognition()` が Flow を返し、collect が例外なく開始する
     *  3. [firstResponseTimeoutMs] 以内に、最初の応答 (partial/final/completed のいずれか) または
     *     エラー (ErrorResponse か Flow 例外) が到達する
     *  上記すべてを満たした場合のみ `accepted = true` とする。
     */
    data class SessionResult(
        val accepted: Boolean,
        val mode: Int,
        val featureStatusBefore: Int,
        val featureStatusAfterDownload: Int?,
        val partials: List<String>,
        val finalText: String?,
        val completed: Boolean,
        val error: GenAiException?,
        val pumpBytesSent: Int,
        val pumpElapsedMs: Long,
        val firstResponseLatencyMs: Long?,
    )

    /** cancel() 対象になる、実行中セッションのハンドル。 */
    private class ActiveSession(
        val recognizer: SpeechRecognizer,
        val readSide: ParcelFileDescriptor,
        val writeSide: ParcelFileDescriptor,
        val pumpJob: Job,
        val collectJob: Job,
    )

    @Volatile
    private var active: ActiveSession? = null

    /** 認識処理の重複起動防止用ガード。キューには積まず、実行中の追加起動は拒否する。 */
    private val launchGuard = AtomicBoolean(false)

    fun modeLabel(mode: Int): String = when (mode) {
        SpeechRecognizerOptions.Mode.MODE_BASIC -> "MODE_BASIC"
        SpeechRecognizerOptions.Mode.MODE_ADVANCED -> "MODE_ADVANCED"
        else -> "UNKNOWN_MODE($mode)"
    }

    /**
     * checkStatus() → 必要ならdownload() → PFDパイプ+実時間ポンプ → startRecognition() の
     * 一連の流れを実行する (Issue #11 / #13 共通の中核パス)。
     *
     * 重複起動防止: 実行中に追加で呼ばれた場合はキューに積まず、起動を拒否する
     * ([launchGuard] 参照。1セッションのみ許可)。
     */
    suspend fun runRecognition(
        locale: String,
        mode: Int,
        clipId: String,
        firstResponseTimeoutMs: Long = 20_000,
        joinTimeoutMs: Long = 5_000,
    ): SessionResult {
        if (!launchGuard.compareAndSet(false, true)) {
            SpikeLog.warn(
                "runRecognition(): 別セッションが実行中のため起動を拒否した " +
                    "(mode=${modeLabel(mode)}, clip=$clipId)。"
            )
            return SessionResult(
                accepted = false,
                mode = mode,
                featureStatusBefore = -1,
                featureStatusAfterDownload = null,
                partials = emptyList(),
                finalText = null,
                completed = false,
                error = null,
                pumpBytesSent = 0,
                pumpElapsedMs = 0,
                firstResponseLatencyMs = null,
            )
        }
        try {
            return runRecognitionLocked(locale, mode, clipId, firstResponseTimeoutMs, joinTimeoutMs)
        } finally {
            launchGuard.set(false)
        }
    }

    private suspend fun runRecognitionLocked(
        locale: String,
        mode: Int,
        clipId: String,
        firstResponseTimeoutMs: Long,
        joinTimeoutMs: Long,
    ): SessionResult = coroutineScope {
        SpikeLog.info("=== runRecognition開始: locale=$locale mode=${modeLabel(mode)} clip=$clipId ===")

        val options = speechRecognizerOptions {
            this.locale = Locale.forLanguageTag(locale)
            this.preferredMode = mode
        }
        val recognizer = SpeechRecognition.getClient(options)

        val statusBefore = recognizer.checkStatus()
        SpikeLog.info("checkStatus() 初回 = ${ErrorMapping.featureStatusName(statusBefore)}")
        ErrorMapping.classifyFeatureStatus(statusBefore)?.let {
            SpikeLog.ng("checkStatus() が $it 相当を示した (${ErrorMapping.featureStatusName(statusBefore)})。")
        }

        var statusAfterDownload: Int? = null
        if (statusBefore == FeatureStatus.DOWNLOADABLE) {
            SpikeLog.info("モデルが downloadable のため download() を実行する (暗黙のバックグラウンドダウンロードはしない: design.md §3)。")
            var downloadFailure: GenAiException? = null
            recognizer.download().collect { ds ->
                when (ds) {
                    is DownloadStatus.DownloadStarted ->
                        SpikeLog.info("DownloadStarted: bytesToDownload=${ds.bytesToDownload}")
                    is DownloadStatus.DownloadProgress ->
                        SpikeLog.info("DownloadProgress: totalBytesDownloaded=${ds.totalBytesDownloaded}")
                    is DownloadStatus.DownloadCompleted -> SpikeLog.ok("DownloadCompleted")
                    is DownloadStatus.DownloadFailed -> {
                        downloadFailure = ds.e
                        SpikeLog.ng("DownloadFailed: ${ErrorMapping.classify(ds.e)} code=${ds.e.errorCode} message=${ds.e.message}")
                    }
                    else -> SpikeLog.warn("未知の DownloadStatus サブタイプ: $ds")
                }
            }
            if (downloadFailure != null) {
                recognizer.close()
                return@coroutineScope SessionResult(
                    accepted = false,
                    mode = mode,
                    featureStatusBefore = statusBefore,
                    featureStatusAfterDownload = null,
                    partials = emptyList(),
                    finalText = null,
                    completed = false,
                    error = downloadFailure,
                    pumpBytesSent = 0,
                    pumpElapsedMs = 0,
                    firstResponseLatencyMs = null,
                )
            }
            statusAfterDownload = recognizer.checkStatus()
            SpikeLog.info("download() 後の checkStatus() = ${ErrorMapping.featureStatusName(statusAfterDownload)}")
        }

        val effectiveStatus = statusAfterDownload ?: statusBefore
        if (effectiveStatus != FeatureStatus.AVAILABLE) {
            SpikeLog.ng(
                "checkStatus() が AVAILABLE にならなかった (${ErrorMapping.featureStatusName(effectiveStatus)})。" +
                    "認識は実行できない。"
            )
            recognizer.close()
            return@coroutineScope SessionResult(
                accepted = false,
                mode = mode,
                featureStatusBefore = statusBefore,
                featureStatusAfterDownload = statusAfterDownload,
                partials = emptyList(),
                finalText = null,
                completed = false,
                error = null,
                pumpBytesSent = 0,
                pumpElapsedMs = 0,
                firstResponseLatencyMs = null,
            )
        }

        // Issue #13: 事前生成の16kHzモノラル16-bit raw PCM に固定する。基準wavは既にこの形式
        // なので、ヘッダを飛ばして読むことで満たす (WavPcm 参照)。
        val pcm = BaselineAssets.openWav(context, clipId).use { input ->
            WavPcm.readMono16kHz16BitPcmOrThrow(input, "$clipId.wav")
        }

        SpikeLog.info("ParcelFileDescriptor.createPipe() を呼び出す。")
        val pipe = ParcelFileDescriptor.createPipe()
        val readSide = pipe[0]
        val writeSide = pipe[1]

        val audioSource = try {
            val src = AudioSource.fromPfd(readSide)
            SpikeLog.ok("AudioSource.fromPfd() 成功。")
            src
        } catch (e: Exception) {
            SpikeLog.ng("AudioSource.fromPfd() が例外を送出した: ${e.message}。受理不成立。")
            readSide.close()
            writeSide.close()
            recognizer.close()
            return@coroutineScope SessionResult(
                accepted = false,
                mode = mode,
                featureStatusBefore = statusBefore,
                featureStatusAfterDownload = statusAfterDownload,
                partials = emptyList(),
                finalText = null,
                completed = false,
                error = null,
                pumpBytesSent = 0,
                pumpElapsedMs = 0,
                firstResponseLatencyMs = null,
            )
        }

        val request = speechRecognizerRequest { this.audioSource = audioSource }

        val partials = mutableListOf<String>()
        var finalText: String? = null
        var completed = false
        var lastError: GenAiException? = null
        var firstResponseReceived = false
        var firstResponseLatencyMs: Long? = null
        val firstResponseLatch = CompletableDeferred<Unit>()
        val sessionStartNanos = System.nanoTime()

        var pumpBytesSent = 0
        var pumpElapsedMs = 0L

        val pumpJob = launch(Dispatchers.IO) {
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(writeSide).use { out ->
                    val result = RealtimePump.pump(
                        output = out,
                        pcmBytes = pcm.dataBytes,
                        sampleRateHz = pcm.sampleRate,
                        bitsPerSample = pcm.bitsPerSample,
                        channels = pcm.channels,
                    )
                    pumpBytesSent = result.totalBytesSent
                    pumpElapsedMs = result.elapsedMs
                }
            } catch (e: Exception) {
                SpikeLog.ng("実時間ポンプでエラー: ${e.message}")
            }
        }

        val collectJob = launch {
            try {
                recognizer.startRecognition(request).collect { response ->
                    if (!firstResponseReceived) {
                        firstResponseReceived = true
                        firstResponseLatencyMs = (System.nanoTime() - sessionStartNanos) / 1_000_000
                        firstResponseLatch.complete(Unit)
                    }
                    when (response) {
                        is SpeechRecognizerResponse.PartialTextResponse -> {
                            partials += response.text
                            SpikeLog.info("[partial] ${response.text}")
                        }
                        is SpeechRecognizerResponse.FinalTextResponse -> {
                            finalText = response.text
                            SpikeLog.ok("[final] ${response.text}")
                        }
                        is SpeechRecognizerResponse.CompletedResponse -> {
                            completed = true
                            SpikeLog.ok("[completed] Flow完了通知を受信した。")
                        }
                        is SpeechRecognizerResponse.ErrorResponse -> {
                            lastError = response.e
                            SpikeLog.ng(
                                "[error] ${ErrorMapping.classify(response.e)} " +
                                    "code=${response.e.errorCode} message=${response.e.message}"
                            )
                        }
                        else -> SpikeLog.warn("未知の SpeechRecognizerResponse サブタイプ: $response")
                    }
                }
            } catch (e: GenAiException) {
                lastError = e
                SpikeLog.ng("startRecognition() Flow が例外を送出した: ${ErrorMapping.classify(e)} code=${e.errorCode}")
                if (!firstResponseReceived) {
                    firstResponseReceived = true
                    firstResponseLatencyMs = (System.nanoTime() - sessionStartNanos) / 1_000_000
                    firstResponseLatch.complete(Unit)
                }
            }
        }

        val session = ActiveSession(recognizer, readSide, writeSide, pumpJob, collectJob)
        active = session

        try {
            val gotFirstResponse = withTimeoutOrNull(firstResponseTimeoutMs) {
                firstResponseLatch.await()
                true
            } ?: false

            if (!gotFirstResponse) {
                SpikeLog.ng(
                    "受理不成立: ${firstResponseTimeoutMs}ms 以内に最初の応答/エラーが到達しなかった。" +
                        "パイプ/実時間ポンプ/AudioSource.fromPfd()/startRecognition() のいずれかが" +
                        "機能していない可能性がある。"
                )
                // タイムアウト時は既存のキャンセル経路と同じ順序で停止する
                // (パイプclose → stopRecognition() → close()。design.md §4.3 参照)。
                SpikeLog.warn("=== タイムアウトによる停止経路開始: パイプclose → stopRecognition() → close() ===")
                runCatching { writeSide.close() }
                    .onFailure { SpikeLog.warn("writeSide.close() 失敗: ${it.message}") }
                runCatching { readSide.close() }
                    .onFailure { SpikeLog.warn("readSide.close() 失敗: ${it.message}") }
                pumpJob.cancelAndJoin()
                runCatching { recognizer.stopRecognition() }
                    .onFailure { SpikeLog.warn("stopRecognition() 失敗: ${it.message}") }
                collectJob.cancelAndJoin()
                SpikeLog.warn("=== タイムアウトによる停止経路完了 ===")
            } else {
                SpikeLog.ok("受理成立条件(fromPfd成功 + Flow開始 + 最初の応答/エラー到達)を満たした。")

                // 受理判定後もFlow/ポンプの完了を待ち、最終テキストとキャンセル可否検証の材料を
                // 揃えるが、無期限には待たない(上限を設ける)。
                val collectJoined = withTimeoutOrNull(joinTimeoutMs) { collectJob.join(); true } ?: false
                if (!collectJoined) {
                    SpikeLog.warn("collectJob.join() が ${joinTimeoutMs}ms 以内に完了しなかった。")
                }
                val pumpJoined = withTimeoutOrNull(joinTimeoutMs) { pumpJob.join(); true } ?: false
                if (!pumpJoined) {
                    SpikeLog.warn("pumpJob.join() が ${joinTimeoutMs}ms 以内に完了しなかった。")
                }
            }

            SpikeLog.info("=== runRecognition終了: accepted=$gotFirstResponse ===")

            SessionResult(
                accepted = gotFirstResponse,
                mode = mode,
                featureStatusBefore = statusBefore,
                featureStatusAfterDownload = statusAfterDownload,
                partials = partials,
                finalText = finalText,
                completed = completed,
                error = lastError,
                pumpBytesSent = pumpBytesSent,
                pumpElapsedMs = pumpElapsedMs,
                firstResponseLatencyMs = firstResponseLatencyMs,
            )
        } finally {
            // 例外・キャンセルを含めて recognizer と pipe の解放を保証する。
            // 自セッションに対応する場合のみ解放する(別セッションの状態を壊さない。issue #2 参照)。
            if (active === session) {
                runCatching { recognizer.close() }
                    .onFailure { SpikeLog.warn("recognizer.close() 失敗: ${it.message}") }
                runCatching { readSide.close() }
                    .onFailure { SpikeLog.warn("readSide.close() 失敗: ${it.message}") }
                runCatching { writeSide.close() }
                    .onFailure { SpikeLog.warn("writeSide.close() 失敗: ${it.message}") }
                active = null
            }
        }
    }

    /** Issue #12 (design.md §8 未決事項5) の結果一式。 */
    data class FallbackCheckResult(
        val advanced: SessionResult,
        val basicRetry: SessionResult,
    )

    /**
     * `preferredMode = MODE_ADVANCED` で生成した際の `checkStatus()` と認識可否を観察し、
     * 続けて `MODE_BASIC` での手動リトライも実行して比較できるようにする (Issue #12)。
     *
     * 注記: 「自動フォールバックが発生したかどうか」自体はクライアント側の公開APIからは判別できない
     * (`checkStatus()` の戻り値と実際に認識が成立したかどうかしか観測できない)。したがって本実装は
     * 観測事実 (checkStatus実測値、認識成立可否) のみを記録し、フォールバックの発生有無そのものの
     * 断定はしない。判定はRESULTS.mdで人が行う。
     */
    suspend fun runAdvancedFallbackCheck(locale: String, clipId: String): FallbackCheckResult {
        SpikeLog.info("=== Advancedフォールバック検証開始 (Issue #12, design.md §8 未決事項5) ===")
        SpikeLog.info(
            "自動フォールバックの発生有無はクライアントAPIから直接は判別できないため、" +
                "checkStatus()の実測値と認識可否のみを記録する。"
        )
        val advanced = runRecognition(locale, SpeechRecognizerOptions.Mode.MODE_ADVANCED, clipId)
        SpikeLog.info(
            "Advanced経路結果: accepted=${advanced.accepted}, " +
                "statusBefore=${ErrorMapping.featureStatusName(advanced.featureStatusBefore)}, " +
                "statusAfterDownload=${advanced.featureStatusAfterDownload?.let { ErrorMapping.featureStatusName(it) }}"
        )

        SpikeLog.info("--- Basic手動リトライ開始 (比較のため、Advanced経路の結果に関わらず常に実行する) ---")
        val basicRetry = runRecognition(locale, SpeechRecognizerOptions.Mode.MODE_BASIC, clipId)
        SpikeLog.info(
            "Basic手動リトライ結果: accepted=${basicRetry.accepted}, " +
                "statusBefore=${ErrorMapping.featureStatusName(basicRetry.featureStatusBefore)}"
        )

        SpikeLog.info("=== Advancedフォールバック検証終了 ===")
        return FallbackCheckResult(advanced, basicRetry)
    }

    /**
     * キャンセル経路 (design.md §4.3): パイプclose → stopRecognition() → close()。
     * 実行中セッションが無い場合はログに残すのみで何もしない (フォールバックしない = 黙って無視しない)。
     */
    suspend fun cancelActiveSession() {
        val session = active
        if (session == null) {
            SpikeLog.warn("cancelActiveSession(): 実行中のセッションが無い。")
            return
        }
        SpikeLog.warn("=== キャンセル経路開始: パイプclose → stopRecognition() → close() ===")
        runCatching { session.writeSide.close() }
            .onFailure { SpikeLog.warn("writeSide.close() 失敗: ${it.message}") }
        runCatching { session.readSide.close() }
            .onFailure { SpikeLog.warn("readSide.close() 失敗: ${it.message}") }
        session.pumpJob.cancelAndJoin()
        runCatching { session.recognizer.stopRecognition() }
            .onFailure { SpikeLog.warn("stopRecognition() 失敗: ${it.message}") }
        session.collectJob.cancelAndJoin()
        session.recognizer.close()
        active = null
        SpikeLog.ok("=== キャンセル経路完了 ===")
    }
}
