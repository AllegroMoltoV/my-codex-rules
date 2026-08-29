# my-codex-rules

Codex で使用する共通ルール、再利用可能なスキルと、Beads を使ったプロジェクト初期セットアップを配布する個人向けルール集です。

Codex は共通の指示を `$CODEX_HOME/AGENTS.md`、再利用可能な手順を `$HOME/.agents/skills` から読み込みます。このリポジトリは両方をグローバル領域へ導入し、プロジェクトごとの初期設定は配布用の `.prompts/INIT.md` から開始します。

## 使い方

2 つのフェーズに分かれます。**フェーズ 1 は端末ごとに 1 回、フェーズ 2 はプロジェクトごとです。**

### フェーズ 1: グローバルの初回セットアップ

1. 本リポジトリを clone する
2. `codex`、`bd`、`jq` が使えることを確認する
3. `$CODEX_HOME` に非空の `AGENTS.override.md` がないことを確認する
4. clone したディレクトリで `scripts/setup-beads.ps1` を実行する
5. Codex で `/hooks` を開き、追加されたフックを確認して信頼する
6. Codex を再起動する

```powershell
git clone https://github.com/AllegroMoltoV/my-codex-rules.git
cd my-codex-rules
pwsh -NoProfile -File scripts/setup-beads.ps1
```

セットアップは、共通ルール、2 つのスキル、Auto-review、Beads の Codex 統合、記録漏れ通知フックをグローバル領域へ導入します。既存の Codex 設定は先にバックアップします。`bd` と `jq` は導入しません。見つからない場合は変更前に中止します。

非空の `$CODEX_HOME/AGENTS.override.md` がある場合、Codex は同じ階層の `AGENTS.md` を読み込みません。セットアップは無効な導入を成功扱いにせず、設定変更前に停止します。override の内容を共通ルールへ統合するか、一時的に退避してから再実行してください。0 バイトの override は Codex が読み飛ばすため停止対象ではありません。

### フェーズ 2: プロジェクトのセットアップ

1. プロジェクト用のディレクトリを作る
2. 本リポジトリの `.prompts/INIT.md` を、プロジェクトの `.prompts/INIT.md` へコピーする
3. コピーした INIT に要件、前提条件と制約、完了条件を書く
4. そのプロジェクトで Codex を起動し、`.prompts/INIT.md` を実行してくださいと依頼する

**残りは Codex が行います。** `$project-bootstrap` が Git、除外設定、作業用ディレクトリ、文書索引、Beads を初期設定します。その後、要件に関係する現状を調査し、複数セッションへまたがる作業を Beads へ登録します。このスキルは状態を変更するため暗黙起動せず、INIT または `$project-bootstrap` の明示指定がある場合だけ実行します。

`workspace-write` でも `.git/info/exclude` が保護される場合があります。その場合、Codex は対象プロジェクトと bootstrap コマンドに限定して権限昇格を求めます。拒否された場合は除外設定を未完了として報告し、サンドボックス全体を無効にしません。

共通 `AGENTS.md` と INIT はプロジェクト初期設定で生成しません。共通ルールはグローバル領域から読み込み、INIT はユーザーが配布元からコピーしたファイルをそのまま使います。

## 内容物

| パス | 内容 |
|---|---|
| `rules/AGENTS.md` | グローバルへ導入する共通ルールの原本 |
| `.prompts/INIT.md` | プロジェクトへ手動でコピーする要件シート |
| `skills/project-bootstrap/` | INIT から呼び出すプロジェクト初期セットアップスキル |
| `skills/japanese-technical-writing/` | README、設計書、報告書などの日本語技術文書を作成、改稿するスキル |
| `scripts/setup-beads.ps1` | 共通ルール、スキル、Beads 統合、通知フックの導入 |
| `scripts/teardown-beads.ps1` | 管理要素の削除または導入前バックアップの復元 |
| `scripts/verify-beads.ps1` | 一時的な利用者領域を使う隔離検証 |
| `exclude` | 対象プロジェクトの `.git/info/exclude` へ追加する設定 |

## 補足

**更新時は再実行します。** 本リポジトリで `git pull` した後、`scripts/setup-beads.ps1` を再実行してください。管理対象の共通ルールとスキルを更新します。導入後にグローバル `AGENTS.md` またはスキルが変更されていた場合は、利用者の変更を上書きせず中止します。

**Auto-review はサンドボックスを解除しません。** `approval_policy` が未設定なら `on-request`、`approvals_reviewer` が未設定なら `auto_review` を利用者の `config.toml` へ追加します。既存値は上書きせず、Auto-review が有効にならない可能性を警告します。設定は新しい Codex セッションから有効です。Auto-review は承認対象の操作を別の審査エージェントへ送り、追加のモデル呼び出しを使います。高危険度操作、組織の管理方針、プロジェクト固有設定、サンドボックスの保護範囲を上書きする機能ではありません。

**このリポジトリも Beads で管理します。** `.beads-optout` は置かず、複数セッションへまたがる作業とブロッカーを Beads に記録します。`.beads/` は進捗データを含むため、取り消し処理や一時ファイル削除の対象にしません。

**通常の取り消しでは共通ルールと Codex 設定を残します。** Beads 統合、通知フック、2 つのスキルだけを削除する場合は、次を実行します。

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
| v1.6.0 | 2026-08-29 | Claude Code 版 v2.10.0 の反復手順の固定化原則を Codex 向けに反映。過去の記録で再現性を確認できた手順だけを対象とし、判断が残らない部分はスクリプト、判断が残る部分は `.agents/skills` 配下のスキルへ分離する。手順本文を `AGENTS.md` や `bd remember` へ置かず、再現手順の所在だけを記録する規則を追加 |
| v1.5.0 | 2026-08-22 | Claude Code 版 v2.9.1 の計画検証規則を Codex 向けに反映。親の会話履歴を継承しないサブエージェントに計画の失敗経路を反証させ、現在のセッションより低位のモデルを使わない要件を追加 |
| v1.4.0 | 2026-08-16 | 共通ルールを Codex 向けに圧縮。日本語技術文書スキル、override 検出、Auto-review の安全な既定設定、明示起動する project-bootstrap を追加 |
| v1.3.0 | 2026-08-08 | グローバル導入とプロジェクト初期設定を分離。共通ルールをグローバルへ導入し、README と INIT を二段階運用に合わせて短縮 |
| v1.2.0 | 2026-08-08 | 移設前の `Stop` フックの置き換え、エラーと証拠なしを区別する規則を追加 |
| v1.1.0 | 2026-08-08 | Beads 公式 Codex 統合、初回セットアップスキル、記録漏れ通知、隔離検証を追加 |
| v1.0.0 | 2026-07-20 | 事実の検証、調査、報告、文書、テストなどの行動原則を追加 |
| v0.2.0 | 2026-06-06 | 計画と承認、調査記録、TDD の規則を追加 |
| v0.1.0 | 2026-03-13 | 初版 |
