import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:offline_stt_platform_interface/offline_stt_platform_interface.dart';

import 'download_consent_dialog.dart';
import 'object_url.dart';
import 'transcribe_error_messages.dart';

/// `offline_stt` の参照実装画面(design.md §7、requirements.md §8)。
///
/// 正しい使い方として示す一連の流れ:
/// 1. ファイルピッカーで音声ファイルを選択する(ユーザー操作起点。
///    requirements.md §8「Webではユーザー操作起点でなければならない」)
/// 2. `checkModel(locale)` でモデル状態を表示する(FR-1)
/// 3. `downloadable` であれば同意ダイアログを経てから `downloadModel()`
///    を呼び、完了後に再度 `checkModel()` で状態を確認する
///    (design.md §3「内部で暗黙ダウンロードしない」)
/// 4. `available` になって初めて `transcribeFile()` を呼び、partial/final
///    結果を逐次表示する
/// 5. 実行中はキャンセル可能にし、同時に2本目を開始できないようUIでも
///    ガードする(design.md §3「同時セッションは1本のみ」)
/// 6. `TranscribeException` の各サブクラスを区別してエラーを表示する
///    (`transcribe_error_messages.dart` 参照)
class OfflineSttHomePage extends StatefulWidget {
  const OfflineSttHomePage({super.key});

  @override
  State<OfflineSttHomePage> createState() => _OfflineSttHomePageState();
}

class _OfflineSttHomePageState extends State<OfflineSttHomePage> {
  final _localeController = TextEditingController(text: 'ja-JP');

  ModelState? _modelState;
  bool _checkingModel = false;
  String? _modelCheckError;

  PlatformFile? _selectedFile;
  String? _selectedRequestPath; // 非Web: 実ファイルパス。Web: Blob URL。
  String? _objectUrlToRevoke; // Webでのみ使用。破棄時にrevokeするため保持。

  bool _downloading = false;
  DownloadProgress? _lastDownloadProgress;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  // playbackRateはWeb専用オプション(design.md §2.2・§7)。他プラット
  // フォームでは値を渡しても無視される。UIでもWebでのみ操作可能にする。
  double _playbackRate = 1.0;

  bool _transcribing = false;
  StreamSubscription<TranscriptSegment>? _transcribeSubscription;
  final List<TranscriptSegment> _segments = [];
  String? _transcribeError;

  @override
  void initState() {
    super.initState();
    unawaited(_checkModel());
  }

  @override
  void dispose() {
    _localeController.dispose();
    unawaited(_downloadSubscription?.cancel());
    unawaited(_transcribeSubscription?.cancel());
    _revokeSelectedObjectUrlIfNeeded();
    super.dispose();
  }

  bool get _busy => _checkingModel || _downloading || _transcribing;

  Future<void> _checkModel() async {
    final locale = _localeController.text.trim();
    if (locale.isEmpty) return;
    setState(() {
      _checkingModel = true;
      _modelCheckError = null;
    });
    try {
      final state = await OfflineTranscriberPlatform.instance.checkModel(
        locale,
      );
      if (!mounted) return;
      setState(() {
        _modelState = state;
        _checkingModel = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelState = null;
        _modelCheckError = describeTranscribeError(e);
        _checkingModel = false;
      });
    }
  }

