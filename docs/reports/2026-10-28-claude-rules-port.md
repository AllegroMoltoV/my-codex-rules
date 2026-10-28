# Claude Code 版の 2026 年 10 月変更の調査

## 対象

移植元は `my-claude-code-rules` の `ccd7ba6..75d1139`、移植先の調査基準は `my-codex-rules` の `3a2eb45` である。実質的な追加は `1ba434c`、`37cd6a9`、`00c00f8` の 3 コミットに含まれる。両リポジトリの追跡ファイル一覧、差分、関連するルール、スキル、セットアップ、テストを調べた。

## 変更内容と対応箇所

| 変更 | 移植先での対応箇所 |
|---|---|
| 記事の筋、引用、考察、改稿範囲の具体化と概要の文数制限の撤廃 | `skills/technical-blog-writing/SKILL.md` |
| 依頼者とプロダクト利用者の区別 | `rules/AGENTS.md` と関連するスキル |
| 一時制約の保存、決定の前提の見直し、影響による優先度 | `rules/AGENTS.md` の Beads 規則 |
| 常時読む規則の重複解消 | 共通ルールと日本語技術文書スキルの責務分担 |
| コマンド規約と Markdown 表記のフック | Codex のツール入力に合わせた実装と導入処理 |
| `BD_NO_GIT_OPS=false` の設定 | 既存の Codex 統合との差分確認が必要 |

## Codex への適応条件

調査環境のバージョンは Codex CLI 0.160.1、Beads 1.1.2 であった。Python 3 は利用できる。PowerShell は PATH 上に見つからなかった。

Codex の `PreToolUse` と `PostToolUse` では、シェル呼出しを `Bash`、パッチ編集を `apply_patch` として扱う。いずれも `tool_input.command` を使用する。Claude Code の `file_path`、`content`、`new_string` を前提とした Markdown 検査を、そのまま接続する方式では動作しない。フックには全ツールを網羅する保証がない。[公式のフック仕様](https://learn.chatgpt.com/docs/hooks)

既存の `scripts/beads-codex-hook.sh` は、公式フックの出力にある Git authority の文言を置換する。macOS のセットアップで使う一方、PowerShell のセットアップは公式統合を直接呼ぶ。公式統合によるコンテキスト注入と圧縮対応を独自実装で重ねる必要はない。

`bd prime` の対照実行では、環境変数が未設定の場合に Git 操作を禁止する authority が出力され、`BD_NO_GIT_OPS=false` を子プロセスへ渡した場合にその行が消えた。後者でもコミットと push を明示的な権限に限定する workflow が出力された。この観測は、リモートを持つ調査対象リポジトリでの結果である。

Codex のシェル設定には `shell_environment_policy.set` がある。ただし、この設定名の存在だけではフック子プロセスへの伝播まで証明できない。[公式の設定リファレンス](https://learn.chatgpt.com/docs/config-file/config-reference)

一時制約のキーに利用する識別子として、調査中の Codex プロセスには `CODEX_THREAD_ID` と `CODEX_SESSION_ID` が供給され、値も一致していた。Claude Code 専用の環境変数名、対応バージョン、クリア時の挙動を移植する根拠にはならない。

## 移植元フックの観測結果

移植元のスクリプトへ JSON を標準入力で渡し、終了状態と標準エラーを確認した。ファイルの変更は行っていない。

| 入力 | 結果 | 移植時の注意 |
|---|---|---|
| `printf %s git -C` | コマンドガードが終了コード 2 | 引数として渡した文字列を Git の実行と誤認する |
| `cd -- /tmp && pwd` | コマンドガードが終了コード 0 | 引数位置を固定した判定で見逃す |
| Markdown の編集断片 `print("値：")` | Markdown 検査が終了コード 2 | 断片だけの検査では既存コードフェンス内の編集を区別できない |

Codex では、ディレクトリの変更を別のシェル呼出しへ分ける案内より、実行ツールの作業ディレクトリ指定を案内する必要がある。Markdown 検査にも、追加した行と、その行が属する文書の構造を対応させる処理が必要である。

コードモードの `PostToolUse` で終了コード 2 を返すと、編集の実行後にツールの Promise が reject される。編集成功を維持する通知には、終了コード 0 と `hookSpecificOutput.additionalContext` を使う必要がある。[公式の事後フック仕様](https://learn.chatgpt.com/docs/hooks#posttooluse)

日本語技術文書スキルは通常のチャット、UI、チケット文案を対象外にしている。全 Markdown ファイルへの無条件な強制によって、この適用範囲を広げないことも必要である。

## 移植後の検証

macOS arm64、Codex CLI 0.160.1、Beads 1.1.2、Python 3.14、PowerShell 7.6.9 で確認した。PowerShell とスキル検証器の依存をテスト用の一時領域へ配置し、実利用の設定を変更していない。

| 対象 | 結果 |
|---|---|
| フックの挙動と登録 | Python の 17 テストが成功。引用されたコマンド文字列、編集後の文書構造、変更行の範囲、移設・重複防止、対象外パスを確認 |
| Windows 向けの呼出し | macOS 上の実 PowerShell で終了コード 0・2・7 と空白・引用符を含む引数の伝達を確認 |
| Windows 相当の文字コード | `PYTHONIOENCODING=cp932` の子プロセスへ日本語を含む UTF-8 JSON を渡し、阻止と指摘が動作することを確認 |
| macOS 標準セットアップ | 再実行、ローカル原本の追加・更新・解除、既存設定保持、規約フックの登録、Python 不足時の停止が成功 |
| PowerShell テスト | 51 テストが成功。変更済みフックの上書き拒否、解除時の保全も確認 |
| 実 Beads と Codex による隔離統合検証 | 導入、再実行、設定読込み、通常解除、完全復元、再導入が成功。実利用の設定のハッシュ一致を確認 |
| Codex の実ツール呼出し | `git -C /tmp status` が実行前に拒否された。`apply_patch` の編集状態は `completed` となり、追加行の全角記号がモデルへ通知された。ファイルの追記も確認 |
| Beads の圧縮対応 | 公式 `SessionStart`、`PreCompact`、`PostCompact`、`UserPromptSubmit` をラッパー経由で順に実行。開始時と圧縮後の入力時に、検証用の一時制約が出力へ含まれた |
| スキル形式 | `technical-blog-writing` と `japanese-technical-writing` の `quick_validate.py` が成功 |

Windows 用の PowerShell 呼出しには `exit $LASTEXITCODE` を付け、Python の終了コードを保持する。日本語 JSON を読むフックでは標準入出力を UTF-8 に固定する。これらを省いた状態での検証失敗を再現し、修正後の成功を確認した。

## 適応した範囲と限界

Claude Code の `settings.json`、`Write`・`Edit` の入力形式、専用のセッション ID、画像の読取り制限を移植していない。共通ルールと既存の Codex 用スキルを更新し、フックを `hooks.json`、`Bash`、`apply_patch` へ合わせた。文書検査の正確な対象範囲と未対応の構文は [README](../../README.md#規約フック) に記載している。

`BD_NO_GIT_OPS=false` は公式 Beads フックの子プロセスで未設定の場合だけ渡す。既存の値、標準入出力、終了状態を保つ。通常のシェルの環境まで変更する必要はないため、`shell_environment_policy.set` への追加を行わなかった。

Windows のネイティブ実機では実行していない。PowerShell と文字コードの対照実験を Windows 実機の検証と同一視しない。また、圧縮対応の検証は公式イベントの連続呼出しであり、長時間の会話を実際に圧縮した運用全体の保証ではない。
