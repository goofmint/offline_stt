#
# offline_stt_darwin.podspec — iOS/macOS共用(sharedDarwinSource)
#
Pod::Spec.new do |s|
  s.name             = 'offline_stt_darwin'
  s.version          = '0.1.0'
  s.summary          = 'offline_stt のiOS/macOS共用実装(雛形)。'
  s.description      = <<-DESC
offline_stt のiOS/macOS共用実装。SpeechAnalyzer + AVFoundationによる
ファイル入力オフライン文字起こし(design.md §4.2)。実装はM2で行う。
                       DESC
  s.homepage         = 'https://github.com/moongift/offline_stt'
  # LICENSEファイルはIssue #60〜#62で整備する。それまでは型のみ指定する。
  s.license          = { :type => 'TBD' }
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
  s.swift_version = '6.2'
end