  Future<void> _pickFile() async {
    // requirements.md §8: Webでのファイル選択はユーザー操作起点でなければ
    // ならない。この関数はボタンの onPressed から直接(awaitを挟まず)
    // 呼び出されているため、その制約を満たしている。
    //
    // file_picker 13.x の `pickFile()` はキャンセル時に `null` を返す
    // (単一ファイル向けAPI。複数選択したい場合は `pickFiles()` を使う)。
    final PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        type: FileType.custom,
        // FR-4が挙げる一般的な音声ファイル形式(design.md §4.4も参照)。
        allowedExtensions: ['wav', 'm4a', 'mp3', 'aac'],
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _transcribeError = describeTranscribeError(e));
      return;
    }
    if (file == null) return;

    _revokeSelectedObjectUrlIfNeeded();

    String requestPath;
    String? objectUrl;
    if (kIsWeb) {
      final Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _transcribeError =
              'ファイルの読み込みに失敗した: '
              '${describeTranscribeError(e)}';
        });
        return;
      }
      // design.md §2.2: Webでは TranscribeRequest.path にBlob URL /
      // ObjectURLを渡す。
      objectUrl = createObjectUrlFromBytes(
        bytes,
        mimeType: _guessMimeType(file.extension),
      );
      requestPath = objectUrl;
    } else {
      final filePath = file.path;
      if (filePath == null) {
        if (!mounted) return;
        setState(() => _transcribeError = 'ファイルパスが取得できない。');
        return;
      }
      requestPath = filePath;
    }

    setState(() {
      _selectedFile = file;
      _selectedRequestPath = requestPath;
      _objectUrlToRevoke = objectUrl;
      _segments.clear();
      _transcribeError = null;
    });
  }

  String _guessMimeType(String? extension) {
    return switch (extension?.toLowerCase()) {
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      _ => 'application/octet-stream',
    };
  }

  void _revokeSelectedObjectUrlIfNeeded() {
    final url = _objectUrlToRevoke;
    if (url != null && kIsWeb) {
      revokeObjectUrl(url);
    }
    _objectUrlToRevoke = null;
  }

  Future<void> _startDownload() async {
    final locale = _localeController.text.trim();
    // 最重要: 同意なしに downloadModel() を呼んではならない
    // (requirements.md FR-2・§8)。
    final agreed = await showDownloadConsentDialog(context, locale: locale);
    if (!agreed || !mounted) return;

    setState(() {
      _downloading = true;
      _lastDownloadProgress = null;
      _modelCheckError = null;
    });

    final completer = Completer<void>();
    _downloadSubscription = OfflineTranscriberPlatform.instance
        .downloadModel(locale)
        .listen(
          (progress) {
            if (!mounted) return;
            setState(() => _lastDownloadProgress = progress);
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _downloading = false;
                _modelCheckError = describeTranscribeError(error);
              });
            }
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );
    await completer.future;
    if (!mounted) return;
    setState(() => _downloading = false);
    // design.md §3の状態遷移(downloadable → downloading → available)の
    // とおり、ダウンロード完了後は再度 checkModel() で状態を確認する。
    await _checkModel();
  }

  Future<void> _startTranscription() async {
    final path = _selectedRequestPath;
    if (path == null || _transcribing) return;

    final locale = _localeController.text.trim();
    final TranscribeRequest request;
    try {
      request = TranscribeRequest(
        path: path,
        locale: locale,
        playbackRate: kIsWeb ? _playbackRate : 1.0,
      );
    } on ArgumentError catch (e) {
      setState(() => _transcribeError = '不正なパラメータを指定した: $e');
      return;
    }

    setState(() {
      _transcribing = true;
      _segments.clear();
      _transcribeError = null;
    });

    final Stream<TranscriptSegment> stream;
    try {
      // transcribeFile()の呼び出し自体(Streamオブジェクトの生成)は
      // 未実装プラットフォーム(Android/Windows、M3/M4で実装予定)では
      // 同期的に UnimplementedError を送出しうるため、ここもtry/catchで
      // 捕捉する。
      stream = OfflineTranscriberPlatform.instance.transcribeFile(request);
    } catch (e) {
      setState(() {
        _transcribing = false;
        _transcribeError = describeTranscribeError(e);
      });
      return;
    }

    _transcribeSubscription = stream.listen(
      (segment) {
        if (!mounted) return;
        setState(() => _segments.add(segment));
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _transcribing = false;
          // design.md §3の細則2: 2本目が拒否された場合もStateErrorが
          // ここへStreamエラーとして届く。他の TranscribeException 各種も
          // 同様にここで一元的にハンドルする。
          _transcribeError = describeTranscribeError(error);
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _transcribing = false);
      },
    );
  }

  Future<void> _cancelTranscription() async {
    // Streamのcancelで下層の認識セッションを停止する(requirements.md
    // FR-3「キャンセル可能であること」)。
    await _transcribeSubscription?.cancel();
    if (!mounted) return;
    setState(() => _transcribing = false);
  }

  String _modelStateLabel(ModelState state) {
    return switch (state) {
      ModelState.available => '利用可能',
      ModelState.downloadable => 'ダウンロード可能',
      ModelState.downloading => 'ダウンロード中',
      ModelState.unavailable => '利用不可',
    };
  }

  Color _modelStateColor(ModelState state) {
    return switch (state) {
      ModelState.available => Colors.green,
      ModelState.downloadable => Colors.orange,
      ModelState.downloading => Colors.blue,
      ModelState.unavailable => Colors.red,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _modelState;

    return Scaffold(
      appBar: AppBar(title: const Text('offline_stt example')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildPlatformNoticeCard(theme),
            const SizedBox(height: 16),
            _buildLocaleSection(theme),
            const SizedBox(height: 16),
            _buildModelStateSection(theme, state),
            const SizedBox(height: 16),
            _buildFilePickerSection(theme),
            const SizedBox(height: 16),
            _buildPlaybackRateSection(theme),
            const SizedBox(height: 16),
            _buildTranscribeSection(theme, state),
            const SizedBox(height: 16),
            _buildTranscriptSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformNoticeCard(ThemeData theme) {
    // requirements.md §8・design.md §4.2: iOSシミュレータでは
    // SpeechTranscriber.isAvailableがfalseになり認識自体が利用できない
    // (実機が必須)。Android/Windowsはまだ未実装(M3/M4、design.md §4.3・
    // §4.4)。example appがクラッシュせず、その旨を表示する。
    final notices = <String>[];
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      notices.add(
        'iOSシミュレータではSpeechAnalyzerによる認識自体が利用できない'
        '(isAvailableがfalseになる)。文字起こしのE2E検証には実機が必要'
        'である(design.md §4.2)。',
      );
    }
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.windows)) {
      notices.add(
        'このプラットフォーム(${defaultTargetPlatform.name})の実装は'
        'まだ提供されていない。checkModel等はUnimplementedErrorを返す'
        '(design.md §4.3・§4.4、M3/M4で実装予定)。',
      );
    }
    if (kIsWeb) {
      notices.add(
        'Web版はChrome 142以上でのみ動作する。Chrome以外のブラウザでは'
        'モデル状態が「利用不可」になる(requirements.md §8)。',
      );
    }
    if (notices.isEmpty) return const SizedBox.shrink();
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('プラットフォームに関する注意', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final notice in notices)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(notice, style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocaleSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ロケール(BCP-47)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _localeController,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '例: ja-JP',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _checkModel,
                  child: _checkingModel
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('状態を確認'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  label: const Text('ja-JP'),
                  onPressed: _busy
                      ? null
                      : () {
                          _localeController.text = 'ja-JP';
                          unawaited(_checkModel());
                        },
                ),
                ActionChip(
                  label: const Text('en-US'),
                  onPressed: _busy
                      ? null
                      : () {
                          _localeController.text = 'en-US';
                          unawaited(_checkModel());
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelStateSection(ThemeData theme, ModelState? state) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('モデル状態(checkModel）', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (state != null)
              Chip(
                label: Text(_modelStateLabel(state)),
                backgroundColor: _modelStateColor(
                  state,
                ).withValues(alpha: 0.15),
                labelStyle: TextStyle(color: _modelStateColor(state)),
              )
            else if (_modelCheckError == null)
              const Text('未確認'),
            if (_modelCheckError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _modelCheckError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            // design.md §3の細則3: downloadModel()の状態変化は呼び出し
            // 時点で即座に確定する。ここでは downloadable のときのみ
            // ダウンロードボタン(同意ダイアログ経由)を出す。
            if (state == ModelState.downloadable) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _startDownload,
                icon: const Icon(Icons.download),
                label: const Text('音声認識モデルをダウンロード'),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _lastDownloadProgress?.fraction),
              const SizedBox(height: 4),
              Text(
                _lastDownloadProgress?.fraction != null
                    ? 'ダウンロード中: '
                          '${((_lastDownloadProgress!.fraction!) * 100).toStringAsFixed(0)}%'
                    : 'ダウンロード中(不定進捗。design.md §4.1/§4.4を参照)',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilePickerSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('音声ファイル', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              // ボタンのonPressedから直接呼ぶことで、Webでのユーザー操作
              // 起点の制約(requirements.md §8)を満たす。
              onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.audio_file),
              label: const Text('音声ファイルを選択(wav/m4a/mp3/aac)'),
            ),
            if (_selectedFile != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('選択中: ${_selectedFile!.name}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaybackRateSection(ThemeData theme) {
    // design.md §2.2「playbackRateはWeb専用オプション。他プラットフォーム
    // では無視される」。UI上でもWebでのみ操作可能にし、それ以外では
    // 無効である旨を示す(タスク指示の要件どおり)。
    if (!kIsWeb) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '再生速度(playbackRate)はWeb専用オプションであり、'
            'このプラットフォームでは指定しても無視される'
            '(design.md §2.2・§7)。',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '再生速度(playbackRate): ${_playbackRate.toStringAsFixed(2)}x',
              style: theme.textTheme.titleSmall,
            ),
            Slider(
              value: _playbackRate,
              min: 1.0,
              max: 2.0,
              divisions: 4,
              label: '${_playbackRate.toStringAsFixed(2)}x',
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _playbackRate = value),
            ),
            Text(
              '速度を上げるほど所要時間は短くなるが、ピッチも同倍率で'
              '変化するため認識精度が低下しうる'
              '(design.md §7実測: 1.0x 66.7% → 1.5x 50.0% → 2.0x 33.3%)。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscribeSection(ThemeData theme, ModelState? state) {
    final canStart =
        !_busy && state == ModelState.available && _selectedRequestPath != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文字起こし', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  // design.md §3: 同時セッションは1本のみ。実行中は
                  // ボタンを無効化して2本目の開始をUI側でも防ぐ
                  // (下層はStateErrorで拒否するが、正しい使い方を示す
                  // ためUIでもガードする)。
                  onPressed: canStart ? _startTranscription : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('文字起こし開始'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _transcribing ? _cancelTranscription : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('キャンセル'),
                ),
              ],
            ),
            if (state != ModelState.available)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'モデルが利用可能になるまで文字起こしは開始できない'
                  '(checkModel() が available 以外の場合、transcribeFile() は'
                  'ModelUnavailableExceptionを返す契約である。design.md §3)。',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (_transcribing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            if (_transcribeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _transcribeError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranscriptSection(ThemeData theme) {
    final finalText = _segments
        .where((s) => s.isFinal)
        .map((s) => s.text)
        .join(' ');
    final lastPartial = _segments.isNotEmpty && !_segments.last.isFinal
        ? _segments.last.text
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文字起こし結果', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (lastPartial != null) ...[
              Text('認識中(partial)', style: theme.textTheme.labelSmall),
              Text(lastPartial, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
            ],
            Text('確定結果(final)', style: theme.textTheme.labelSmall),
            SelectableText(
              finalText.isEmpty ? '(まだ確定結果がない)' : finalText,
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}
