# my-codex-rules

Codex で使用する共通ルールと、Beads を使ったプロジェクト初期セットアップを配布する個人向けルール集です。

Codex は共通の指示を `$CODEX_HOME/AGENTS.md`、再利用可能な手順を `$HOME/.agents/skills` から読み込みます。このリポジトリは両方をグローバル領域へ導入し、プロジェクトごとの初期設定は配布用の `.prompts/INIT.md` から開始します。

## 使い方

2 つのフェーズに分かれます。**フェーズ 1 は端末ごとに 1 回、フェーズ 2 はプロジェクトごとです。**

### フェーズ 1: グローバルの初回セットアップ

1. 本リポジトリを clone する
2. `codex`、`bd`、`jq` が使えることを確認する
3. clone したディレクトリで `scripts/setup-beads.ps1` を実行する
4. Codex で `/hooks` を開き、追加されたフックを確認して信頼する
5. Codex を再起動する

```powershell
git clone https://github.com/AllegroMoltoV/my-codex-rules.git
cd my-codex-rules
pwsh -NoProfile -File scripts/setup-beads.ps1
```

セットアップは、共通ルール、`project-bootstrap` スキル、Beads の Codex 統合、記録漏れ通知フックをグローバル領域へ導入します。既存の Codex 設定は先にバックアップします。`bd` と `jq` は導入しません。見つからない場合は変更前に中止します。

### フェーズ 2: プロジェクトのセットアップ

1. プロジェクト用のディレクトリを作る
2. 本リポジトリの `.prompts/INIT.md` を、プロジェクトの `.prompts/INIT.md` へコピーする
3. コピーした INIT に要件、前提条件と制約、完了条件を書く
4. そのプロジェクトで Codex を起動し、`.prompts/INIT.md` を実行してくださいと依頼する

**残りは Codex が行います。** `$project-bootstrap` が Git、除外設定、作業用ディレクトリ、文書索引、Beads を初期設定します。その後、要件に関係する現状を調査し、複数セッションへまたがる作業を Beads へ登録します。

共通 `AGENTS.md` と INIT はプロジェクト初期設定で生成しません。共通ルールはグローバル領域から読み込み、INIT はユーザーが配布元からコピーしたファイルをそのまま使います。

## 内容物

| パス | 内容 |
|---|---|
| `rules/AGENTS.md` | グローバルへ導入する共通ルールの原本 |
| `.prompts/INIT.md` | プロジェクトへ手動でコピーする要件シート |
| `skills/project-bootstrap/` | INIT から呼び出すプロジェクト初期セットアップスキル |
| `scripts/setup-beads.ps1` | 共通ルール、スキル、Beads 統合、通知フックの導入 |
| `scripts/teardown-beads.ps1` | 管理要素の削除または導入前バックアップの復元 |
| `scripts/verify-beads.ps1` | 一時的な利用者領域を使う隔離検証 |
| `exclude` | 対象プロジェクトの `.git/info/exclude` へ追加する設定 |

## 補足

**更新時は再実行します。** 本リポジトリで `git pull` した後、`scripts/setup-beads.ps1` を再実行してください。管理対象の共通ルールとスキルを更新します。導入後にグローバル `AGENTS.md` またはスキルが変更されていた場合は、利用者の変更を上書きせず中止します。

**通常の取り消しでは共通ルールを残します。** Beads 統合、通知フック、`project-bootstrap` だけを削除する場合は、次を実行します。

```powershell
pwsh -NoProfile -File scripts/teardown-beads.ps1
```

導入前の `AGENTS.md`、`hooks.json`、`config.toml` を復元する場合は `-Restore` を付けます。セットアップ後に加えた変更も失われるため注意してください。

```powershell
pwsh -NoProfile -File scripts/teardown-beads.ps1 -Restore
```

**配布用 INIT の正本はひとつです。** Git 管理下の `.prompts/INIT.md` だけを更新します。計画、調査報告、実行ログなどの作業資料は `.appendix` または `.logs` に置き、公開用の `.prompts` 配下へ混在させません。

**現在は Windows と PowerShell 7 以降に対応します。** セットアップスクリプトは `codex`、`bd`、`jq` の存在と版表示を確認します。

## 開発時の検証

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/verify-beads.ps1
```

隔離検証は一時的な `HOME` と `CODEX_HOME` を使い、実際のグローバル環境を変更しません。

## ライセンス

MIT License です。詳細は [LICENSE](LICENSE) を参照してください。

## 更新履歴

各版の詳細は [リリース](https://github.com/AllegroMoltoV/my-codex-rules/releases) を参照してください。

| バージョン | 日付 | 内容 |
|---|---|---|
| v1.3.0 | 2026-08-08 | グローバル導入とプロジェクト初期設定を分離。共通ルールをグローバルへ導入し、README と INIT を二段階運用に合わせて短縮 |
| v1.2.0 | 2026-08-08 | 移設前の `Stop` フックの置き換え、エラーと証拠なしを区別する規則を追加 |
| v1.1.0 | 2026-08-08 | Beads 公式 Codex 統合、初回セットアップスキル、記録漏れ通知、隔離検証を追加 |
| v1.0.0 | 2026-07-20 | 事実の検証、調査、報告、文書、テストなどの行動原則を追加 |
| v0.2.0 | 2026-06-06 | 計画と承認、調査記録、TDD の規則を追加 |
| v0.1.0 | 2026-03-13 | 初版 |
