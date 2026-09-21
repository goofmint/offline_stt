# pub.dev への公開 runbook

対応 Issue: #65。関連: [VERSION_POLICY.md](./VERSION_POLICY.md)(Issue #68)、
requirements.md NFR-5「バージョニング」、`.github/workflows/publish.yml`、
`.github/workflows/ci.yml`。

## この文書の位置づけ

本書は `offline_stt` monorepo を pub.dev へ公開する手順書である。
**本書は手順書であって、実行記録ではない。** 2026-09-21 時点で dry-run の
成功は確認済みだが、`dart pub publish`(dry-run でない方)は本書を書いた
PR では**実行していない**。初回公開は本書に従って人間が手動で行う。

## 1. 公開対象は5パッケージ(6ではない)

このリポジトリには6つのパッケージ(`packages/` 配下)があるが、公開対象は
次の **5パッケージ**である。

- `offline_stt_platform_interface`
- `offline_stt_darwin`
- `offline_stt_android`
- `offline_stt_web`
- `offline_stt`(利用者が直接依存するエントリパッケージ)

`offline_stt_windows` は **v1では公開しない**。`packages/offline_stt_windows/pubspec.yaml`
に `publish_to: none` が設定されている。理由は次のとおりで、Windows 11
実機で確認済みの事実である(requirements.md NFR-4、
`packages/offline_stt_windows/README.md` §1)。

- Windows 実装が使う `Microsoft.Windows.AI.Speech` は WinAppSDK の
  **安定版に存在しない**。NuGet の `Microsoft.WindowsAppSDK.AI` を実際に
  展開して確認したところ、安定版(2.5.5系まで確認)にも 1.7系
  (`1.7.250401001` / `1.7.260224002`)にも当該名前空間の `.winmd` は含まれず、
  `2.4.8-experimental` などの **experimental チャンネルにのみ存在する**。
- Windows 11 実機(10.0.26200 / 25H2)でクリーンビルドし、安定版の
  WinAppSDK では WinRT 実装4ファイルがコンパイル対象から外れることも
  確認済みである。
