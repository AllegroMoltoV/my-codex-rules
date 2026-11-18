$repoRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $repoRoot 'scripts\bootstrap.ps1'
$skillPath = Join-Path $repoRoot 'skills\project-bootstrap\SKILL.md'
$skillMetadataPath = Join-Path $repoRoot 'skills\project-bootstrap\agents\openai.yaml'
$initPath = Join-Path $repoRoot '.prompts\INIT.md'
$duplicatedInitPath = Join-Path $repoRoot 'skills\project-bootstrap\assets\INIT.md'
$duplicatedAgentsPath = Join-Path $repoRoot 'skills\project-bootstrap\assets\AGENTS.md'

Invoke-TestCase 'INITは唯一の配布用正本としてproject-bootstrapを呼び出す' {
    Assert-PathExists $initPath
    $init = [System.IO.File]::ReadAllText($initPath)
    Assert-True ($init.Contains('$project-bootstrap を使って、このプロジェクトを初期セットアップしてください。')) 'INITにproject-bootstrapの呼び出しがありません。'
    Assert-True (-not [System.IO.File]::Exists($duplicatedInitPath)) 'スキル内にINITの複製があります。'
    Assert-True (-not [System.IO.File]::Exists($duplicatedAgentsPath)) 'スキル内に共通AGENTS.mdの複製があります。'
}

Invoke-TestCase 'INITは未発見時に明示起動と導入失敗を区別する' {
    $init = [System.IO.File]::ReadAllText($initPath)
    Assert-True ($init.Contains('依頼文に `$project-bootstrap` が直接含まれているか')) 'スキルが見つからない場合に明示起動を確認する案内がありません。'
    Assert-True ($init.Contains('直接指定されていても見つからない場合だけ')) '明示起動の失敗とグローバルセットアップ未完了を区別していません。'
}

