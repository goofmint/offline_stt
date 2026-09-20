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
  s.dependency 'Flutter'

  s.ios.deployment_target = '26.0'
  s.osx.deployment_target = '26.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '6.2'
end
