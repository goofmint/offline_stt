'use strict';

/**
 * M0 検証スパイク: Web (Chrome オンデバイス Web Speech API)
 *
 * 対応 Issue: #3 (可用性チェック), #4 (言語パック取得),
 *             #5 (audioTrack + processLocally 併用動作), #6 (キーワード包含率評価)
 * 対応する設計: design.md §4.1 Web, §5 エラーマッピング, §7 テスト戦略/評価基準, §8 未決事項4
 *
 * このファイルはビルドツール非依存。素の ES2022 として動作する。
 * フォールバック処理は書かない。エラーは握りつぶさず必ずログへ出す。
 */

// ---------------------------------------------------------------------------
// 定数
// ---------------------------------------------------------------------------

// design.md §7 「評価基準(キーワード包含率)」由来のしきい値 (クリーン基準音声)。
// ja-JP: 95%以上で合格、90〜94%は「条件付き合格 / 要確認」の中間区分、90%未満は不成立。
// en-US: 95%以上で合格、95%未満は不成立 (design.mdに中間区分の記載なし)。
const THRESHOLDS = {
  'ja-JP': { passMin: 95, conditionalMin: 90 },
  'en-US': { passMin: 95, conditionalMin: null },
};

// onended から onend を待つ猶予時間 (ms)。これを超えたら stop() を呼んでタイムアウト扱いにする。
const ONEND_TIMEOUT_MS = 15000;

// stop() が効かず abort() まで打った後に onend を待つ猶予 (ms)。
const ABORT_GRACE_MS = 5000;

const TARGET_LOCALES = ['ja-JP', 'en-US'];

// keywords.json のクリップIDとファイル名プレフィックスの対応 (ファイル名からの自動推定に使う)
const CLIP_ID_HINTS = {
  jaJP_10s: [/ja.?jp.*10s/i, /jajp_10s/i],
  jaJP_3m: [/ja.?jp.*3m/i, /jajp_3m/i],
  enUS_10s: [/en.?us.*10s/i, /enus_10s/i],
  enUS_3m: [/en.?us.*3m/i, /enus_3m/i],
};

// ---------------------------------------------------------------------------
// グローバル状態
// ---------------------------------------------------------------------------

/** @type {Record<string, {locale: string, transcript: string, keywords: (string|string[])[]}>} */
let KEYWORDS_DB = null;

let selectedFile = null;
// install() の対象ロケール。可用性チェックや文字起こし前チェックで downloadable を
// 検出したロケールを保持する。ja-JP 固定にしないこと (en-US も検証対象のため)。
let pendingInstallLocale = 'ja-JP';
let currentSession = null; // 実行中の認識セッション制御用

// ---------------------------------------------------------------------------
// ログユーティリティ
// ---------------------------------------------------------------------------