Invoke-TestCase 'プロジェクト初期化は既存ファイルを上書きしない' {
    Assert-PathExists $bootstrapPath
    $root = New-TestDirectory
    try {
        [System.IO.Directory]::CreateDirectory((Join-Path $root '.prompts')) | Out-Null
        $agentsPath = Join-Path $root 'AGENTS.md'
        $initPath = Join-Path $root '.prompts\INIT.md'
        [System.IO.File]::WriteAllText($agentsPath, 'existing agents')
        [System.IO.File]::WriteAllText($initPath, 'existing init')
        [System.IO.Directory]::CreateDirectory((Join-Path $root 'docs')) | Out-Null
        $oldIndex = Join-Path $root 'docs\INDEX.md'
        [System.IO.File]::WriteAllText($oldIndex, 'existing docs index')
        [System.IO.Directory]::CreateDirectory((Join-Path $root '.reports')) | Out-Null
        $reportIndex = Join-Path $root '.reports\INDEX.md'
        [System.IO.File]::WriteAllText($reportIndex, 'existing report index')

        & $bootstrapPath -TargetPath $root -NoBeads

        Assert-Equal 'existing agents' ([System.IO.File]::ReadAllText($agentsPath)) '既存AGENTS.mdが変更されました。'
        Assert-Equal 'existing init' ([System.IO.File]::ReadAllText($initPath)) '既存INIT.mdが変更されました。'
        Assert-Equal 'existing docs index' ([System.IO.File]::ReadAllText($oldIndex)) '既存の docs 索引が変更されました。'
        Assert-Equal 'existing report index' ([System.IO.File]::ReadAllText($reportIndex)) '既存の調査索引が変更されました。'
        Assert-True (Test-Path -LiteralPath (Join-Path $root '.reports\INDEX.md')) '.reports/INDEX.mdが作成されませんでした。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'プロジェクト初期化は共通AGENTS.mdとINITを生成しない' {
    Assert-PathExists $bootstrapPath
    $root = New-TestDirectory
    try {
        & $bootstrapPath -TargetPath $root -NoBeads

        Assert-True (-not [System.IO.File]::Exists((Join-Path $root 'AGENTS.md'))) 'bootstrapが共通AGENTS.mdを生成しました。'
        Assert-True (-not [System.IO.File]::Exists((Join-Path $root '.prompts\INIT.md'))) 'bootstrapがINIT.mdを生成しました。'
        Assert-True ([System.IO.File]::Exists((Join-Path $root '.reports\INDEX.md'))) '.reports/INDEX.mdが作成されませんでした。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'NoBeadsとopt-outはBeadsを呼ばない' {
    Assert-PathExists $bootstrapPath
    $root = New-TestDirectory
    try {
        [System.IO.File]::WriteAllText((Join-Path $root '.beads-optout'), '')
        & $bootstrapPath -TargetPath $root -BdCommand 'missing-bd-command'
        Assert-True (-not [System.IO.File]::Exists((Join-Path $root '.prompts\INIT.md'))) 'bootstrapがINIT.mdを生成しました。'
        & $bootstrapPath -TargetPath $root -NoBeads -BdCommand 'missing-bd-command'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'Beads初期化前にローカル役割と除外設定を補う' {
    Assert-PathExists $bootstrapPath
    $root = New-TestDirectory
    try {
        $fakeBd = Join-Path $root 'fake-bd.ps1'
        [System.IO.File]::WriteAllText($fakeBd, "exit 0`n", [System.Text.Encoding]::ASCII)

        & $bootstrapPath -TargetPath $root -BdCommand $fakeBd

        $originalLocation = Get-Location
        try {
            Set-Location -LiteralPath $root
            $role = @(& git config --local --get beads.role)
            Assert-Equal 0 $LASTEXITCODE 'beads.roleを読み取れませんでした。'
            Assert-Equal 'maintainer' (($role -join '').Trim()) '未設定のbeads.roleがmaintainerになっていません。'
        }
        finally {
            Set-Location -LiteralPath $originalLocation
        }

        $exclude = [System.IO.File]::ReadAllText((Join-Path $root '.git\info\exclude'))
        Assert-True ($exclude.Contains('.beads/')) '.beads/がローカル除外設定にありません。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '調査レポートと索引を除外し再実行でも既存除外を保持する' {
    $root = New-TestDirectory
    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $root
        & git init -b main
        Assert-Equal 0 $LASTEXITCODE 'Git を初期化できませんでした。'
        & git config core.ignorecase false
        $excludePath = Join-Path $root '.git\info\exclude'
        [System.IO.File]::WriteAllText($excludePath, ".REPORTS/`nexisting-local.txt`n")
        & $bootstrapPath -TargetPath $root -NoBeads
        $before = [System.IO.File]::ReadAllText($excludePath)
        [System.IO.File]::WriteAllText((Join-Path $root '.reports\report.md'), 'private report')
        foreach ($path in @('.reports/INDEX.md', '.reports/report.md', 'existing-local.txt')) {
            & git check-ignore -q -- $path
            Assert-Equal 0 $LASTEXITCODE "Git の除外が無効です: $path"
        }
        $candidates = @(& git ls-files --others --exclude-standard -- .reports)
        Assert-Equal 0 $LASTEXITCODE '追跡候補を取得できませんでした。'
        Assert-Equal 0 $candidates.Count '調査記録が追跡候補へ出ています。'
        & $bootstrapPath -TargetPath $root -NoBeads
        Assert-Equal $before ([System.IO.File]::ReadAllText($excludePath)) '再実行で除外設定が変化しました。'
    }
    finally {
        Set-Location -LiteralPath $originalLocation
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

Invoke-TestCase '再包含された調査パスの除外に失敗したら索引を書き込まない' {
    foreach ($path in @('INDEX.md', 'report.md')) {
        $root = New-TestDirectory
        try {
            [System.IO.File]::WriteAllText((Join-Path $root '.gitignore'), "!.reports/`n!.reports/$path`n")
            $failure = $null
            try { & $bootstrapPath -TargetPath $root -NoBeads } catch { $failure = $_ }
            Assert-True ($null -ne $failure) '除外に失敗しても初期設定が成功しました。'
            Assert-True ($failure.Exception.Message.Contains('Git の除外を確認できない')) '別の原因で失敗しました。'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $root '.reports\INDEX.md'))) '除外が無効な状態で索引を書き込みました。'
        }
        finally { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

Invoke-TestCase 'worktreeで共有除外ファイルを解決し調査記録を除外する' {
    $root = New-TestDirectory
    $originalLocation = Get-Location
    try {
        Set-Location -LiteralPath $root
        & git init -b main
        & git -c user.name=AllegroMoltoV -c user.email=allegromoltov@example.example commit --allow-empty -m '検証用の初期コミット'
        Assert-Equal 0 $LASTEXITCODE '検証用コミットを作成できませんでした。'
        $worktree = Join-Path $root 'linked-worktree'
        & git worktree add --detach $worktree HEAD
        Assert-Equal 0 $LASTEXITCODE 'worktree を作成できませんでした。'
        & $bootstrapPath -TargetPath $worktree -NoBeads
        Set-Location -LiteralPath $worktree
        & git check-ignore -q -- .reports/INDEX.md
        Assert-Equal 0 $LASTEXITCODE 'worktree の索引が除外されていません。'
        Assert-PathExists (Join-Path $worktree '.reports\INDEX.md')
    }
    finally {
        Set-Location -LiteralPath $originalLocation
        Remove-Item -LiteralPath $root -Recurse -Force
    }
}

Invoke-TestCase 'Codexスキルのメタデータが仕様を満たす' {
    Assert-PathExists $skillPath
    Assert-PathExists $skillMetadataPath
    $content = [System.IO.File]::ReadAllText($skillPath)
    $frontmatterMatch = [regex]::Match($content, '(?s)^---\r?\n(?<yaml>.*?)\r?\n---')
    Assert-True $frontmatterMatch.Success 'SKILL.mdのfrontmatterがありません。'
    $keys = @([regex]::Matches($frontmatterMatch.Groups['yaml'].Value, '(?m)^(?<key>[a-zA-Z0-9_-]+):') | ForEach-Object { $_.Groups['key'].Value })
    Assert-Equal 2 $keys.Count 'frontmatterのキー数が不正です。'
    Assert-True ($keys -contains 'name') 'nameがありません。'
    Assert-True ($keys -contains 'description') 'descriptionがありません。'

    $metadata = [System.IO.File]::ReadAllText($skillMetadataPath)
    Assert-True ($metadata.Contains('display_name:')) 'display_nameがありません。'
    Assert-True ($metadata.Contains('short_description:')) 'short_descriptionがありません。'
    Assert-True ($metadata.Contains('default_prompt:')) 'default_promptがありません。'
    Assert-True ($metadata.Contains('$project-bootstrap')) 'default_promptにスキル名がありません。'
    Assert-True ($metadata.Contains('allow_implicit_invocation: false')) '状態を変更するスキルの暗黙起動が禁止されていません。'
}

Invoke-TestCase 'project-bootstrapは保護されたGit除外設定の扱いを説明する' {
    Assert-PathExists $skillPath
    $content = [System.IO.File]::ReadAllText($skillPath)
    Assert-True ($content.Contains('.git/info/exclude')) '.git/info/excludeの更新説明がありません。'
    Assert-True ($content.Contains('権限昇格')) '狭い権限昇格が必要になる場合の説明がありません。'
    Assert-True ($content.Contains('未完了')) '権限昇格が拒否された場合の報告方法がありません。'
}

Invoke-TestCase 'PowerShellファイルに構文エラーがない' {
    $paths = @()
    $paths += [System.IO.Directory]::GetFiles((Join-Path $repoRoot 'tests'), '*.ps1', [System.IO.SearchOption]::AllDirectories)
    if (Test-Path -LiteralPath (Join-Path $repoRoot 'scripts')) {
        $paths += [System.IO.Directory]::GetFiles((Join-Path $repoRoot 'scripts'), '*.ps1', [System.IO.SearchOption]::AllDirectories)
        $paths += [System.IO.Directory]::GetFiles((Join-Path $repoRoot 'scripts'), '*.psm1', [System.IO.SearchOption]::AllDirectories)
    }

    foreach ($path in $paths) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-Equal 0 $errors.Count "構文エラーがあります: $path"
    }
}

Invoke-TestCase '除外設定の配布テンプレートが原本と一致する' {
    $sourcePath = Join-Path $repoRoot 'exclude'
    $assetPath = Join-Path $repoRoot 'skills\project-bootstrap\assets\exclude'
    $source = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($sourcePath))
    $asset = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($assetPath))
    Assert-Equal $source $asset "配布テンプレートが原本と一致しません: $sourcePath"
}

Invoke-TestCase 'READMEは通常利用を二段階で説明する' {
    $readme = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'README.md'))
    Assert-True ($readme.Contains('フェーズ 1: グローバルの初回セットアップ')) 'グローバル導入のフェーズがありません。'
    Assert-True ($readme.Contains('フェーズ 2: プロジェクトのセットアップ')) 'プロジェクト初期設定のフェーズがありません。'
    Assert-True ($readme.Contains('scripts/setup-beads.ps1')) 'グローバル導入コマンドがありません。'
    Assert-True ($readme.Contains('.prompts/INIT.md')) 'INITのコピー元がありません。'
    Assert-True ($readme.Contains('`$project-bootstrap を使って .prompts/INIT.md を実行してください`')) '利用者の依頼文でproject-bootstrapを明示起動していません。'
    Assert-True (-not $readme.Contains('scripts/bootstrap.ps1 -TargetPath')) '内部bootstrapの直接実行が通常導線に残っています。'
}
