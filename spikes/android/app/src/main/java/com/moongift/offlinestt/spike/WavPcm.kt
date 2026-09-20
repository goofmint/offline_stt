package com.moongift.offlinestt.spike

import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Issue #13 の指示 (design.md §4.3): PFDパイプ実時間ポンプの入力を、デコード/リサンプリングの
 * 変数から分離するため「事前生成の 16kHz モノラル 16-bit raw PCM」に固定する。本スパイクでは
 * test-assets/baseline-audio 配下の .wav ファイルが既にその形式 (jaJP_10s.json: sample_rate=16000,
 * channels=1, encoding=pcm_s16le) であることを利用し、wav のヘッダを飛ばして raw PCM を取り出す。
 *
 * 注意: test-assets/baseline-audio の wav は `fmt ` チャンクの後に `LIST/INFO` チャンクを
 * 含むため、固定 44 バイトオフセットでは data チャンクの位置を取り違える。したがって
 * 簡易 RIFF チャンクウォーカーで `data` チャンクを正しく探索する。フォールバックはしない:
 * 想定外の chunk 構造や非対応フォーマットを検出した場合は例外で明確に停止する。
 */
object WavPcm {

    data class PcmInfo(
        val sampleRate: Int,
        val channels: Int,
        val bitsPerSample: Int,
        val audioFormat: Int, // 1 = PCM
        val dataBytes: ByteArray,
    )

    /** 16kHz モノラル 16-bit PCM であることを要求する (design.md §4.3 の実時間ポンプ入力仕様)。 */
    fun readMono16kHz16BitPcmOrThrow(input: InputStream, sourceNameForLog: String): PcmInfo {
        val info = read(input, sourceNameForLog)
        if (info.audioFormat != 1) {
            throw IllegalStateException(
                "$sourceNameForLog: audioFormat=${info.audioFormat} は非対応。PCM (1) のみサポートする。"
            )
        }
        if (info.sampleRate != 16000 || info.channels != 1 || info.bitsPerSample != 16) {
            throw IllegalStateException(
                "$sourceNameForLog: 想定形式(16kHz/mono/16bit)と不一致。" +
                    "実測: sampleRate=${info.sampleRate}, channels=${info.channels}, bits=${info.bitsPerSample}。" +
                    "本スパイクはリサンプリングを行わない方針 (Issue #13 は #14 の範囲外)。"
            )
        }
        return info
    }

    private fun read(input: InputStream, sourceNameForLog: String): PcmInfo {
        val all = input.readBytes()
        SpikeLog.info("$sourceNameForLog: 読み込みバイト数=${all.size}")

        if (all.size < 12) {
            throw IllegalStateException("$sourceNameForLog: ファイルが短すぎて RIFF ヘッダを読めない。")
        }
        val buf = ByteBuffer.wrap(all).order(ByteOrder.LITTLE_ENDIAN)

        val riff = ascii(all, 0, 4)
        val wave = ascii(all, 8, 4)
        if (riff != "RIFF" || wave != "WAVE") {
            throw IllegalStateException("$sourceNameForLog: RIFF/WAVE ヘッダではない (riff=$riff, wave=$wave)。")
        }

        var pos = 12
        var sampleRate = -1
        var channels = -1
        var bitsPerSample = -1
        var audioFormat = -1
        var dataStart = -1
        var dataSize = -1

        while (pos + 8 <= all.size) {
            val chunkId = ascii(all, pos, 4)
            val chunkSize = buf.getInt(pos + 4)
            if (chunkSize < 0) {
                throw IllegalStateException("$sourceNameForLog: chunk '$chunkId' の size が不正 ($chunkSize)。")
            }
            val bodyStart = pos + 8
            when (chunkId) {
                "fmt " -> {
                    if (bodyStart + 16 > all.size) {
                        throw IllegalStateException("$sourceNameForLog: fmt チャンクが短すぎる。")
                    }
                    audioFormat = buf.getShort(bodyStart).toInt() and 0xFFFF
                    channels = buf.getShort(bodyStart + 2).toInt() and 0xFFFF
                    sampleRate = buf.getInt(bodyStart + 4)
                    bitsPerSample = buf.getShort(bodyStart + 14).toInt() and 0xFFFF
                    SpikeLog.info(
                        "$sourceNameForLog: fmt チャンク解析: audioFormat=$audioFormat, channels=$channels, " +
                            "sampleRate=$sampleRate, bitsPerSample=$bitsPerSample"
                    )
                }
                "data" -> {
                    dataStart = bodyStart
                    dataSize = chunkSize
                    SpikeLog.info("$sourceNameForLog: data チャンク検出: offset=$dataStart, size=$dataSize")
                }
                else -> {
                    SpikeLog.info("$sourceNameForLog: chunk '$chunkId' (size=$chunkSize) をスキップする。")
                }
            }
            // RIFF チャンクは奇数サイズの場合 1 バイトパディングされる。
            val advance = chunkSize + (chunkSize % 2)
            pos = bodyStart + advance
        }

        if (sampleRate <= 0 || channels <= 0 || bitsPerSample <= 0) {
            throw IllegalStateException("$sourceNameForLog: fmt チャンクが見つからなかった。")
        }
        if (dataStart < 0 || dataSize < 0) {
            throw IllegalStateException("$sourceNameForLog: data チャンクが見つからなかった。")
        }
        if (dataStart + dataSize > all.size) {
            SpikeLog.warn(
                "$sourceNameForLog: data チャンクの宣言サイズ ($dataSize) がファイル終端を超える。" +
                    "実ファイル残りバイトに切り詰める。"
            )
        }
        val actualDataEnd = minOf(dataStart + dataSize, all.size)
        val pcm = all.copyOfRange(dataStart, actualDataEnd)

        return PcmInfo(
            sampleRate = sampleRate,
            channels = channels,
            bitsPerSample = bitsPerSample,
            audioFormat = audioFormat,
            dataBytes = pcm,
        )
    }

    private fun ascii(bytes: ByteArray, offset: Int, len: Int): String {
        return String(bytes, offset, len, Charsets.US_ASCII)
    }
}
