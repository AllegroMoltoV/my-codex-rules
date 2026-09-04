$repoRoot = Split-Path -Parent $PSScriptRoot
$rulesPath = Join-Path $repoRoot 'rules\AGENTS.md'
$writingSkillPath = Join-Path $repoRoot 'skills\japanese-technical-writing\SKILL.md'
$writingSkillMetadataPath = Join-Path $repoRoot 'skills\japanese-technical-writing\agents\openai.yaml'

Invoke-TestCase '共通ルールはCodexの既定上限以下である' {
    Assert-PathExists $rulesPath
    $size = [System.Text.Encoding]::UTF8.GetByteCount([System.IO.File]::ReadAllText($rulesPath))
    Assert-True ($size -le 32768) "rules/AGENTS.mdが32 KiBを超えています: $size bytes"
}

Invoke-TestCase '共通ルールはテスト結果を実装と環境から切り分ける' {
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    Assert-True (-not $rules.Contains('coverage を 100% に近づけてください')) 'coverage率そのものを目的にする規則が残っています。'
    Assert-True ($rules.Contains('テストの失敗原因')) 'テスト失敗を切り分ける規則がありません。'
    Assert-True ($rules.Contains('実装、テスト、環境')) '実装、テスト、環境の切り分けが明記されていません。'
}

Invoke-TestCase '共通ルールは診断価値がある実行だけログ保存を求める' {
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    Assert-True (-not $rules.Contains('シェルスクリプトの標準出力と標準エラーは')) '全シェル出力を無条件に保存する規則が残っています。'
    Assert-True ($rules.Contains('長時間')) '長時間実行のログ保存条件がありません。'
    Assert-True ($rules.Contains('再実行が難しい')) '再実行困難な処理のログ保存条件がありません。'
    Assert-True ($rules.Contains('診断価値')) '診断価値に基づくログ保存条件がありません。'
}

Invoke-TestCase '共通ルールはコマンド承認の判定境界を説明する' {
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    Assert-True ($rules.Contains('完全な接頭辞')) '許可ルールの接頭辞一致が説明されていません。'
    Assert-True ($rules.Contains('複合コマンド')) '複合コマンドの分割条件が説明されていません。'
    Assert-True ($rules.Contains('サンドボックス')) '許可ルールとサンドボックスの違いが説明されていません。'
}

Invoke-TestCase '共通ルールは実証済みの反復だけをCodex向けに固定化する' {
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    Assert-True ($rules.Contains('繰り返しが確定した手順だけを固定化する')) '固定化の原則がありません。'
    Assert-True ($rules.Contains('過去に同じ手順を実行した記録')) '反復を過去の記録で確認する条件がありません。'
    Assert-True ($rules.Contains('固定化できる対象を探すための振り返りや棚卸し')) '固定化のための棚卸しが禁止されていません。'
    Assert-True ($rules.Contains('入力が決まれば出力も決まる部分')) '決定的な部分だけを切り出す条件がありません。'
    Assert-True ($rules.Contains('スクリプトか 1 つのコマンド')) '判断が残らない手順の置き場所がありません。'
    Assert-True ($rules.Contains('.agents/skills/<名前>/SKILL.md')) 'Codex用スキルの置き場所がありません。'
    Assert-True (-not $rules.Contains('.claude/skills/')) 'Claude Code用スキルの置き場所が混入しています。'
    Assert-True ($rules.Contains('手順の本文を、常時読み込まれる')) '手順本文を常時読み込ませない規則がありません。'
    Assert-True ($rules.Contains('再現手順の所在')) '永続メモリへ記録する対象が手順本文ではなく所在に限定されていません。'
}

