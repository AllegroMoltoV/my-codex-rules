$repoRoot = Split-Path -Parent $PSScriptRoot
$bootstrapPath = Join-Path $repoRoot 'scripts\bootstrap.ps1'
$skillPath = Join-Path $repoRoot 'skills\project-bootstrap\SKILL.md'
$skillMetadataPath = Join-Path $repoRoot 'skills\project-bootstrap\agents\openai.yaml'

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

Invoke-TestCase 'NoBeadsとopt-outはBeadsを呼ばない' {
    Assert-PathExists $bootstrapPath
    $root = New-TestDirectory
    try {
        $gitDir = Join-Path $root '.git\info'
        [System.IO.Directory]::CreateDirectory($gitDir) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $root '.beads-optout'), '')
        & $bootstrapPath -TargetPath $root -BdCommand 'missing-bd-command'
        & $bootstrapPath -TargetPath $root -NoBeads -BdCommand 'missing-bd-command'
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

Invoke-TestCase '配布テンプレートが原本と一致する' {
    $pairs = @(
        @((Join-Path $repoRoot 'rules\AGENTS.md'), (Join-Path $repoRoot 'skills\project-bootstrap\assets\AGENTS.md')),
        @((Join-Path $repoRoot '.prompts\INIT.md'), (Join-Path $repoRoot 'skills\project-bootstrap\assets\INIT.md')),
        @((Join-Path $repoRoot 'exclude'), (Join-Path $repoRoot 'skills\project-bootstrap\assets\exclude'))
    )
    foreach ($pair in $pairs) {
        $source = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pair[0]))
        $asset = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pair[1]))
        Assert-Equal $source $asset "配布テンプレートが原本と一致しません: $($pair[0])"
    }
}

Invoke-TestCase 'READMEと配布ルールがBeadsの役割を一致して説明する' {
    $readme = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'README.md'))
    $rules = [System.IO.File]::ReadAllText((Join-Path $repoRoot 'rules\AGENTS.md'))
    $init = [System.IO.File]::ReadAllText((Join-Path $repoRoot '.prompts\INIT.md'))
    foreach ($contentItem in @($readme, $rules, $init)) {
        Assert-True ($contentItem.Contains('Beads')) 'Beadsの説明がありません。'
        Assert-True ($contentItem.Contains('.prompts/PLANS')) '計画ファイルの役割がありません。'
    }
    Assert-True (-not $readme.Contains('exclude` で置き換えて')) 'READMEに古いexclude置換手順が残っています。'
}