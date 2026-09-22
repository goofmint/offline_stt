# pub.dev への公開 runbook

対応 Issue: #65。関連: [VERSION_POLICY.md](./VERSION_POLICY.md)(Issue #68)、
requirements.md NFR-5「バージョニング」、`.github/workflows/publish.yml`、
`.github/workflows/ci.yml`。

## この文書の位置づけ

本書は `offline_stt` monorepo を pub.dev へ公開する手順書である。
**本書は手順書であって、実行記録ではない。** `dart pub publish`(dry-run で
ない方)はまだ実行していない。初回公開は本書に従って人間が手動で行う。

**単一パッケージへの統合(Issue #91)により、公開対象は `offline_stt` 1つ
だけになった。** 以前は `offline_stt_platform_interface` /
`offline_stt_android` / `offline_stt_darwin` / `offline_stt_web` /
`offline_stt` の5パッケージが対象であり、Dart Pub Workspaces の依存順制約
から公開順序を守る必要があったが、単一パッケージ化によりこの制約は解消
した。

## 1. 公開対象は `offline_stt` の1パッケージ

このリポジトリの `packages/` 配下にあるのは `offline_stt` 1パッケージのみで
あり、これが公開対象のすべてである。`apps/example` は `publish_to: none` を
宣言しており公開対象ではない。

## 2. 公開前チェックリスト

初回公開・以降の公開(タグ push)のいずれも、次をすべて満たしてから行う。

- [ ] `main` ブランチが green である(`.github/workflows/ci.yml` の
      `analyze-test` / `build` ジョブがすべて成功している)。
- [ ] `melos run analyze` が通る(`dart analyze --fatal-infos`)。
- [ ] `melos run test` が通る。
- [ ] `melos run format` が通る(フォーマット差分が無い)。
- [ ] `melos run doc` が通る(`dart doc --validate-links`。APIドキュメントが
      生成でき、docコメント中の参照切れ・READMEの相対リンク切れが無いことを
      検証する)。
- [ ] `melos run publish:dry-run` が警告0件で通る(ルート `pubspec.yaml` の
      melos scripts。`packageFilters: { private: false }` により
      `publish_to: none` の `apps/example` は自動的に対象から外れる)。
- [ ] `packages/offline_stt/CHANGELOG.md` に、公開するバージョンのエントリが
      存在し、`pubspec.yaml` の `version:` と一致している。
- [ ] 依存関係の宣言に `path:` 依存が残っていない。

## 3. 初回 0.1.0 の手動公開手順

**`dart pub publish` は取り消せない外向き操作である(4節参照)。** 実行前に
2節のチェックリストをすべて満たしていることを確認すること。

```sh
# 0. リポジトリルートで依存解決(ワークスペース全体)
melos bootstrap

# 1. offline_stt を公開する
cd packages/offline_stt
dart pub publish
cd ../..
```

`dart pub publish` の直前に、対話プロンプトで公開内容(パッケージ名・
バージョン・アップロード先)が表示される。**内容を必ず目視確認してから
承認すること。** 誤った内容のまま承認すると、4節のとおり取り消せない。

## 4. `dart pub publish` は取り消せない

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
- したがって、公開前は必ず2節のチェックリストを満たし、3節のコマンドを
  実行する前に対話プロンプトの内容を確認すること。**「とりあえず公開して
  みる」は禁止。**

## 5. 2回目以降: GitHub Actions OIDC(Trusted Publishing)による自動公開

初回 0.1.0 の手動公開が完了した後、以降のバージョンは
`.github/workflows/publish.yml` によるタグ push トリガの自動公開へ
移行する。Trusted Publishing はリポジトリに長期の認証情報(トークン)を
保存しない方式であり、pub.dev が公式に推奨している
(<https://dart.dev/tools/pub/automated-publishing>)。

**Trusted Publishing を有効化するには、そのパッケージが pub.dev 上に
既に存在している必要がある**(同上「Today, you can only automate
publishing of existing packages. To create a new package, you must publish
the first version using `dart pub publish`.」)。これが3節で初回を
手動公開にする理由である。

### 5.1 pub.dev 側の設定(1回)

1. `https://pub.dev/packages/offline_stt/admin` を開く(*uploader* または
   publisher の admin であること)。
2. **Automated publishing** セクションの
   **Enable publishing from GitHub Actions** をクリックする。
3. 次を入力する。
   - **Repository**: `goofmint/offline_stt`
   - **Tag pattern**: `offline_stt-v{{version}}`(例: `offline_stt-v0.1.0`)

タグパターンは `.github/workflows/publish.yml` の `on.push.tags` と
**必ず一致させる**こと。一致していないと、タグを push してもワークフローが
起動しない、またはワークフローが起動しても pub.dev 側が公開を拒否する。

任意だが推奨: pub.dev の Admin 画面で **Require GitHub Actions environment**
を有効化し、GitHub 側で `pub.dev` という Deployment Environment に
レビュー必須の保護ルールを設定すると、タグを push できる人全員が即公開
できてしまう状態を避けられる
(<https://dart.dev/tools/pub/automated-publishing#hardening-security-with-github-deployment-environments>)。
本書はこの設定手順までは含まない(採用するかどうかは別途判断する)。

### 5.2 公開の実行(バージョンを上げるたびに)

```sh
# 例: offline_stt を 0.2.0 として公開する場合
# 1. packages/offline_stt/pubspec.yaml の version を 0.2.0 に、
#    CHANGELOG.md に 0.2.0 のエントリを追加してコミット・マージする。
# 2. main 上のそのコミットにタグを打って push する。
git tag offline_stt-v0.2.0
git push origin offline_stt-v0.2.0
```

タグ push をトリガに `.github/workflows/publish.yml` が実行され、
タグの version と `pubspec.yaml` の `version:` が一致することを検証した
上で、format / analyze / test / dry-run を通してから公開する(実装は
同ファイルのコメント参照)。

### 5.3 publish.yml の Action は必ずコミットSHAで固定する

`.github/workflows/publish.yml` は `id-token: write` を持ち、pub.dev へ
実際に公開できる。ここで `actions/checkout@v4` のような**可変タグ**を使うと、
タグの指す先が差し替えられた時点でそれがそのまま公開権限の乗っ取りになる。
このため publish.yml が使う Action は**不変のコミットSHAで固定**し、
右側の行コメントに対応するバージョンを書いてある。

```yaml
- uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
```

**バージョンを上げるときは、SHAと行コメントを必ず同時に直すこと。**
片方だけ直すと、コメントが実際に動いている版と食い違う。

また、CI・publish の双方で `actions/checkout` に
`persist-credentials: false` を指定している。どのジョブも `git push` を
しないため `GITHUB_TOKEN` を `.git/config` に残す必要が無い。

## 6. なぜ 0.x 系で公開するか(NFR-5)

requirements.md NFR-5 のとおり、本ライブラリは 0.x 系で公開する。

> 土台のAPIが新しく、
> iOS/macOSのSpeechAnalyzerもOS 26で導入されたばかりである。また各OSの
> オンデバイス認識の挙動には実測で判明した未確定要素が残る(design.md §8)。
> そのためライブラリは0.x系で公開し、各OS APIのstable化までstableを
> 名乗らない

補足として、Issue #65 のコメントに記録されているとおり、基準音声の
認識精度がしきい値未達(ja-JP 66.7%)であることも 0.x 系である理由の
一つである。したがって、1.0.0 への到達は「破壊的変更が無くなったら」
ではなく、「土台のOS APIがstable化し、認識精度がしきい値を満たしたら」
判断する。
