[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tmp\beads-integration-' + [guid]::NewGuid().ToString('N'))
$actualHome = if ($env:USERPROFILE) { [System.IO.Path]::GetFullPath($env:USERPROFILE) } else { [System.IO.Path]::GetFullPath($env:HOME) }
$actualCodexHome = if ($env:CODEX_HOME) { [System.IO.Path]::GetFullPath($env:CODEX_HOME) } else { Join-Path $actualHome '.codex' }

function Assert-Condition {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Assert-Same {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Get-FileHashOrState {
    param([string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return 'missing' }
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path)))
}

function Get-DirectoryHashOrState {
    param([string]$Path)
    if (-not [System.IO.Directory]::Exists($Path)) { return 'missing' }
    $builder = [System.Text.StringBuilder]::new()
    $files = [System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)
    [Array]::Sort($files, [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $files) {
        [void]$builder.Append([System.IO.Path]::GetRelativePath($Path, $file).Replace('\', '/'))
        [void]$builder.Append("`n")
        [void]$builder.Append((Get-FileHashOrState -Path $file))
        [void]$builder.Append("`n")
    }
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($builder.ToString())))
}

function Get-UserSnapshot {
    return [ordered]@{
        agents = Get-FileHashOrState -Path (Join-Path $actualCodexHome 'AGENTS.md')
        hooks = Get-FileHashOrState -Path (Join-Path $actualCodexHome 'hooks.json')
        config = Get-FileHashOrState -Path (Join-Path $actualCodexHome 'config.toml')
        beads_skill = Get-DirectoryHashOrState -Path (Join-Path $actualHome '.agents\skills\beads')
        bootstrap_skill = Get-DirectoryHashOrState -Path (Join-Path $actualHome '.agents\skills\project-bootstrap')
        metrics = Get-FileHashOrState -Path (Join-Path $actualHome '.config\bd\config.yaml')
    }
}

function Assert-SnapshotsEqual {
    param($Expected, $Actual, [string]$Context)
    foreach ($key in $Expected.Keys) {
        Assert-Same $Expected[$key] $Actual[$key] "${Context}で実利用者領域が変わりました: ${key}"
    }
}

function New-IsolatedEnvironment {
    param(
        [string]$Name,
        [switch]$ConfigMissing
    )
    $root = Join-Path $testRoot $Name
    $isolatedHome = Join-Path $root 'home'
    $codexHome = Join-Path $root 'codex-home'
    [System.IO.Directory]::CreateDirectory($isolatedHome) | Out-Null
    [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
    [System.IO.File]::WriteAllBytes((Join-Path $codexHome 'AGENTS.md'), [byte[]](0xEF, 0xBB, 0xBF, 0x70, 0x72, 0x65, 0x73, 0x65, 0x72, 0x76, 0x65, 0x0D, 0x0A))
    $hooks = '{"description":"preserve","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo preserve-this-hook"}]}]}}'
    [System.IO.File]::WriteAllText((Join-Path $codexHome 'hooks.json'), $hooks, [System.Text.UTF8Encoding]::new($false))
    if (-not $ConfigMissing) {
        [System.IO.File]::WriteAllText((Join-Path $codexHome 'config.toml'), "model = 'preserve-model'`r`n", [System.Text.UTF8Encoding]::new($false))
    }
    return [pscustomobject]@{ Root = $root; Home = $isolatedHome; CodexHome = $codexHome }
}

function Get-ManagedSnapshot {
    param($Environment)
    return [ordered]@{
        agents = Get-FileHashOrState -Path (Join-Path $Environment.CodexHome 'AGENTS.md')
        hooks = Get-FileHashOrState -Path (Join-Path $Environment.CodexHome 'hooks.json')
        config = Get-FileHashOrState -Path (Join-Path $Environment.CodexHome 'config.toml')
        beads_skill = Get-DirectoryHashOrState -Path (Join-Path $Environment.Home '.agents\skills\beads')
        bootstrap_skill = Get-DirectoryHashOrState -Path (Join-Path $Environment.Home '.agents\skills\project-bootstrap')
        nudge = Get-FileHashOrState -Path (Join-Path $Environment.CodexHome 'my-codex-rules-beads\beads-stop-nudge.ps1')
    }
}

function Invoke-WithEnvironment {
    param(
        $Environment,
        [scriptblock]$Action
    )
    $oldHome = $env:HOME
    $oldUserProfile = $env:USERPROFILE
    $oldCodexHome = $env:CODEX_HOME
    try {
        $env:HOME = $Environment.Home
        $env:USERPROFILE = $Environment.Home
        $env:CODEX_HOME = $Environment.CodexHome
        & $Action
    }
    finally {
        $env:HOME = $oldHome
        $env:USERPROFILE = $oldUserProfile
        $env:CODEX_HOME = $oldCodexHome
    }
}

function Invoke-Setup {
    param($Environment)
    & (Join-Path $repoRoot 'scripts\setup-beads.ps1') -HomePath $Environment.Home -CodexHome $Environment.CodexHome
}

function Invoke-Teardown {
    param($Environment, [switch]$Restore)
    & (Join-Path $repoRoot 'scripts\teardown-beads.ps1') -HomePath $Environment.Home -CodexHome $Environment.CodexHome -Restore:$Restore
}

function Invoke-NudgeProcess {
    param(
        [string]$WorkingDirectory,
        [bool]$StopHookActive
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command pwsh).Source
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add((Join-Path $repoRoot 'scripts\beads-stop-nudge.ps1'))
    $startInfo.ArgumentList.Add('-StaleMinutes')
    $startInfo.ArgumentList.Add('0')
    $startInfo.ArgumentList.Add('-CooldownMinutes')
    $startInfo.ArgumentList.Add('0')
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $payload = [pscustomobject]@{
        session_id = 'verify-session'
        cwd = $WorkingDirectory
        hook_event_name = 'Stop'
        model = 'verify-model'
        stop_hook_active = $StopHookActive
        turn_id = 'verify-turn'
        last_assistant_message = $null
    } | ConvertTo-Json -Compress
    $process.StandardInput.Write($payload)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Assert-Same 0 $process.ExitCode 'Stopフックの終了コードが不正です。'
    Assert-Condition ([string]::IsNullOrWhiteSpace($stderr)) "Stopフックが標準エラーを出力しました: $stderr"
    return $stdout
}

$beforeUser = Get-UserSnapshot
[System.IO.Directory]::CreateDirectory($testRoot) | Out-Null
Write-Host "隔離検証領域: $testRoot"

try {
    $normalEnvironment = New-IsolatedEnvironment -Name 'normal'
    Invoke-Setup -Environment $normalEnvironment
    $afterFirstSetup = Get-ManagedSnapshot -Environment $normalEnvironment
    Assert-Condition ($afterFirstSetup.beads_skill -ne 'missing') '公式Beadsスキルが配置されませんでした。'
    Assert-Condition ($afterFirstSetup.bootstrap_skill -ne 'missing') 'project-bootstrapスキルが配置されませんでした。'
    Assert-Condition ($afterFirstSetup.nudge -ne 'missing') '記録漏れ通知スクリプトが配置されませんでした。'

    $hooksPath = Join-Path $normalEnvironment.CodexHome 'hooks.json'
    $hooksObject = [System.IO.File]::ReadAllText($hooksPath) | ConvertFrom-Json
    $allCommands = @(
        foreach ($eventProperty in $hooksObject.hooks.PSObject.Properties) {
            foreach ($group in @($eventProperty.Value)) {
                foreach ($handler in @($group.hooks)) {
                    [string]$handler.command
                }
            }
        }
    )
    Assert-Same 1 (@($allCommands | Where-Object { $_ -eq 'echo preserve-this-hook' }).Count) '既存フックが保持されませんでした。'
    Assert-Same 1 (@($allCommands | Where-Object { $_ -like '*beads-stop-nudge.ps1*' }).Count) '独自Stopフックが重複または欠落しています。'
    Assert-Condition ($allCommands -contains 'bd codex-hook SessionStart') '公式SessionStartフックがありません。'
    Assert-Condition (([System.IO.File]::ReadAllText((Join-Path $normalEnvironment.Home '.config\bd\config.yaml'))).Contains('disabled: true')) '隔離環境の匿名利用統計が停止されませんでした。'

    Invoke-Setup -Environment $normalEnvironment
    $afterSecondSetup = Get-ManagedSnapshot -Environment $normalEnvironment
    foreach ($key in $afterFirstSetup.Keys) {
        Assert-Same $afterFirstSetup[$key] $afterSecondSetup[$key] "再実行後のハッシュが変わりました: $key"
    }

    $projectPath = Join-Path $normalEnvironment.Root 'project'
    [System.IO.Directory]::CreateDirectory($projectPath) | Out-Null
    Invoke-WithEnvironment -Environment $normalEnvironment -Action {
        & (Join-Path $repoRoot 'scripts\bootstrap.ps1') -TargetPath $projectPath
        Assert-Condition ([System.IO.Directory]::Exists((Join-Path $projectPath '.beads'))) 'bootstrapでBeadsが初期化されませんでした。'
        Assert-Condition ([System.IO.File]::Exists((Join-Path $projectPath 'AGENTS.md'))) 'bootstrapでAGENTS.mdが配置されませんでした。'
        Assert-Condition ([System.IO.File]::Exists((Join-Path $projectPath '.prompts\INIT.md'))) 'bootstrapでINIT.mdが配置されませんでした。'
        Assert-Condition ([System.IO.File]::Exists((Join-Path $projectPath 'docs\INDEX.md'))) 'bootstrapで文書索引が配置されませんでした。'

        $originalLocation = Get-Location
        try {
            Set-Location -LiteralPath $projectPath
            $firstOutput = @(& bd create '隔離検証の親課題' --type task --priority P1 --silent)
            Assert-Same 0 $LASTEXITCODE '親課題の作成に失敗しました。'
            $firstId = [string]$firstOutput[$firstOutput.Count - 1]
            $secondOutput = @(& bd create '隔離検証の子課題' --type task --priority P2 --deps $firstId --silent)
            Assert-Same 0 $LASTEXITCODE '子課題の作成に失敗しました。'
            $secondId = [string]$secondOutput[$secondOutput.Count - 1]
            & bd update $firstId --claim
            Assert-Same 0 $LASTEXITCODE '課題のclaimに失敗しました。'
            & bd note $firstId '隔離検証で進捗を記録'
            Assert-Same 0 $LASTEXITCODE '課題のnoteに失敗しました。'
            & bd remember '隔離検証では外部pushを行わない' --key verify-no-push
            Assert-Same 0 $LASTEXITCODE 'rememberに失敗しました。'
            $prime = @(& bd prime)
            Assert-Same 0 $LASTEXITCODE 'bd primeに失敗しました。'
            Assert-Condition (($prime -join "`n").Contains('verify-no-push') -or ($prime -join "`n").Contains('外部push')) 'bd primeに記憶が含まれませんでした。'

            $nudgeOutput = Invoke-NudgeProcess -WorkingDirectory $projectPath -StopHookActive $false
            $nudgeObject = $nudgeOutput | ConvertFrom-Json
            Assert-Same 'block' $nudgeObject.decision 'Stopフックが未更新課題を通知しませんでした。'
            $repeatOutput = Invoke-NudgeProcess -WorkingDirectory $projectPath -StopHookActive $true
            Assert-Condition ([string]::IsNullOrWhiteSpace($repeatOutput)) 'stop_hook_activeで通知が抑止されませんでした。'

            & bd close $firstId --reason '隔離検証が成功した。'
            Assert-Same 0 $LASTEXITCODE '親課題のcloseに失敗しました。'
            & bd close $secondId --reason '依存関係の検証が成功した。'
            Assert-Same 0 $LASTEXITCODE '子課題のcloseに失敗しました。'
        }
        finally {
            Set-Location -LiteralPath $originalLocation
        }
    }

    Import-Module (Join-Path $repoRoot 'scripts\lib\BeadsSetup.psm1') -Force
    Add-BeadsStopHook -HooksPath $hooksPath -Command 'echo user-added-after-setup'
    Invoke-Teardown -Environment $normalEnvironment
    $afterNormalRemoval = [System.IO.File]::ReadAllText($hooksPath) | ConvertFrom-Json
    $remainingCommands = @(
        foreach ($group in @($afterNormalRemoval.hooks.Stop)) {
            foreach ($handler in @($group.hooks)) { [string]$handler.command }
        }
    )
    Assert-Condition ($remainingCommands -contains 'echo preserve-this-hook') '通常取り消しで既存フックが失われました。'
    Assert-Condition ($remainingCommands -contains 'echo user-added-after-setup') '通常取り消しで導入後の利用者フックが失われました。'
    Assert-Condition (-not ($remainingCommands | Where-Object { $_ -like '*beads-stop-nudge.ps1*' })) '通常取り消し後も独自フックが残っています。'

    $restoreEnvironment = New-IsolatedEnvironment -Name 'restore' -ConfigMissing
    $restoreBefore = Get-ManagedSnapshot -Environment $restoreEnvironment
    Invoke-Setup -Environment $restoreEnvironment
    [System.IO.File]::AppendAllText((Join-Path $restoreEnvironment.CodexHome 'AGENTS.md'), 'user change after setup')
    Invoke-Teardown -Environment $restoreEnvironment -Restore
    $restoreAfter = Get-ManagedSnapshot -Environment $restoreEnvironment
    Assert-Same $restoreBefore.agents $restoreAfter.agents 'AGENTS.mdがバイト単位で復元されませんでした。'
    Assert-Same $restoreBefore.hooks $restoreAfter.hooks 'hooks.jsonがバイト単位で復元されませんでした。'
    Assert-Same 'missing' $restoreAfter.config '導入前に存在しなかったconfig.tomlが残りました。'
    Assert-Same 'missing' $restoreAfter.beads_skill '公式Beadsスキルが取り消されませんでした。'
    Assert-Same 'missing' $restoreAfter.bootstrap_skill 'project-bootstrapスキルが取り消されませんでした。'

    $afterUser = Get-UserSnapshot
    Assert-SnapshotsEqual -Expected $beforeUser -Actual $afterUser -Context '隔離統合検証'

    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    $resolvedExpectedParent = [System.IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp'))
    Assert-Condition ($resolvedTestRoot.StartsWith($resolvedExpectedParent + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) '一時領域の削除先が不正です。'
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    Write-Host '隔離統合検証は成功しました。'
}
catch {
    Write-Host "隔離統合検証は失敗しました。一時領域を保持します: $testRoot"
    throw
}
