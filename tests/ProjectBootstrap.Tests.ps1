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

Invoke-TestCase 'プロジェクト初期化は既存ファイルを上書きしない' {
    Assert-PathExists $bootstrapPath
    $root = New-TestDirectory
    try {
        $gitDir = Join-Path $root '.git\info'
        [System.IO.Directory]::CreateDirectory($gitDir) | Out-Null
        [System.IO.Directory]::CreateDirectory((Join-Path $root '.prompts')) | Out-Null
        $agentsPath = Join-Path $root 'AGENTS.md'
        $initPath = Join-Path $root '.prompts\INIT.md'
        [System.IO.File]::WriteAllText($agentsPath, 'existing agents')
        [System.IO.File]::WriteAllText($initPath, 'existing init')

        & $bootstrapPath -TargetPath $root -NoBeads

        Assert-Equal 'existing agents' ([System.IO.File]::ReadAllText($agentsPath)) '既存AGENTS.mdが変更されました。'
        Assert-Equal 'existing init' ([System.IO.File]::ReadAllText($initPath)) '既存INIT.mdが変更されました。'
        Assert-True (Test-Path -LiteralPath (Join-Path $root 'docs\INDEX.md')) 'docs/INDEX.mdが作成されませんでした。'
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
        $gitDir = Join-Path $root '.git\info'
        [System.IO.Directory]::CreateDirectory($gitDir) | Out-Null

        & $bootstrapPath -TargetPath $root -NoBeads

        Assert-True (-not [System.IO.File]::Exists((Join-Path $root 'AGENTS.md'))) 'bootstrapが共通AGENTS.mdを生成しました。'
        Assert-True (-not [System.IO.File]::Exists((Join-Path $root '.prompts\INIT.md'))) 'bootstrapがINIT.mdを生成しました。'
        Assert-True ([System.IO.File]::Exists((Join-Path $root 'docs\INDEX.md'))) 'docs/INDEX.mdが作成されませんでした。'
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
        $gitDir = Join-Path $root '.git\info'
        [System.IO.Directory]::CreateDirectory($gitDir) | Out-Null
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
        $fakeBd = Join-Path $root 'fake-bd.cmd'
        [System.IO.File]::WriteAllText($fakeBd, "@exit /b 0`r`n", [System.Text.Encoding]::ASCII)

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
    Assert-True ($readme.Contains('`.prompts/INIT.md` を実行してください')) 'INITの実行依頼がありません。'
    Assert-True (-not $readme.Contains('scripts/bootstrap.ps1 -TargetPath')) '内部bootstrapの直接実行が通常導線に残っています。'
}
