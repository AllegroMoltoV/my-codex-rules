# Claude Code 版 v2.25.0 の反映

## 対象と採否

移植元の `75d1139..9ade3d5` (v2.24.1〜v2.25.0) を調査した。

| 移植元 | Codex 版の対応 |
|---|---|
| `rules/working-principles.md` | 口頭の打ち合わせを文案や計画へ入れる前の確認を共通ルールへ追加 |
| `rules/documentation.md` | 不要な強調と助詞「まで」の扱いを日本語技術文書スキルへ追加。用語の統一は既存規則で対応 |
| `skills/technical-blog-writing/SKILL.md` | 題名の主張、抜粋の範囲、執筆者の責任、図の選択、過去記事の紹介を反映。古い題名規則を置換 |
| `scripts/hooks/bash-guard.py`、`md-lint.py` | UTF-8 固定は既存実装で対応済み。変更不要 |
| `README.md` | Codex 版 v1.20.0 の更新履歴を追加 |

Codex 固有のスキル説明と呼出し範囲、Beads の参照、疑問節を避けた既存表現を維持した。

## 検証

- Python の既存テスト: 17 件中 16 件成功、PowerShell 依存の 1 件をスキップ。
- macOS 標準セットアップの既存テスト: 全 5 項目成功。PC 固有ルールの追加・更新・解除、再実行、依存不足時の保全を確認。
- 両スキルの `quick_validate.py`: 成功。PyYAML はリポジトリ内の仮想環境へ導入。
- `git diff --check`: 成功。

今回は実装コードを変更していない。PowerShell が未導入のため、PowerShell のテストと Windows 実機の検証を実施していない。

## この PC への反映

標準の `scripts/setup-beads.sh` を実行した。PC 固有原本と `config.toml` のハッシュ保持、生成済み共通ルールと原本の一致、3 スキルのリンク先、規約・通知フックの登録を確認した。
