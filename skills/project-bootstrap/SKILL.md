---
name: project-bootstrap
description: Initialize a new or existing project after the user invokes a copied .prompts/INIT.md. Set up Git, local working directories, excludes, documentation index, and optional Beads tracking without generating shared AGENTS.md rules or INIT.md. Use when Codex is asked to execute the distributed INIT.md, prepare a project for first use, apply my-codex-rules project setup, or initialize Beads safely.
---

# プロジェクト初期セットアップ

このスキルは、グローバル初期設定を終えた端末で、別途作成した対象プロジェクトを初期設定する。共通ルールとこのスキル自体はグローバル領域から読み込まれている前提とする。

`.prompts/INIT.md` または利用者が `$project-bootstrap` を明示した場合だけ実行する。状態を変更するため、依頼文から暗黙に起動しない。

## 入力の確認

1. 対象ディレクトリを特定する。通常は現在の作業ディレクトリを使い、不明な場合だけ利用者へ確認する。
2. 対象の `.prompts/INIT.md` を読む。このファイルは利用者が配布元から手動でコピーし、要件を記入した入力である。
3. INIT に要件がない場合は、現在の利用者依頼から補完できるか確認する。どちらにも要件がない場合だけ記入を依頼して停止する。
4. 対象にプロジェクト固有の `AGENTS.md` がある場合は、その内容も確認する。

INIT とプロジェクト固有の `AGENTS.md` は作成または変更しない。

## 機械的な初期設定

スキル内の `scripts/bootstrap.ps1` を、スキルディレクトリからの相対パスで実行する。

```powershell
pwsh -NoProfile -File scripts/bootstrap.ps1 -TargetPath <対象ディレクトリ>
```

Beads を使わないよう利用者から指示された場合は、`-NoBeads` を付ける。`.beads-optout` がある場合も Beads を初期化しない。

`workspace-write` でも `.git/info/exclude` が保護される環境では、対象プロジェクトと上記の bootstrap コマンドに限定して権限昇格を求める。権限昇格を拒否された場合は成功扱いにせず、除外設定が未完了であることを報告する。サンドボックス全体は無効にしない。

スクリプトは次の処理だけを行う。

- Git が未初期化なら `main` ブランチで初期化する
- `.appendix`、`.tmp`、`.logs`、`.prompts`、`docs` と、その標準サブディレクトリを作成する
- `.git/info/exclude` へ不足項目だけを追加する
- `docs/INDEX.md` がなければ作成する
- オプトアウトされていなければ Beads を初期化する

既存ファイルは上書きしない。グローバル Codex 設定、コミット、push、`bd dolt push` は変更しない。

## 調査と作業の登録

初期設定後、要件に関係するファイル、Git 履歴、既存文書、依存関係を非破壊操作で確認する。調査結果を `docs/reports/` へ保存し、`docs/INDEX.md` に参照を追加する。

Beads を使うプロジェクトでは、計画が必要な作業、複数セッションへまたがる作業、依存関係、ブロッカー、後続課題を登録する。計画が不要な短時間の単発作業は登録しない。計画、実行状態、決定事項と合意の記録は、適用中の `AGENTS.md` が指定する役割に従って保持する。

調査後も利用者にしか決められない事項が残る場合は、判断材料、複数案、推奨案を会話内で示す。利用者の回答と承認範囲を正本へ反映し、回答に依存する実装は合意後に進める。Beads を使わない場合も、適用中の `AGENTS.md` が定める保存先で計画と合意を保持する。