- 公式ドキュメント(<https://learn.microsoft.com/en-us/windows/ai/apis/speech-recognition>)
  の Prerequisites は「WinAppSDK version: Version 1.7.1 or later」と書いて
  いるが、これは実際の出荷物と食い違っている。
- 利用者に experimental チャンネルの WinAppSDK を要求することはできない
  ため、stable 化するまで公開対象から外す。stable 化した時点で
  `publish_to` を外して公開対象へ戻す(`packages/offline_stt_windows/pubspec.yaml`
  冒頭コメント参照)。

`.github/workflows/publish.yml` も `offline_stt_windows` を対象に含めない
(タグパターンを用意しない)。

## 2. 公開順序とその理由

**必ずこの順序で公開する。**

1. `offline_stt_platform_interface`(依存されるだけで、他の公開パッケージに
   依存しない)
2. `offline_stt_android` / `offline_stt_darwin` / `offline_stt_web`
   (`offline_stt_platform_interface: ^0.1.0` に依存する。3パッケージ間に
   相互依存は無いため、この3つの間の順序は問わない)
3. `offline_stt`(上記4パッケージすべてに依存するエントリパッケージ。
   必ず最後)

### なぜ順序を守る必要があるか

このリポジトリは [Dart Pub Workspaces](https://dart.dev/tools/pub/workspaces)
(ルート `pubspec.yaml` の `workspace:` フィールド)で管理されており、各
パッケージの `pubspec.yaml` は `resolution: workspace` を宣言している。
ワークスペース内では、`offline_stt_platform_interface: ^0.1.0` のような
hosted 形式の依存であっても **ローカルのワークスペースメンバーが
自動的に解決に使われ、pub.dev 上の実体は参照されない**
(<https://dart.dev/tools/pub/workspaces> 「If any of the workspace packages
depend on each other, they will automatically resolve to the one in the
workspace, regardless of the source.」)。

一方、`dart pub publish`(dry-run を含む)はパッケージ単体の
`acquireDependencies` を必ず実行する。ワークスペース内でこれを実行すると
上記のとおりローカル解決されてしまい、「依存先が実際に pub.dev 上に
存在するか」を検証できない。**pub.dev 上に存在しない依存先を宣言した
パッケージを公開すると、そのパッケージに実際に依存しようとした利用者側で
初めて解決エラーになる。** これを避けるため、公開順序を守り、かつ
依存先を先に公開してから依存元を公開する。

単体で(ワークスペースのローカル解決を経由せずに)依存解決を検証する
公式な方法は、対象パッケージ直下に一時的な `pubspec_overrides.yaml` を
置いて `resolution:` を空にすることである(公式ドキュメント
<https://dart.dev/tools/pub/workspaces#temporarily-resolving-a-package-outside-its-workspace>
「One way to do this is to create a `pubspec_overrides.yaml` file that
resets the `resolution` setting... Now running `dart pub get` inside
`packages/client_package` will create an independent resolution.」)。
`.github/workflows/publish.yml` はこの手法で「依存先が pub.dev 上に
存在すること」を検証してから公開する(詳細は同ファイルのコメント参照)。
手動公開でも、次に公開するパッケージへ進む前に、同じ手法で依存先が
解決できることを確認してから進むこと(4節「実行コマンド」の
「(依存確認)」を参照)。

## 3. 公開前チェックリスト

初回公開・以降の公開(タグ push)のいずれも、次をすべて満たしてから行う。

- [ ] `main` ブランチが green である(`.github/workflows/ci.yml` の
      `analyze-test` / `build` ジョブがすべて成功している)。
- [ ] `melos run analyze` が通る(全パッケージ `dart analyze --fatal-infos`)。
- [ ] `melos run test` が通る(`test/` を持つ全パッケージ)。
- [ ] `melos run format` が通る(フォーマット差分が無い)。
- [ ] `melos run doc` が通る(`dart doc --validate-links`。公開5パッケージで
      APIドキュメントが生成でき、docコメント中の参照切れ・READMEの相対
      リンク切れが無いことを検証する)。
- [ ] `melos run publish:dry-run` が5パッケージすべてで警告0件で通る
      (ルート `pubspec.yaml` の melos scripts。`packageFilters: { private: false }`
      により `publish_to: none` の `offline_stt_windows` と `apps/example`
      は自動的に対象から外れる)。
- [ ] 公開する各パッケージの `CHANGELOG.md` に、公開するバージョンの
      エントリが存在し、`pubspec.yaml` の `version:` と一致している。
- [ ] 依存関係の宣言(`offline_stt_platform_interface: ^0.1.0` 等)が
      hosted 形式であり、`path:` 依存が残っていない。

## 4. 初回 0.1.0 の手動公開手順

**`dart pub publish` は取り消せない外向き操作である(5節参照)。** 実行前に
3節のチェックリストをすべて満たしていることを確認すること。

Pub Workspaces の制約により、依存先パッケージが pub.dev 上に存在しないと
依存元パッケージの検証・公開ができない。そのため、1パッケージ公開する
たびに、**次のパッケージへ進む前に** pub.dev 上でその公開が反映されている
ことを確認する。

```sh
# 0. リポジトリルートで依存解決(ワークスペース全体)
melos bootstrap

# 1. offline_stt_platform_interface を公開する(最初)
cd packages/offline_stt_platform_interface
dart pub publish
cd ../..

# (依存確認) offline_stt_android / offline_stt_darwin / offline_stt_web に
# 進む前に、pub.dev 上で platform_interface 0.1.0 が解決できることを
# ワークスペースから切り離して確認する(2節「なぜ順序を守る必要があるか」)。
# 確認できたら pubspec_overrides.yaml を削除すること(コミットしない)。
cd packages/offline_stt_android
echo 'resolution:' > pubspec_overrides.yaml
dart pub get
rm pubspec_overrides.yaml
cd ../..

# 2. offline_stt_android / offline_stt_darwin / offline_stt_web を公開する
#    (この3つの間に相互依存は無いため順不同)
cd packages/offline_stt_android && dart pub publish && cd ../..
cd packages/offline_stt_darwin  && dart pub publish && cd ../..
cd packages/offline_stt_web     && dart pub publish && cd ../..

# (依存確認) offline_stt に進む前に、上記3パッケージすべてが
# pub.dev 上で解決できることを同様に確認する。
cd packages/offline_stt
echo 'resolution:' > pubspec_overrides.yaml
dart pub get
rm pubspec_overrides.yaml
cd ../..

# 3. offline_stt を公開する(必ず最後)
cd packages/offline_stt
dart pub publish
cd ../..
```

各 `dart pub publish` の直前に、対話プロンプトで公開内容(パッケージ名・
バージョン・アップロード先)が表示される。**内容を必ず目視確認してから
承認すること。** 誤った内容のまま承認すると、5節のとおり取り消せない。

## 5. `dart pub publish` は取り消せない

**`dart pub publish`(dry-run でない方)を実行してよいか迷ったら、実行しない。**
これは取り消せない外向き操作である。

- pub.dev の公開ポリシーは、ごく一部の例外を除き**パッケージの
  unpublish(完全削除)を認めていない**
  (<https://dart.dev/tools/pub/publishing>
  「a published package lasts forever... the pub.dev policy disallows
  unpublishing packages except for very few cases.」)。
- `dart pub retract` による撤回(retract)は**削除ではない**。公開から
  **7日以内**なら撤回でき、撤回から**7日以内**なら復元(restore)できる
  (同上「you can retract that package version within seven days of
  publication. The retracted version can be restored again within seven
  days of retraction.」)。撤回してもバージョンの一覧には
  「Retracted versions」として残り続け、**そのバージョン番号を
  空けて再利用できるわけではない。** 内容を差し替えたい場合は、
  常に新しいバージョン番号で公開し直す必要がある。
- したがって、公開前は必ず3節のチェックリストを満たし、4節のコマンドを
  実行する前に対話プロンプトの内容を確認すること。**「とりあえず公開して
  みる」は禁止。**

## 6. 2回目以降: GitHub Actions OIDC(Trusted Publishing)による自動公開

初回 0.1.0 の手動公開が完了した後、以降のバージョンは
`.github/workflows/publish.yml` によるタグ push トリガの自動公開へ
移行する。Trusted Publishing はリポジトリに長期の認証情報(トークン)を
保存しない方式であり、pub.dev が公式に推奨している
(<https://dart.dev/tools/pub/automated-publishing>)。

**Trusted Publishing を有効化するには、そのパッケージが pub.dev 上に
既に存在している必要がある**(同上「Today, you can only automate
publishing of existing packages. To create a new package, you must publish
the first version using `dart pub publish`.」)。これが4節で初回を
手動公開にする理由である。

### 6.1 pub.dev 側の設定(パッケージごとに1回)

5パッケージそれぞれについて、以下を行う。

1. `https://pub.dev/packages/<package>/admin` を開く(該当パッケージの
   *uploader* または publisher の admin であること)。
2. **Automated publishing** セクションの
   **Enable publishing from GitHub Actions** をクリックする。
3. 次を入力する。
   - **Repository**: `goofmint/offline_stt`
   - **Tag pattern**: 下表のパッケージごとのパターン(`{{version}}` を
     含む文字列)

| パッケージ | pub.dev の Tag pattern | 例(タグ名) |
|---|---|---|
| `offline_stt_platform_interface` | `platform_interface-v{{version}}` | `platform_interface-v0.1.0` |
| `offline_stt_darwin` | `darwin-v{{version}}` | `darwin-v0.1.0` |
| `offline_stt_android` | `android-v{{version}}` | `android-v0.1.0` |
| `offline_stt_web` | `web-v{{version}}` | `web-v0.1.0` |
| `offline_stt` | `offline_stt-v{{version}}` | `offline_stt-v0.1.0` |

タグパターンは `.github/workflows/publish.yml` の `on.push.tags` と
**必ず一致させる**こと。一致していないと、タグを push してもワークフローが
起動しない、またはワークフローが起動しても pub.dev 側が公開を拒否する。

任意だが推奨: pub.dev の Admin 画面で **Require GitHub Actions environment**
を有効化し、GitHub 側で `pub.dev` という Deployment Environment に
レビュー必須の保護ルールを設定すると、タグを push できる人全員が即公開
できてしまう状態を避けられる
(<https://dart.dev/tools/pub/automated-publishing#hardening-security-with-github-deployment-environments>)。
本書はこの設定手順までは含まない(採用するかどうかは別途判断する)。

### 6.2 公開の実行(パッケージごとに、バージョンを上げるたびに)

```sh
# 例: offline_stt_platform_interface を 0.2.0 として公開する場合
# 1. packages/offline_stt_platform_interface/pubspec.yaml の version を 0.2.0 に、
#    CHANGELOG.md に 0.2.0 のエントリを追加してコミット・マージする。
# 2. main 上のそのコミットにタグを打って push する。
git tag platform_interface-v0.2.0
git push origin platform_interface-v0.2.0
```

タグ push をトリガに `.github/workflows/publish.yml` が実行され、
タグ名からパッケージを特定し、タグの version と `pubspec.yaml` の
`version:` が一致することを検証した上で、format / analyze / test /
dry-run を通してから公開する(実装は同ファイルのコメント参照)。

## 7. なぜ 0.x 系で公開するか(NFR-5)

requirements.md NFR-5 のとおり、本ライブラリは 0.x 系で公開する。

> 土台のAPIが新しく、Windows AI APIs は Experimental 段階であり、
> iOS/macOSのSpeechAnalyzerもOS 26で導入されたばかりである。また各OSの
> オンデバイス認識の挙動には実測で判明した未確定要素が残る(design.md §8)。
> そのためライブラリは0.x系で公開し、各OS APIのstable化までstableを
> 名乗らない

補足として、Issue #65 のコメントに記録されているとおり、基準音声の
認識精度がしきい値未達(ja-JP 66.7%)であることも 0.x 系である理由の
一つである。したがって、1.0.0 への到達は「破壊的変更が無くなったら」
ではなく、「土台のOS APIがstable化し、認識精度がしきい値を満たしたら」
判断する。
