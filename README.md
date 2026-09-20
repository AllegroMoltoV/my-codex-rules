# my-codex-rules

Codex で使用する共通ルール、再利用可能なスキルと、Beads を使ったプロジェクト初期セットアップを配布する個人向けルール集です。

Codex は共通の指示を `$CODEX_HOME/AGENTS.md`、再利用可能な手順を `$HOME/.agents/skills` から読み込みます。このリポジトリは両方をグローバル領域へ導入し、プロジェクトごとの初期設定は配布用の `.prompts/INIT.md` から開始します。

## 使い方

2 つのフェーズに分かれます。**フェーズ 1 は端末の設定、フェーズ 2 はプロジェクトごとの初期設定です。** フェーズ 1 のセットアップは、初回導入とルール更新時に実行します。

### フェーズ 1: グローバルの初回セットアップ

1. 本リポジトリを clone する
2. `codex`、`bd`、`jq` が使えることを確認する
3. `$CODEX_HOME` に非空の `AGENTS.override.md` がないことを確認する
4. clone したディレクトリで、OS に合うセットアップを実行する
5. Codex で `/hooks` を開き、追加されたフックを確認して信頼する
6. Codex を再起動する

```powershell
git clone https://github.com/AllegroMoltoV/my-codex-rules.git
cd my-codex-rules
pwsh -NoProfile -File scripts/setup-beads.ps1
```

macOS では PowerShell を追加せず、POSIX シェル版を使います。2 つのスキルはリポジトリへのシンボリックリンクで配置します。共通ルールは、PC 固有ルールがなければリンク、あれば結合した通常ファイルとして配置します。

```bash
git clone https://github.com/AllegroMoltoV/my-codex-rules.git
cd my-codex-rules
bash scripts/setup-beads.sh
```

セットアップは、共通ルール、2 つのスキル、Auto-review、Beads の Codex 統合、記録漏れ通知フックをグローバル領域へ導入します。既存の Codex 設定は先にバックアップします。`bd` と `jq` は導入しません。見つからない場合は変更前に中止します。

非空の `$CODEX_HOME/AGENTS.override.md` がある場合、Codex は同じ階層の `AGENTS.md` を読み込みません。セットアップは無効な導入を成功扱いにせず、設定変更前に停止します。override の内容を共通ルールへ統合するか、一時的に退避してから再実行してください。0 バイトの override は Codex が読み飛ばすため停止対象ではありません。

### PC 固有ルールの追加 (任意)

この PC だけで使うルールを残したい場合は、`$CODEX_HOME/AGENTS.local.md` を UTF-8 で作成します。`CODEX_HOME` が未設定の場合は `~/.codex/AGENTS.local.md` です。リポジトリの共通原本や生成済みの `AGENTS.md` へ個人のルールを直接追記せず、この原本を編集してください。

```markdown
# AGENTS.local.md

このPCでのみ使用するルールを記載します。
```

作成・変更後は、フェーズ 1 と同じ OS 別セットアップを実行し、新しい Codex セッションを開始します。Windows でも macOS でも、共通ルールの後ろに PC 固有ルールを追加して `$CODEX_HOME/AGENTS.md` へ配置します。既存の `AGENTS.local.md` の内容は変更しません。別の PC で使い始める場合も、同じ場所へ必要な原本を置いて標準セットアップを実行します。

PC 固有ルールを解除する場合は、`AGENTS.local.md` を空にするか、別名へ退避してから同じセットアップを再実行します。共通ルールだけの状態へ戻ります。

