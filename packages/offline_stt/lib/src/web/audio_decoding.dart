import 'dart:js_interop';

import '../common.dart';
import 'package:web/web.dart' as web;

/// デコード層(design.md §4.1、Issue #27)。
///
/// パイプライン: `path`(Blob URL / ObjectURL)→ `fetch` → `ArrayBuffer` →
/// `AudioContext.decodeAudioData` → `AudioBuffer` → `AudioBufferSourceNode`
/// → `MediaStreamAudioDestinationNode` → `audioTrack`。
///
/// このファイルはブラウザAPIを直接叩く層であるため単体テストを書かない
/// (テスト方針は `speech_recognition_js.dart` 冒頭コメントと同じ)。

/// [buildAudioTrack] が返す一式。
///
/// **重要(GC対策)**: `destination` / `stream` への参照を、認識セッションが
/// 終わるまで呼び出し側が保持し続けること。これらをローカル変数のまま
/// 破棄して到達不能にすると、GCにより `MediaStreamAudioDestinationNode` が
/// 回収され、それに伴い `audioTrack` が終了(ended)状態になり、認識が
/// "aborted" で即座に中断する。design.md自体にはこの注意点の明記が無いが、
/// spikes/web/spike.js のレビューで判明した実バグであり、Web実装では必須の
/// 対応である。このクラスにフィールドとして保持させることで、
/// [DecodedAudioTrack] インスタンスが生きている限りGCされないようにする。
class DecodedAudioTrack {
  /// 4つのノードをまとめて受け取り、認識セッションが終わるまで生存させる
  /// のがこのコンストラクタの目的である(クラスのdocコメントのGC対策参照)。
  DecodedAudioTrack({
    required this.source,
    required this.destination,
    required this.stream,
    required this.audioTrack,
  });

  /// デコード済み `AudioBuffer` の再生ノード。再生開始(`start()`)と
  /// 停止(`stop()`)、および `playbackRate` の設定先である。
  final web.AudioBufferSourceNode source;

  /// [source] の接続先。GC対策のため保持する(クラスのdocコメント参照)。
  final web.MediaStreamAudioDestinationNode destination;

  /// [destination] が生成したストリーム。GC対策のため保持する。
  final web.MediaStream stream;

  /// `SpeechRecognition.start(audioTrack)` に渡す音声トラック。
  /// [stream] の唯一の音声トラックである。
  final web.MediaStreamTrack audioTrack;
}

/// `path`(Blob URL / ObjectURL)を取得し `AudioBuffer` にデコードする。
///
/// `decodeAudioData` がrejectした場合は [DecodeFailedException] に写像する
/// (design.md §5「DecodeFailed: decodeAudioData reject」)。`fetch` 自体が
/// 失敗した場合(不正なBlob URL等)も同様にデコード不能として扱う。
Future<web.AudioBuffer> fetchAndDecode(
  web.AudioContext audioContext,
  String path,
) async {
  final JSArrayBuffer arrayBuffer;
  try {
    final response = await web.window.fetch(path.toJS).toDart;
    arrayBuffer = await response.arrayBuffer().toDart;
  } on Object {
    // design.md §4.1のパイプラインは「path → fetch → ArrayBuffer」であり、
    // ここでの失敗もファイルを音声データとして得られなかったという点で
    // decodeAudioData失敗と本質的に同じ状況である。
    throw const DecodeFailedException();
  }
  try {
    return await audioContext.decodeAudioData(arrayBuffer).toDart;
  } on Object {
    throw const DecodeFailedException();
  }
}

/// [audioBuffer] から [DecodedAudioTrack] を構築する。
///
/// [playbackRate] は `AudioBufferSourceNode.playbackRate` にそのまま設定する
/// (design.md §2.2 `TranscribeRequest.playbackRate`、§4.1)。**注意:
/// Web Audioにピッチ保持のタイムストレッチは無いため、1.0以外を指定すると
/// ピッチも同倍率で変化する。** design.md §4.1・§7実測のとおり、速度を
/// 上げるほど認識精度が低下しうる。
DecodedAudioTrack buildAudioTrack(
  web.AudioContext audioContext,
  web.AudioBuffer audioBuffer,
  double playbackRate,
) {
  final source = audioContext.createBufferSource();
  source.buffer = audioBuffer;
  source.playbackRate.value = playbackRate;

  final destination = audioContext.createMediaStreamDestination();
  source.connect(destination);

  final stream = destination.stream;
  final tracks = stream.getAudioTracks();
  if (tracks.length == 0) {
    // MediaStreamAudioDestinationNodeは仕様上必ず1本の音声トラックを持つ。
    // 0本という状況は想定外であり、デコード/合成のいずれかが実質的に
    // 失敗しているとみなす。
    throw const DecodeFailedException();
  }

  return DecodedAudioTrack(
    source: source,
    destination: destination,
    stream: stream,
    audioTrack: tracks[0],
  );
}