function nowStamp() {
  const d = new Date();
  const pad = (n, l = 2) => String(n).padStart(l, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}.${pad(d.getMilliseconds(), 3)}`;
}

/**
 * 実行ログへ1行追記する。level: 'info' | 'ok' | 'ng' | 'warn'
 */
function log(message, level = 'info') {
  const el = document.getElementById('log');
  if (!el) {
    // ログ領域が無い状況 (テスト実行等) でも落ちないようにコンソールへは必ず出す
    console.log(`[${level}] ${message}`);
    return;
  }
  const line = document.createElement('div');
  line.className = `log-line log-${level}`;
  line.textContent = `[${nowStamp()}] ${message}`;
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
  const consoleFn = level === 'ng' ? console.error : level === 'warn' ? console.warn : console.log;
  consoleFn(`[spike] ${message}`);
}

function setStatus(elId, text) {
  const el = document.getElementById(elId);
  if (el) el.textContent = text;
}

// ---------------------------------------------------------------------------
// (A) 機能検出と可用性チェック (Issue #3, #4)
// ---------------------------------------------------------------------------

function getSpeechRecognitionCtor() {
  return window.SpeechRecognition ?? window.webkitSpeechRecognition ?? null;
}

function detectEnvironment() {
  const ua = navigator.userAgent;
  const isChrome = /Chrome\/(\d+)/.test(ua) && !/Edg\//.test(ua) && !/OPR\//.test(ua);
  const chromeVersionMatch = ua.match(/Chrome\/(\d+)/);
  const chromeVersion = chromeVersionMatch ? Number(chromeVersionMatch[1]) : null;

  setStatus('env-ua', ua);
  setStatus('env-protocol', location.protocol);
  setStatus(
    'env-chrome',
    isChrome ? `Chrome と判定 (バージョン ${chromeVersion ?? '不明'})` : 'Chrome ではないと判定'
  );

  log(`実行環境: UA="${ua}"`);
  log(`実行環境: protocol=${location.protocol}`);
  log(`実行環境: Chrome判定=${isChrome} (version=${chromeVersion ?? '不明'})`);

  return { ua, isChrome, chromeVersion };
}

/**
 * SpeechRecognition.available({langs, processLocally}) を1ロケール分呼び出し、
 * 結果 (もしくは例外) をそのまま返す。
 */
async function checkAvailability(SR, locale) {
  try {
    if (typeof SR.available !== 'function') {
      log(`SpeechRecognition.available が未定義 (locale=${locale})`, 'ng');
      return { locale, ok: false, errorName: 'NotDefined', errorMessage: 'SpeechRecognition.available is not a function' };
    }
    const result = await SR.available({ langs: [locale], processLocally: true });
    log(`available({langs:['${locale}'], processLocally:true}) => ${JSON.stringify(result)}`, 'ok');
    return { locale, ok: true, result };
  } catch (err) {
    // APIが未定義なのか権限拒否なのかを区別して表示する
    const name = err && err.name ? err.name : 'UnknownError';
    const message = err && err.message ? err.message : String(err);
    log(`available() 失敗 (locale=${locale}): name=${name} message=${message}`, 'ng');
    return { locale, ok: false, errorName: name, errorMessage: message };
  }
}

async function runAvailabilityCheck() {
  log('=== 可用性チェック開始 ===');
  const SR = getSpeechRecognitionCtor();
  if (!SR) {
    log('window.SpeechRecognition / window.webkitSpeechRecognition のいずれも未定義。この環境では機能検出の時点で unavailable。', 'ng');
    setStatus('availability-result', 'unavailable (API未定義)');
    document.getElementById('btn-install').disabled = true;
    return;
  }
  log('SpeechRecognition コンストラクタを検出した。');

  const results = [];
  for (const locale of TARGET_LOCALES) {
    results.push(await checkAvailability(SR, locale));
  }

  const summary = results
    .map((r) => (r.ok ? `${r.locale}=${r.result}` : `${r.locale}=ERROR(${r.errorName})`))
    .join(' / ');
  setStatus('availability-result', summary);

  // ja-JP を優先しつつ、downloadable なロケールがあれば install 対象にする。
  const installBtn = document.getElementById('btn-install');
  const downloadable = results.filter((r) => r.ok && r.result === 'downloadable');
  const target = downloadable.find((r) => r.locale === 'ja-JP') || downloadable[0];
  if (target) {
    pendingInstallLocale = target.locale;
    installBtn.disabled = false;
    installBtn.textContent = `言語パック取得 (install: ${target.locale})`;
    log(`${target.locale} が downloadable のため、言語パック取得ボタンを有効化した。`);
    if (downloadable.length > 1) {
      log(`他に downloadable なロケール: ${downloadable.filter((r) => r !== target).map((r) => r.locale).join(', ')}。` +
          'それらを使う場合は、該当ロケールの音声を選んでから文字起こしを実行すると取得を促す。');
    }
  } else {
    installBtn.disabled = true;
    const states = results.filter((r) => r.ok).map((r) => `${r.locale}=${r.result}`).join(', ');
    log(`downloadable なロケールが無い (${states}) ため、install ボタンは無効のまま。`);
  }

  log('=== 可用性チェック終了 ===');
  return results;
}

async function runInstall() {
  log('=== 言語パック取得 (install) 開始 ===');
  const SR = getSpeechRecognitionCtor();
  if (!SR) {
    log('SpeechRecognition が未定義のため install を実行できない。', 'ng');
    return;
  }
  if (typeof SR.install !== 'function') {
    log('SpeechRecognition.install が未定義。この Chrome バージョンでは未実装の可能性がある。', 'ng');
    return;
  }

  // downloadprogress 系イベントは存在が保証されないため、防御的に登録する。
  // install() は静的メソッドで EventTarget を返さない可能性があるため、
  // 進捗取得を試みる先は Promise の戻り値ではなく SR 自体/グローバルのどちらかになり得る。
  // 存在しないAPIを推測で叩かないよう、まず install() の戻り値の型を確認してからイベント登録を試みる。
  try {
    const installLocale = pendingInstallLocale;
    const installPromise = SR.install({ langs: [installLocale], processLocally: true });
    log(`SpeechRecognition.install({langs:["${installLocale}"], processLocally:true}) を呼び出した。`);

    // 戻り値がイベントを発火できるオブジェクト (addEventListener を持つ) であれば
    // downloadprogress を試験的に購読する。無ければ何もしない (フォールバックはしない、単に「無い」とログするだけ)。
    if (installPromise && typeof installPromise.addEventListener === 'function') {
      try {
        installPromise.addEventListener('downloadprogress', (ev) => {
          log(`downloadprogress イベント受信: ${JSON.stringify({ loaded: ev.loaded, total: ev.total })}`);
        });
        log('install() の戻り値に downloadprogress リスナを登録した。');
      } catch (evErr) {
        log(`downloadprogress リスナ登録に失敗: ${evErr && evErr.message}`, 'warn');
      }
    } else {
      log('install() の戻り値は addEventListener を持たない。進捗イベントは取得できない環境と判断する。');
    }

    const resolved = await installPromise;
    log(`install() Promise 解決値: ${JSON.stringify(resolved)}`, 'ok');
    setStatus('install-result', JSON.stringify(resolved));
  } catch (err) {
    const name = err && err.name ? err.name : 'UnknownError';
    const message = err && err.message ? err.message : String(err);
    log(`install() 失敗: name=${name} message=${message}`, 'ng');
    setStatus('install-result', `ERROR(${name}): ${message}`);
  }

  // install 後に再度 available() を呼んで状態遷移を確認する
  log('install 後の状態遷移を確認するため available() を再実行する。');
  const after = await checkAvailability(SR, 'ja-JP');
  if (after.ok) {
    setStatus('install-after-result', after.result);
    if (after.result === 'available') {
      log('install 後の available() が "available" を返した。言語パック取得成功の条件を満たす。', 'ok');
    } else {
      log(`install 後の available() は "${after.result}" だった。まだ available になっていない。`, 'warn');
    }
  } else {
    setStatus('install-after-result', `ERROR(${after.errorName})`);
  }

  log('=== 言語パック取得 (install) 終了 ===');
}

// ---------------------------------------------------------------------------
// (B) ファイル → audioTrack 合成と認識 (Issue #5, #6)
// ---------------------------------------------------------------------------

function readFileAsArrayBuffer(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(reader.error ?? new Error('FileReader failed'));
    reader.readAsArrayBuffer(file);
  });
}

/**
 * ArrayBuffer を decodeAudioData で AudioBuffer に復号する。
 * 失敗時は DecodeFailed 相当としてログに記録し、null を返す (例外は呼び出し側で捕捉させる)。
 */
async function decodeToAudioBuffer(audioCtx, arrayBuffer) {
  log('decodeAudioData を開始する (DecodeFailed 相当のエラーはここで捕捉する)。');
  try {
    // decodeAudioData はコールバック版とPromise版があるが、モダンChromeはPromise版に対応
    const audioBuffer = await audioCtx.decodeAudioData(arrayBuffer);
    log(`decodeAudioData 成功: duration=${audioBuffer.duration.toFixed(3)}s, sampleRate=${audioBuffer.sampleRate}, channels=${audioBuffer.numberOfChannels}`, 'ok');
    return audioBuffer;
  } catch (err) {
    const message = err && err.message ? err.message : String(err);
    log(`decodeAudioData 失敗 (DecodeFailed): ${message}`, 'ng');
    throw err;
  }
}

/**
 * AudioBuffer → AudioBufferSourceNode → MediaStreamAudioDestinationNode を接続し、
 * audioTrack を取得する。design.md §4.1 のパイプラインに対応。
 */
function buildAudioTrack(audioCtx, audioBuffer, playbackRate) {
  const source = audioCtx.createBufferSource();
  source.buffer = audioBuffer;
  // playbackRate は単純な速度変更であり、ピッチも同じ倍率で変化する。
  // Web Audio にピッチ保持のタイムストレッチは無い。design.md §4.1 が
  // 倍速を「認識品質への影響が未検証」としているため、ここで測定できるようにする。
  source.playbackRate.value = playbackRate;
  if (playbackRate !== 1) {
    log(`playbackRate=${playbackRate} を設定した。ピッチも ${playbackRate} 倍になる点に注意。`, 'warn');
    log(`想定所要時間: 約 ${(audioBuffer.duration / playbackRate).toFixed(1)} 秒 (実時間なら ${audioBuffer.duration.toFixed(1)} 秒)。`);
  }
  const destination = audioCtx.createMediaStreamDestination();
  source.connect(destination);

  const stream = destination.stream;
  const audioTrack = stream.getAudioTracks()[0];
  if (!audioTrack) {
    throw new Error('MediaStreamAudioDestinationNode から audioTrack を取得できなかった。');
  }
  log(`audioTrack 取得: readyState=${audioTrack.readyState}, kind=${audioTrack.kind}, label="${audioTrack.label}"`);
  if (audioTrack.readyState !== 'live') {
    log(`audioTrack.readyState が "live" ではない ("${audioTrack.readyState}")。想定外の状態。`, 'warn');
  } else {
    log('audioTrack.readyState === "live" を確認した。', 'ok');
  }

  // destination と stream を呼び出し側へ返して参照を保持させる。
  // これらをローカル変数のまま捨てると、到達不能になった時点で GC により
  // MediaStreamAudioDestinationNode が回収され、audioTrack が ended になり、
  // 認識が "aborted" で即座に中断する。
  return { source, destination, stream, audioTrack };
}

/**
 * SpeechRecognition インスタンスを構築し、processLocally を設定 → 読み戻し検証する。
 * NFR-2: processLocally が true で読み戻せない場合はサーバーフォールバックせずエラーで停止する。
 */
function buildRecognition(SR, locale, opts) {
  const recognition = new SR();
  recognition.lang = locale;
  // design.md §4.1 の既定は continuous/interimResults とも true。
  // 実機で isFinal が立たない事象を確認したため、切り分け用に変更可能にしている。
  recognition.continuous = opts.continuous;
  recognition.interimResults = opts.interimResults;

  // processLocally はプロパティとして存在するとは限らない。存在確認せず単純代入すると
  // サイレントに無視される可能性があるため、設定直後に読み戻して必ず検証する。
  recognition.processLocally = true;
  const readBack = recognition.processLocally;
  log(`processLocally 設定直後の読み戻し値: ${readBack}`);
  if (readBack !== true) {
    // NFR-2: フォールバック禁止。ここで明確にエラーとして停止する。
    throw new Error(
      `processLocally を true に設定したが読み戻し値が true にならなかった (実際: ${readBack})。` +
      'NFR-2 (サーバー認識へのサイレントフォールバック禁止) により、ここで処理を停止する。'
    );
  }
  log('processLocally === true を確認した。サーバーフォールバックの兆候なし。', 'ok');

  log(`recognition 設定: lang=${recognition.lang}, continuous=${recognition.continuous}, interimResults=${recognition.interimResults}`);
  return recognition;
}

/**
 * 認識セッション本体。source.start() + recognition.start(audioTrack) を行い、
 * final結果を蓄積して返す。design.md §4.1 / §8 未決事項4 の検証対象。
 */
function runRecognitionSession(recognition, source, audioTrack, retained) {
  return new Promise((resolve, reject) => {
    // retained (destination / stream) はこのクロージャが握り続けることで
    // セッション中の GC を防ぐ。finish() でも参照して最適化による除去を避ける。
    const keepAlive = retained;
    let finalText = '';
    // Chrome のオンデバイス認識は isFinal を一度も立てずに onend へ到達することがある
    // (実機で確認済み)。その場合でも認識テキスト自体は interim として得られているため、
    // 最後の interim を保持しておき、final が皆無だったときの記録に使う。
    let lastInterimText = '';
    let interimOnly = false;
    let sessionEnded = false;
    let onendTimer = null;
    const startedAt = performance.now();
    let networkErrorSeen = false;
    // 最初に観測した認識エラー。onend 到達時にこれを使ってセッションを reject する。
    // 不完全な finalText を「成功」として包含率評価に渡さないための措置。
    let recognitionError = null;

    const finish = (result, error) => {
      if (sessionEnded) return;
      sessionEnded = true;
      if (onendTimer) clearTimeout(onendTimer);
      // keepAlive をここで参照し、セッション終了まで destination / stream が
      // 到達可能であることを保証する (GC による audioTrack 終了の防止)。
      if (keepAlive && keepAlive.stream) {
        log(`セッション終了時の audioTrack.readyState=${audioTrack.readyState}`);
      }
      log(`収集した確定テキスト: ${finalText.length} 文字`);
      if (!finalText && lastInterimText) {
        // フォールバックではなく事実の記録。final が出ないこと自体が
        // design.md §2.2 の isFinal 設計に関わる知見であるため、
        // interim を採用したことを必ず明示する。
        interimOnly = true;
        finalText = lastInterimText;
        log(
          'isFinal が一度も立たないまま onend に到達した。最後の interim 結果を' +
          `採用する (${lastInterimText.length} 文字)。` +
          'この挙動は design.md §2.2 / §4.1 の isFinal 写像に影響する。',
          'warn'
        );
      }
      const elapsedMs = Math.round(performance.now() - startedAt);
      if (error) {
        reject({ error, elapsedMs, finalText, networkErrorSeen, interimOnly });
      } else {
        resolve({ finalText, elapsedMs, networkErrorSeen, interimOnly });
      }
    };

    recognition.onresult = (event) => {
      for (let i = event.resultIndex; i < event.results.length; i++) {
        const result = event.results[i];
        const transcript = result[0] ? result[0].transcript : '';
        if (result.isFinal) {
          finalText += transcript;
          log(`[final] ${transcript}`, 'ok');
        } else {
          lastInterimText = transcript;
          log(`[partial] ${transcript}`);
        }
      }
    };

    recognition.onerror = (event) => {
      const errorCode = event.error;
      log(`recognition.onerror: error="${errorCode}" message="${event.message ?? ''}"`, 'ng');
      if (errorCode === 'network') {
        networkErrorSeen = true;
        log('"network" エラーを検知した。サーバーフォールバックの兆候の可能性があり、NFR-2違反の疑いがある。', 'ng');
      }
      // onerror 単体ではセッションを即終了させず、後続の onend を待つ (ブラウザ実装によりonendが続けて発火するため)。
      // 最初のエラーのみ保持し、onend でこれを使って reject する。
      if (!recognitionError) {
        recognitionError = new Error(
          `SpeechRecognition failed: ${errorCode}${event.message ? `: ${event.message}` : ''}`
        );
      }
    };

    recognition.onend = () => {
      if (recognitionError) {
        log('recognition.onend 発火。認識エラーが記録されているためセッションをエラーとして終了する。', 'ng');
        finish(null, recognitionError);
        return;
      }
      log('recognition.onend 発火。セッションを終了する。');
      finish();
    };

    source.onended = () => {
      // continuous = true では、AudioBufferSourceNode が再生を終えても
      // MediaStreamAudioDestinationNode のトラックは live のまま無音を流し続ける。
      // そのため Chrome は入力が終わったことを知りようがなく、放置しても onend は来ない。
      // design.md §4.1 の「sourceの onended 後、recognition.onend をもって Stream close」を
      // 成立させるには、ここで明示的に stop() を呼んで入力終了を通知する必要がある。
      log('audio source.onended 発火。recognition.stop() で入力終了を通知し、onend を待つ。');
      try {
        recognition.stop();
        log('recognition.stop() を呼び出した。', 'ok');
      } catch (stopErr) {
        log(`recognition.stop() 呼び出しでエラー: ${stopErr && stopErr.message}`, 'ng');
      }

      onendTimer = setTimeout(() => {
        log(`stop() から ${ONEND_TIMEOUT_MS}ms 経過しても onend が来ない。トラックを停止して abort() する。`, 'warn');
        // 入力トラック自体を終了させてから abort() する。ここまでやっても onend が
        // 来ないのであれば、それ自体が design.md §4.1 の終了検出に関する知見となる。
        try { audioTrack.stop(); } catch (e) { log(`audioTrack.stop() でエラー: ${e && e.message}`, 'ng'); }
        try { recognition.abort(); } catch (e) { log(`recognition.abort() でエラー: ${e && e.message}`, 'ng'); }

        onendTimer = setTimeout(() => {
          const timeoutError = new Error(
            `recognition.onend did not fire within ${ONEND_TIMEOUT_MS}ms after stop(), ` +
            `nor within ${ABORT_GRACE_MS}ms after abort()`
          );
          // 収集済みの確定テキストがあれば必ず残す。3分クリップの認識結果を
          // 捨てないため。ただし包含率評価には渡さない (セッションは異常終了扱い)。
          if (finalText) {
            log(`onend 未達だが確定テキストを ${finalText.length} 文字収集済み。結果欄に表示する。`, 'warn');
          }
          finish(null, timeoutError);
        }, ABORT_GRACE_MS);
      }, ONEND_TIMEOUT_MS);
    };

    // audioTrack が途中で終了/ミュートされると認識は "aborted" になる。
    // 原因切り分けのため、トラック側のイベントを必ず記録する。
    audioTrack.onended = () => {
      log(`audioTrack.onended 発火 (readyState=${audioTrack.readyState})。以降の認識入力は途切れる。`, 'ng');
    };
    audioTrack.onmute = () => log('audioTrack.onmute 発火。入力が無音として扱われる。', 'warn');
    audioTrack.onunmute = () => log('audioTrack.onunmute 発火。');

    // recognition を先に開始し、onstart を待ってから音声を再生する。
    // 逆順だと先頭が認識器に渡る前に再生が進み、冒頭が欠落する。
    let startedSource = false;
    const startSource = () => {
      if (startedSource) return;
      startedSource = true;
      try {
        source.start();
        log('AudioBufferSourceNode.start() を呼び出した。再生を開始する。');
      } catch (err) {
        finish(null, err);
      }
    };

    const onstartTimer = setTimeout(() => {
      if (!startedSource && !sessionEnded) {
        finish(
          null,
          new Error('recognition.start(audioTrack) 後 5000ms 以内に onstart が発火しなかった。')
        );
      }
    }, 5000);

    recognition.onstart = () => {
      clearTimeout(onstartTimer);
      log('recognition.onstart 発火。認識セッションが開始された。', 'ok');
      log(`onstart 時点の audioTrack: readyState=${audioTrack.readyState}, enabled=${audioTrack.enabled}, muted=${audioTrack.muted}`);
      startSource();
    };

    try {
      recognition.start(audioTrack);
      log('recognition.start(audioTrack) を呼び出した。design.md §8 未決事項4 の検証対象。');
    } catch (err) {
      clearTimeout(onstartTimer);
      log(`recognition.start(audioTrack) 呼び出しで例外: ${err && err.message}`, 'ng');
      finish(null, err);
    }
  });
}

/**
 * マイク権限の状態を記録する。start(audioTrack) はマイクを使わないが、
 * Chrome の SpeechRecognition が権限を要求するかどうかが未確認のため、
 * "aborted" / "not-allowed" の原因切り分け材料として必ず残す。
 */
async function logMicrophonePermission() {
  if (!navigator.permissions || !navigator.permissions.query) {
    log('navigator.permissions.query が利用できない。マイク権限状態は取得不可。', 'warn');
    return;
  }
  try {
    const status = await navigator.permissions.query({ name: 'microphone' });
    log(`マイク権限の状態: ${status.state}`);
  } catch (err) {
    log(`マイク権限の照会に失敗: ${err && err.name}: ${err && err.message}`, 'warn');
  }
}

async function runTranscription() {
  log('=== 文字起こし実行 開始 ===');
  log(`document.visibilityState=${document.visibilityState}, document.hasFocus()=${document.hasFocus()}`);
  await logMicrophonePermission();
  if (!selectedFile) {
    log('ファイルが選択されていない。', 'ng');
    return;
  }

  const SR = getSpeechRecognitionCtor();
  if (!SR) {
    log('SpeechRecognition が未定義のため文字起こしを実行できない。', 'ng');
    return;
  }

  const clipId = resolveClipId();
  if (!clipId) {
    log('クリップIDを推定できなかった。プルダウンで手動選択してから再実行すること。', 'ng');
    return;
  }
  const clip = KEYWORDS_DB[clipId];
  log(`クリップID=${clipId} (locale=${clip.locale}) を使用する。`);

  // design.md §3: transcribeFile() は checkModel() が available 以外なら
  // 即座に ModelUnavailableException を返す。内部で暗黙にダウンロードしない
  // (同意UXをアプリ側に強制するため)。ハーネスも同じ契約に従う。
  // このチェックが無いと、言語パック未取得のまま start() が呼ばれ、
  // Chrome が "aborted" / "language-not-supported" を返して原因が分かりにくくなる。
  const availability = await SR.available({ langs: [clip.locale], processLocally: true });
  log(`文字起こし前の available({langs:["${clip.locale}"], processLocally:true}) = ${availability}`);
  if (availability !== 'available') {
    if (availability === 'downloadable') {
      pendingInstallLocale = clip.locale;
      const installBtn = document.getElementById('btn-install');
      installBtn.disabled = false;
      installBtn.textContent = `言語パック取得 (install: ${clip.locale})`;
    }
    const msg =
      `${clip.locale} の言語パックが available ではない (${availability})。` +
      (availability === 'downloadable'
        ? `「言語パック取得 (install: ${clip.locale})」を実行してから、もう一度文字起こしを実行すること。`
        : 'この環境ではこのロケールのオンデバイス認識を利用できない。');
    log(msg, 'ng');
    setStatus('transcribe-status', `中止: ${availability}`);
    return;
  }
  log(`${clip.locale} は available。文字起こしを開始する。`, 'ok');

  let audioCtx = null;
  try {
    log(`ファイル読込開始: name="${selectedFile.name}" size=${selectedFile.size}bytes`);
    const arrayBuffer = await readFileAsArrayBuffer(selectedFile);
    log('ArrayBuffer 読込完了。', 'ok');

    audioCtx = new (window.AudioContext ?? window.webkitAudioContext)();
    const audioBuffer = await decodeToAudioBuffer(audioCtx, arrayBuffer);

    const rateEl = document.getElementById('playback-rate');
    const playbackRate = rateEl ? Number(rateEl.value) : 1;
    if (!Number.isFinite(playbackRate) || playbackRate <= 0) {
      log(`再生速度の値が不正 (${rateEl && rateEl.value})。`, 'ng');
      return;
    }
    const { source, destination, stream, audioTrack } = buildAudioTrack(audioCtx, audioBuffer, playbackRate);
    const recognitionOpts = {
      continuous: document.getElementById('opt-continuous').checked,
      interimResults: document.getElementById('opt-interim').checked,
    };
    log(`認識オプション: continuous=${recognitionOpts.continuous}, interimResults=${recognitionOpts.interimResults}`);
    const recognition = buildRecognition(SR, clip.locale, recognitionOpts);

    setStatus('transcribe-status', '実行中...');
    const sessionResult = await runRecognitionSession(recognition, source, audioTrack, { destination, stream });

    log(`所要時間: ${sessionResult.elapsedMs}ms (NFR-1: Webはファイル長と同程度になる想定)`);
    setStatus('transcribe-status', `完了 (${sessionResult.elapsedMs}ms)`);
    document.getElementById('result-text').value = sessionResult.finalText;

    log(`再生速度 ${playbackRate}x での所要時間: ${sessionResult.elapsedMs}ms`);
    if (sessionResult.interimOnly) {
      log('注意: この結果は確定(isFinal)結果ではなく interim 結果である。', 'warn');
    }
    scoreResult(clipId, sessionResult.finalText, sessionResult.elapsedMs, sessionResult.networkErrorSeen);
  } catch (errInfo) {
    // decode失敗やstart失敗など、reject/throw両方の経路をまとめて捕捉する
    const err = errInfo && errInfo.error ? errInfo.error : errInfo;
    const elapsedMs = errInfo && errInfo.elapsedMs;
    const partialFinal = errInfo && errInfo.finalText;
    const message = err && err.message ? err.message : String(err);
    log(`文字起こし実行中にエラー: ${message}`, 'ng');
    setStatus('transcribe-status', `エラー: ${message}`);
    if (partialFinal) {
      document.getElementById('result-text').value = partialFinal;
      log(`エラー終了だが確定テキスト ${partialFinal.length} 文字を結果欄に表示した。包含率評価には渡さない。`, 'warn');
    } else {
      log('確定テキストは1文字も得られていない。', 'ng');
    }
    if (elapsedMs != null) {
      log(`エラー発生までの所要時間: ${elapsedMs}ms`);
    }
  } finally {
    if (audioCtx) {
      try {
        await audioCtx.close();
      } catch (closeErr) {
        log(`AudioContext.close() でエラー: ${closeErr && closeErr.message}`, 'warn');
      }
    }
  }

  log('=== 文字起こし実行 終了 ===');
}

// ---------------------------------------------------------------------------
// (C) キーワード包含率スコアリング (Issue #6)
// design.md §7「評価基準(キーワード包含率)」の正規化ルールに厳密に従う。
// ---------------------------------------------------------------------------

/**
 * design.md §7 の正規化ルールを適用する。
 * 1. NFKC正規化
 * 2. 小文字化
 * 3. 句読点・記号除去 (Unicode一般カテゴリ P と S、および明示列挙記号)
 * 4. 空白除去
 * ja-JP はさらにひらがな→カタカナ畳み込みを行う。
 *
 * @param {string} text
 * @param {string} locale 'ja-JP' | 'en-US'
 */
function normalize(text, locale) {
  let s = text;

  // 1. Unicode NFKC 正規化 (全角英数字・記号の半角化、半角カナの全角化を含む)
  s = s.normalize('NFKC');

  // 2. 小文字化 (ja-JPに含まれるラテン文字にも適用する)
  s = s.toLowerCase();

  // 3. 句読点・記号除去。Unicode一般カテゴリ P (句読点) と S (記号) の全文字、
  //    および明示列挙記号 (念のためNFKC/カテゴリ判定の抜け漏れに備えて明示する)
  s = s.replace(/[\p{P}\p{S}]/gu, '');
  s = s.replace(/[、。「」・,.!?:;()[\]{}"'\-/]/gu, '');

  // 4. 空白除去。半角/全角スペース、タブ、改行を含む全空白文字
  s = s.replace(/\s/gu, '');

  // ja-JP固有: ひらがな→カタカナ畳み込み (U+3041-U+3096 を +0x60 してカタカナ範囲へ)
  if (locale === 'ja-JP') {
    s = s.replace(/[ぁ-ゖ]/g, (ch) => String.fromCharCode(ch.charCodeAt(0) + 0x60));
  }

  return s;
}

/**
 * 1個のキーワード項目 (文字列 or 許容表記の配列) が認識結果に含まれるか判定する。
 */
function keywordMatches(keywordItem, normalizedResult, locale) {
  const variants = Array.isArray(keywordItem) ? keywordItem : [keywordItem];
  for (const variant of variants) {
    const normalizedVariant = normalize(variant, locale);
    if (normalizedVariant.length === 0) continue;
    if (normalizedResult.includes(normalizedVariant)) {
      return { matched: true, matchedVariant: variant };
    }
  }
  return { matched: false, matchedVariant: null };
}

function judge(locale, rate) {
  const th = THRESHOLDS[locale];
  if (!th) return '判定基準未定義';
  if (rate >= th.passMin) return '合格';
  if (th.conditionalMin != null && rate >= th.conditionalMin) return '条件付き合格 / 要確認';
  return '不成立';
}

function scoreResult(clipId, resultText, elapsedMs, networkErrorSeen) {
  const clip = KEYWORDS_DB[clipId];
  const locale = clip.locale;
  const normalizedResult = normalize(resultText, locale);

  const matched = [];
  const unmatched = [];
  for (const kw of clip.keywords) {
    const { matched: isMatched, matchedVariant } = keywordMatches(kw, normalizedResult, locale);
    if (isMatched) {
      matched.push({ keyword: kw, matchedVariant });
    } else {
      unmatched.push(kw);
    }
  }

  const total = clip.keywords.length;
  const rate = total === 0 ? 0 : (matched.length / total) * 100;
  const verdict = judge(locale, rate);

  log(`キーワード包含率: ${matched.length}/${total} = ${rate.toFixed(1)}% (locale=${locale}) → 判定: ${verdict}`, verdict === '不成立' ? 'ng' : 'ok');
  log(`一致キーワード: ${matched.map((m) => JSON.stringify(m.keyword)).join(', ') || '(なし)'}`);
  log(`不一致キーワード: ${unmatched.map((k) => JSON.stringify(k)).join(', ') || '(なし)'}`);
  if (networkErrorSeen) {
    log('このセッションでは "network" エラーが発生していた。結果の信頼性に注意 (NFR-2違反の疑い)。', 'warn');
  }

  const scoreEl = document.getElementById('score-result');
  if (scoreEl) {
    scoreEl.innerHTML = '';
    const summary = document.createElement('div');
    summary.className = 'score-summary';
    summary.textContent = `${clipId} (${locale}): ${matched.length}/${total} = ${rate.toFixed(1)}% → ${verdict}` +
      (elapsedMs != null ? ` (所要時間 ${elapsedMs}ms)` : '');
    scoreEl.appendChild(summary);

    const matchedEl = document.createElement('div');
    matchedEl.textContent = `一致: ${matched.map((m) => m.keyword).join(', ') || '(なし)'}`;
    scoreEl.appendChild(matchedEl);

    const unmatchedEl = document.createElement('div');
    unmatchedEl.textContent = `不一致: ${unmatched.join(', ') || '(なし)'}`;
    scoreEl.appendChild(unmatchedEl);
  }

  return { matched, unmatched, rate, verdict };
}

// ---------------------------------------------------------------------------
// クリップID推定
// ---------------------------------------------------------------------------

function resolveClipId() {
  const manualSelect = document.getElementById('clip-select');
  if (manualSelect && manualSelect.value && manualSelect.value !== 'auto') {
    return manualSelect.value;
  }
  if (!selectedFile) return null;
  const name = selectedFile.name;
  for (const [clipId, patterns] of Object.entries(CLIP_ID_HINTS)) {
    if (patterns.some((re) => re.test(name))) {
      return clipId;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// 初期化・イベント配線
// ---------------------------------------------------------------------------

async function loadKeywordsDb() {
  try {
    const res = await fetch('./keywords.json');
    if (!res.ok) {
      throw new Error(`keywords.json 取得失敗: HTTP ${res.status}`);
    }
    const data = await res.json();
    delete data._comment;
    KEYWORDS_DB = data;
    log(`keywords.json 読込完了。クリップ: ${Object.keys(KEYWORDS_DB).join(', ')}`, 'ok');
  } catch (err) {
    log(`keywords.json 読込失敗: ${err && err.message}`, 'ng');
  }
}

function onFileSelected(event) {
  const file = event.target.files && event.target.files[0];
  if (!file) {
    selectedFile = null;
    return;
  }
  selectedFile = file;
  log(`ファイル選択: name="${file.name}" size=${file.size}bytes type="${file.type}"`);
  const guessed = resolveClipId();
  setStatus('clip-guess', guessed ? `推定クリップID: ${guessed}` : '推定できず。プルダウンで手動選択すること。');
}

function init() {
  detectEnvironment();
  loadKeywordsDb();

  document.getElementById('btn-check-availability').addEventListener('click', () => {
    runAvailabilityCheck().catch((err) => log(`可用性チェックで予期せぬエラー: ${err && err.message}`, 'ng'));
  });
  document.getElementById('btn-install').addEventListener('click', () => {
    runInstall().catch((err) => log(`install実行で予期せぬエラー: ${err && err.message}`, 'ng'));
  });
  document.getElementById('file-input').addEventListener('change', onFileSelected);
  document.getElementById('btn-transcribe').addEventListener('click', () => {
    runTranscription().catch((err) => log(`文字起こし実行で予期せぬエラー: ${err && err.message}`, 'ng'));
  });

  log('初期化完了。可用性チェックから開始すること。');
}

document.addEventListener('DOMContentLoaded', init);