`AGENTS.local.md` はこのリポジトリのセットアップが読む原本であり、Codex が標準で自動検出する名前ではありません。Codex は配置済みの `AGENTS.md` を読みます。`AGENTS.override.md` は同じ階層の `AGENTS.md` を置き換えるため、追加ルールの保存先には使いません。詳細は [OpenAI の読込み仕様](https://developers.openai.com/ja-JP/docs/agent-configuration/agents-md) を参照してください。

### フェーズ 2: プロジェクトのセットアップ

1. プロジェクト用のディレクトリを作る
2. 本リポジトリの `.prompts/INIT.md` を、プロジェクトの `.prompts/INIT.md` へコピーする
3. コピーした INIT に要件、前提条件と制約、完了条件を書く
4. そのプロジェクトで Codex を起動し、`$project-bootstrap を使って .prompts/INIT.md を実行してください`と依頼する

**残りは Codex が行います。** `$project-bootstrap` が Git、除外設定、作業用ディレクトリ、文書索引、Beads を初期設定します。その後、要件に関係する現状を調査し、計画が必要な作業、複数セッションへまたがる作業、依存関係、ブロッカー、後続課題を Beads へ登録します。このスキルは状態を変更するため暗黙起動を無効にしています。Codex への依頼文に `$project-bootstrap` を含める必要があり、INIT 内の記載だけでは明示起動になりません。

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
| `scripts/setup-beads.sh` | macOS 向けの標準セットアップ。PC 固有ルールの結合にも対応 |
| `scripts/setup-local-rules.sh` | macOS 標準セットアップから呼ぶルール結合処理 |
| `scripts/beads-stop-nudge.sh` | macOS 向けの記録漏れ通知フック |
| `scripts/teardown-beads.ps1` | 管理要素の削除または導入前バックアップの復元 |
| `scripts/verify-beads.ps1` | 一時的な利用者領域を使う隔離検証 |
| `exclude` | 対象プロジェクトの `.git/info/exclude` へ追加する設定 |

## 補足

**更新時も同じセットアップを実行します。** 本リポジトリで最新を取り込んだ後、OS に合う次の手順を実行し、新しい Codex セッションを開始してください。PC 固有ルールがある場合、`git pull` だけでは生成済み `AGENTS.md` は更新されません。

Windows:

```powershell
git pull --ff-only
pwsh -NoProfile -File scripts/setup-beads.ps1
```

macOS:

```bash
git pull --ff-only
bash scripts/setup-beads.sh
```

PowerShell 版は、導入後に出力の `AGENTS.md` やスキルが直接変更されていれば、上書きせず中止します。macOS 版も管理対象と確認できない `AGENTS.md` を上書きしません。生成済みファイルではなく、共通原本または PC 固有原本を編集してください。pull が未コミット変更のために停止した場合は、その変更を保全し、上流とどちらの内容を採るか決めてから統合します。

**Auto-review はサンドボックスを解除しません。** `approval_policy` が未設定なら `on-request`、`approvals_reviewer` が未設定なら `auto_review` を利用者の `config.toml` へ追加します。既存値は上書きせず、Auto-review が有効にならない可能性を警告します。設定は新しい Codex セッションから有効です。Auto-review は承認対象の操作を別の審査エージェントへ送り、追加のモデル呼び出しを使います。高危険度操作、組織の管理方針、プロジェクト固有設定、サンドボックスの保護範囲を上書きする機能ではありません。

**計画と引き継ぎは Beads に集約します。** 複数セッションへまたがる作業では、親課題に現在の計画と決定事項、各課題に現在地を記録します。確定、仮決め、未決定と、確定させる条件・時点・判断主体を区別します。相談は会話内で行い、合意の内容と理由は Codex が記録します。Beads を使う場合は、同じ計画を `.prompts/PLANS` や `.prompts/DISCUSSIONS` へ重複して保存しません。

**このリポジトリも Beads で管理します。** `.beads-optout` は置かず、計画、実行状態、ブロッカーを Beads に記録します。`.beads/` は進捗データを含むため、取り消し処理や一時ファイル削除の対象にしません。

**通常の取り消しでは共通ルールと Codex 設定を残します。** Beads 統合、通知フック、2 つのスキルだけを削除する場合は、次を実行します。

```powershell
pwsh -NoProfile -File scripts/teardown-beads.ps1
```

導入前の `AGENTS.md`、`hooks.json`、`config.toml` を復元する場合は `-Restore` を付けます。セットアップ後に加えた変更も失われるため注意してください。

```powershell
pwsh -NoProfile -File scripts/teardown-beads.ps1 -Restore
```

**配布用 INIT の正本はひとつです。** Git 管理下の `.prompts/INIT.md` だけを更新します。計画と合意は Beads に記録し、調査報告、実行ログなどの作業資料は `.appendix` または `.logs` に置きます。公開用の `.prompts` 配下へ混在させません。

**Windows は PowerShell 7 以降、macOS は POSIX シェルに対応します。** セットアップスクリプトは `codex`、`bd`、`jq` の存在を確認します。

## 開発時の検証

```powershell
pwsh -NoProfile -File tests/run.ps1
pwsh -NoProfile -File scripts/verify-beads.ps1
```

macOS 向けの標準セットアップは次で検証できます。

```bash
bash tests/ShellSetup.Tests.sh
```

隔離検証は一時的な `HOME` と `CODEX_HOME` を使い、実際のグローバル環境を変更しません。PowerShell のテストは PowerShell 7 が必要です。検証範囲と読込み方式は [PC 固有ルールの検証記録](docs/reports/2026-09-20-local-rules.md) を参照してください。

## ライセンス

MIT License です。詳細は [LICENSE](LICENSE) を参照してください。

## 更新履歴

各版の詳細は [リリース](https://github.com/AllegroMoltoV/my-codex-rules/releases) を参照してください。

| バージョン | 日付 | 内容 |
|---|---|---|
| v1.15.0 | 2026-09-20 | Windows と macOS の標準セットアップで、任意の `AGENTS.local.md` の追加・更新・解除を統一。共通ルールへの結合と原本保持を検証し、導入・更新手順を明記 |
| v1.14.0 | 2026-09-20 | 計画の反証を 1 回までに制限し、修正やセッション切替え後の再反証を禁止。目的達成、実行可能性、安全性、完了条件に実質的な影響がある指摘へ集中し、些末な指摘による修正や相談を増やさない規則を追加 |
| v1.13.0 | 2026-09-20 | 計画、現在地、決定事項を Beads へ集約し、確定・仮決め・未決定と確定条件を記録する運用へ変更。TDD の順序を必須とせず、境界条件や失敗経路など必要な検証を優先。関連範囲の網羅的な調査と、利用者の意向・事実認識を区別する規則を整理 |
| v1.12.0 | 2026-09-13 | `project-bootstrap` を利用者の依頼文で明示起動する手順を README と INIT へ反映。Beads のステルス初期化後に `no-git-ops` を解除し、通常のローカル Git 操作を禁止しないよう変更 |
| v1.11.0 | 2026-09-08 | Claude Code 版 v2.15.0 と v2.16.0 の規則を Codex 向けに反映。調査は承認を待たずに済ませ、計画は前提が変わる検証までに絞る。日本語技術文書スキルでは、見出しと箇条書き・表の項目名に文や疑問形を使わず、体言止めなどのラベルを使う規則を明記 |
| v1.10.0 | 2026-09-05 | Claude Code 版 v2.14.0 の判断原則を Codex 向けに反映。利用者が「かもしれない」「気がする」などの留保を付けて述べたことを実行の指示として扱わず、そのまま着手しない。確認結果または対応案を示し、未決定の判断を利用者へ返す規則を追加 |
| v1.9.0 | 2026-09-04 | Claude Code 版 v2.12.0 と v2.13.0 の行動原則を Codex 向けに反映。設計書、コード、コメント、設定など現在状態を表す成果物では、古い内容を追記で補わず置換・削除・統合する。TDD を、挙動を 1 件ずつテストして失敗を確認し、実装後に外から見える挙動を保ったまま重複の除去と命名の見直しまで行う手順として明記 |
| v1.8.0 | 2026-09-03 | macOS 向けの POSIX シェル版セットアップを追加。共通ルールとスキルをシンボリックリンクで導入し、Beads の SessionStart と記録漏れ通知フックを設定する。隔離した利用者領域を使う統合テストで、フック設定の動作と冪等性を検証 |
| v1.7.0 | 2026-09-03 | Claude Code 版 v2.11.0 の Beads 記録規則を Codex 向けに反映。課題の notes を履歴ではなく現在状態のスナップショットとして扱い、古い記述は `bd update --notes` で書き換える。残す価値のある経緯は `docs/reports` へ移し、永続メモリは `bd remember --key` で同じ記録を上書きする規則を追加 |
| v1.6.0 | 2026-08-29 | Claude Code 版 v2.10.0 の反復手順の固定化原則を Codex 向けに反映。過去の記録で再現性を確認できた手順だけを対象とし、判断が残らない部分はスクリプト、判断が残る部分は `.agents/skills` 配下のスキルへ分離する。手順本文を `AGENTS.md` や `bd remember` へ置かず、再現手順の所在だけを記録する規則を追加 |
| v1.5.0 | 2026-08-22 | Claude Code 版 v2.9.1 の計画検証規則を Codex 向けに反映。親の会話履歴を継承しないサブエージェントに計画の失敗経路を反証させ、現在のセッションより低位のモデルを使わない要件を追加 |
| v1.4.0 | 2026-08-16 | 共通ルールを Codex 向けに圧縮。日本語技術文書スキル、override 検出、Auto-review の安全な既定設定、明示起動する project-bootstrap を追加 |
| v1.3.0 | 2026-08-08 | グローバル導入とプロジェクト初期設定を分離。共通ルールをグローバルへ導入し、README と INIT を二段階運用に合わせて短縮 |
| v1.2.0 | 2026-08-08 | 移設前の `Stop` フックの置き換え、エラーと証拠なしを区別する規則を追加 |
| v1.1.0 | 2026-08-08 | Beads 公式 Codex 統合、初回セットアップスキル、記録漏れ通知、隔離検証を追加 |
| v1.0.0 | 2026-07-20 | 事実の検証、調査、報告、文書、テストなどの行動原則を追加 |
| v0.2.0 | 2026-06-06 | 計画と承認、調査記録、TDD の規則を追加 |
| v0.1.0 | 2026-03-13 | 初版 |
