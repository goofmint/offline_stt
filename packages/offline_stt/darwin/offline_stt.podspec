#
# offline_stt.podspec — iOS/macOS共用(sharedDarwinSource)
#
Pod::Spec.new do |s|
  s.name             = 'offline_stt'
  s.version          = '0.1.0'
  s.summary          = 'offline_stt のiOS/macOS共用実装。'
  s.description      = <<-DESC
offline_stt のiOS/macOS共用実装。SpeechAnalyzer + AVFoundationによる
ファイル入力オフライン文字起こし(design.md §4.2)。
                       DESC
  s.homepage         = 'https://github.com/goofmint/offline_stt'
  # LICENSEファイルはIssue #60〜#62で整備する。それまでは型のみ指定する。
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'MOONGIFT' => 'moongift@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  # iOS と macOS で Flutter のモジュール名が異なるため、プラットフォーム別に宣言する。
  # 共通で 'Flutter' を指定すると macOS 側で依存解決とSwiftコンパイルに失敗する。
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'

  s.ios.deployment_target = '26.0'
  s.osx.deployment_target = '26.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  # Swift 5 言語モードを指定する。Swift 6 言語モード(strict concurrency)では、
  # Pigeon が生成する `var pigeonPigeonMethodCodec`(グローバル可変状態)が
  # 「is not concurrency-safe because it is nonisolated global shared mutable state」
  # としてコンパイルエラーになる。Pigeon 27.3.0 と最新の 29.0.2 のどちらでも
  # 同じコードが生成されるため、Pigeon の更新では解決しない。
  # Swift 5 モードでも async/await と actor は使えるため、design.md §4.2 の
  # SpeechAnalyzer 連携(M2)には支障がない。
  s.swift_version = '5.0'
end