Invoke-TestCase '共通ルールはBeadsの記録を現在状態のスナップショットとして保つ' {
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    Assert-True ($rules.Contains('課題の notes と `bd remember` の永続メモリ')) '課題のnotesと永続メモリを現在状態として扱う原則がありません。'
    Assert-True ($rules.Contains('現在状態の記録')) 'Beadsの記録が現在状態であることを明記していません。'
    Assert-True ($rules.Contains('bd update <id> --notes')) '古いnotesを書き換えるコマンドがありません。'
    Assert-True ($rules.Contains('残す価値のある経緯')) '残す価値のある経緯の扱いがありません。'
    Assert-True ($rules.Contains('docs/reports')) '経緯の退避先がありません。'
    Assert-True ($rules.Contains('bd history')) 'Beads履歴を安全網にしない理由がありません。'
    Assert-True ($rules.Contains('bd gc')) '履歴を失う操作としてbd gcが明記されていません。'
    Assert-True ($rules.Contains('bd flatten')) '履歴を失う操作としてbd flattenが明記されていません。'
    Assert-True ($rules.Contains('bd remember')) '永続メモリの更新規則がありません。'
    Assert-True ($rules.Contains('`--key`')) '永続メモリを同じキーで上書きする規則がありません。'
}

Invoke-TestCase '共通ルールは現在状態を表す成果物から古い内容を除く' {
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    Assert-True ($rules.Contains('成果物は現在の状態として保つ')) '成果物を現在状態として保つ原則がありません。'
    Assert-True ($rules.Contains('設計書、仕様書、計画書、コード、コメント、設定')) '現在状態として扱う成果物の範囲がありません。'
    Assert-True ($rules.Contains('置換・削除・統合')) '古い内容を置き換える方法がありません。'
    Assert-True ($rules.Contains('条件分岐、フォールバック、ラッパー')) '既存処理を迂回する追加が禁止されていません。'
    Assert-True ($rules.Contains('実装と一致しなくなったコメント')) '古いコメントの扱いがありません。'
    Assert-True ($rules.Contains('互換性、移行、環境差の吸収、安全対策、履歴の保存')) '現在も必要な要件を残す例外がありません。'
    Assert-True ($rules.Contains('依頼された作業で触れる範囲')) '無関係な箇所へ変更を広げない制限がありません。'
}

Invoke-TestCase '共通ルールはTDDを失敗確認からリファクタリングまでの手順として示す' {
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    Assert-True (-not $rules.Contains('開発は原則として TDD で行ってください')) '名前だけでTDDを指示する古い規則が残っています。'
    Assert-True ($rules.Contains('満たすべき挙動を 1 件ずつテスト')) '挙動を1件ずつテストにする手順がありません。'
    Assert-True ($rules.Contains('失敗を確かめてから実装')) '実装前にテストの失敗を確認する手順がありません。'
    Assert-True ($rules.Contains('外から見える挙動を変えないまま')) 'リファクタリング中に挙動を保つ条件がありません。'
    Assert-True ($rules.Contains('重複の除去と命名の見直し')) 'リファクタリングの具体的な作業がありません。'
    Assert-True ($rules.Contains('ここまでで 1 周')) 'リファクタリングまでを1周とする境界がありません。'
    Assert-True ($rules.Contains('理由を添えて作業前に利用者へ相談')) 'TDDが適さない場合の相談方法がありません。'
}

Invoke-TestCase '日本語技術文書の詳細規則はスキルとして分離される' {
    Assert-PathExists $writingSkillPath
    Assert-PathExists $writingSkillMetadataPath
    $rules = [System.IO.File]::ReadAllText($rulesPath)
    $skill = [System.IO.File]::ReadAllText($writingSkillPath)
    $metadata = [System.IO.File]::ReadAllText($writingSkillMetadataPath)
    Assert-True (-not $rules.Contains('## Documentation')) '日本語技術文書の詳細規則が共通ルールに残っています。'
    Assert-True ($rules.Contains('ユーザーへの応答は日本語で書いてください')) '全出力に必要な日本語規則が共通ルールから失われています。'
    Assert-True ($rules.Contains('不自然な半角スペース')) '全出力に必要な空白規則が共通ルールから失われています。'
    Assert-True ($skill.Contains('日本語の技術文書')) '日本語技術文書を対象とする説明がありません。'
    Assert-True ($skill.Contains('全角かっこ')) '移動対象の表記規則がスキルにありません。'
    Assert-True ($metadata.Contains('$japanese-technical-writing')) '既定プロンプトにスキル名がありません。'
}
