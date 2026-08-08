---
name: project-bootstrap
description: Initialize an existing or new Git repository with the distributed Codex AGENTS.md rules, local working directories, approval prompts, documentation index, and optional Beads task tracking. Use when Codex is asked to prepare a project for first use, apply my-codex-rules, create the standard project workspace, or initialize Beads without overwriting existing project files.
---

# プロジェクト初期セットアップ

既存ファイルを保持しながら、Codex の配布ルール、作業用ディレクトリ、承認用プロンプト、文書索引、Beads データベースを初期設定する。

## 初期設定の実行

1. 対象ディレクトリを特定する。対象が不明な場合だけ利用者へ確認する。
2. 対象の `AGENTS.md`、`.git/info/exclude`、`.prompts/INIT.md`、`docs/INDEX.md`、`.beads-optout` の有無を確認する。
3. スキル内の `scripts/bootstrap.ps1` を、スキルディレクトリからの相対パスで実行する。

```powershell
pwsh -NoProfile -File scripts/bootstrap.ps1 -TargetPath <対象ディレクトリ>
```

Beads を使わないよう利用者から指示された場合は、`-NoBeads` を付ける。`.beads-optout` がある場合も Beads を初期化しない。

このスクリプトは既存の `AGENTS.md`、`.prompts/INIT.md`、`docs/INDEX.md` を上書きしない。`.git/info/exclude` には不足項目だけを追加する。グローバル Codex 統合、コミット、push は行わない。

## 要件の確認と調査

初期設定後、対象の `.prompts/INIT.md` と `AGENTS.md` を読む。要件欄が未記入でも、現在の利用者依頼に明確な要件がある場合は、その内容を要件欄へ記録して調査を続ける。利用者依頼にも要件がない場合だけ、記入を依頼して停止する。

要件がある場合は、ファイル、Git 履歴、既存文書、依存関係を非破壊操作で確認する。調査結果を `docs/reports/` へ保存し、`docs/INDEX.md` に参照を追加する。

## Beads への登録

複数セッションへまたがる作業、依存関係、ブロッカー、後続課題だけを Beads へ登録する。回答だけの依頼や短時間で完了する単発作業は登録しない。

着手時は `bd update <id> --claim`、事実が判明した時点は `bd note <id> <内容>`、完了時は検証結果を含む `bd close <id> --reason <理由>` を使う。継続的な決定は `bd remember` に記録する。`bd dolt push` は利用者から明示的に指示された場合だけ実行する。

## 質問と承認

調査後も利用者にしか決められない事項が残る場合は、推奨案を含む複数案を `.prompts/QUESTIONS.md` へ保存する。利用者へ回答を依頼し、回答を得るまで実装へ進まない。

新たな実装計画が必要な場合は `AGENTS.md` の計画、懸念事項、承認フローに従う。計画ファイルは設計と承認の記録、Beads は実行状態と依存関係の正本として扱う。