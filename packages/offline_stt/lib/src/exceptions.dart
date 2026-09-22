/// `offline_stt` が送出する例外の基底型(design.md §2.2)。
///
/// requirements.md FR-6 の共通エラー型をそのまま例外階層として実装した
/// ものである。sealed class とすることで、利用者はswitch式・switch文で
/// 網羅的に分岐できる。
sealed class TranscribeException implements Exception {
  const TranscribeException();
}

/// モデルが利用できない状態で `transcribeFile()` が呼ばれた場合に送出される。
///
/// design.md §3 のとおり、`transcribeFile()` は `checkModel()` が
/// `ModelState.available` 以外を返す状態では即座にこの例外をStreamエラー
/// として返す。内部で暗黙的にダウンロードを開始することはない(ダウン
/// ロード同意UXをライブラリ利用者側に強制するため)。
class ModelUnavailableException extends TranscribeException {
  /// 付随情報を持たない例外であるため `const` コンストラクタとし、
  /// 送出側は常に同一インスタンスを使い回す(`const ModelUnavailableException()`)。
  const ModelUnavailableException();

  @override
  String toString() => 'ModelUnavailableException';
}

/// 指定されたロケールにOS/ブラウザが対応していない場合に送出される。
class LocaleUnsupportedException extends TranscribeException {
  /// 付随情報を持たない例外であるため `const` コンストラクタとし、
  /// 送出側は常に同一インスタンスを使い回す(`const LocaleUnsupportedException()`)。
  const LocaleUnsupportedException();

  @override
  String toString() => 'LocaleUnsupportedException';
}

/// 音声ファイルのデコードに失敗した場合に送出される。
class DecodeFailedException extends TranscribeException {
  /// 付随情報を持たない例外であるため `const` コンストラクタとし、
  /// 送出側は常に同一インスタンスを使い回す(`const DecodeFailedException()`)。
  const DecodeFailedException();

  @override
  String toString() => 'DecodeFailedException';
}

/// 端末・OSが機能自体に対応していない場合に送出される。
///
/// 例: Androidのブートローダーアンロック端末(design.md §4.3)。
class DeviceUnsupportedException extends TranscribeException {
  /// 付随情報を持たない例外であるため `const` コンストラクタとし、
  /// 送出側は常に同一インスタンスを使い回す(`const DeviceUnsupportedException()`)。
  const DeviceUnsupportedException();

  @override
  String toString() => 'DeviceUnsupportedException';
}

/// 文字起こし・ダウンロードがキャンセルされた場合に送出される。
class CancelledException extends TranscribeException {
  /// 付随情報を持たない例外であるため `const` コンストラクタとし、
  /// 送出側は常に同一インスタンスを使い回す(`const CancelledException()`)。
  const CancelledException();

  @override
  String toString() => 'CancelledException';
}

/// 上記のいずれにも分類できないプラットフォーム固有のエラー。
///
/// クラス名の末尾アンダースコアは design.md §2.2 の命名をそのまま採用した
/// ものである。`package:flutter/services.dart` が同名の `PlatformException`
/// を既に定義しており、両方のクラスを同一スコープでインポートした場合に
/// 名前が衝突するため、これを避ける目的でこの名前が選ばれている。
// design.md §2.2 の命名をそのまま採用しているため、慣習的なUpperCamelCase
// からの逸脱を意図的に許容する(理由は上記docコメントを参照)。
// ignore: camel_case_types
class PlatformException_ extends TranscribeException {
  /// [code] にはプラットフォーム側のエラーコードをそのまま入れる。
  /// design.md §2.2 の共通分類へ丸めずに元の値を保持することが、
  /// この型の存在意義である(requirements.md FR-6)。
  const PlatformException_({required this.code, this.message});

  /// プラットフォーム側のエラーコード。
  final String code;

  /// プラットフォーム側のエラーメッセージ(存在する場合)。
  final String? message;

  /// 値等価。
  ///
  /// この型はプラットフォームチャネル越しのエラーコードから毎回新しく
  /// 生成されるため、同じエラーでもインスタンスは常に別物になる。
  /// 同一性比較では一致しようがないため、値等価を定義している。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlatformException_ &&
        other.code == code &&
        other.message == message;
  }

  /// `==` を上書きしたため対で上書きする(Dartの等価契約)。
  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'PlatformException_(code: $code, message: $message)';
}
