$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'scripts\lib\BeadsSetup.psm1'
$setupPath = Join-Path $repoRoot 'scripts\setup-beads.ps1'
$teardownPath = Join-Path $repoRoot 'scripts\teardown-beads.ps1'

function Import-BeadsSetupModule {
    Assert-PathExists $modulePath
    Import-Module $modulePath -Force
}

Invoke-TestCase '依存コマンド不足を変更前に拒否する' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $codexHome = Join-Path $root 'codex-home'
        [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
        $sentinel = Join-Path $codexHome 'AGENTS.md'
        [System.IO.File]::WriteAllText($sentinel, 'preserve', [System.Text.UTF8Encoding]::new($false))
        $before = [System.IO.File]::ReadAllBytes($sentinel)

        Assert-PathExists $setupPath
        $threw = $false
        try {
            & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand 'missing-bd-command' -JqCommand 'missing-jq-command' -CodexCommand 'missing-codex-command'
        }
        catch {
            $threw = $true
        }

        Assert-True $threw '依存コマンド不足で例外になりませんでした。'
        $after = [System.IO.File]::ReadAllBytes($sentinel)
        Assert-Equal ([Convert]::ToBase64String($before)) ([Convert]::ToBase64String($after)) '依存確認失敗時に既存設定が変わりました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'Stopフックの追加は既存要素を保持し冪等である' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $hooksPath = Join-Path $root 'hooks.json'
        $existing = [ordered]@{
            description = 'preserve'
            hooks = [ordered]@{
                Stop = @(
                    [ordered]@{
                        hooks = @(
                            [ordered]@{
                                type = 'command'
                                command = 'echo preserve-this-hook'
                            }
                        )
                    }
                )
            }
        }
        [System.IO.File]::WriteAllText($hooksPath, ($existing | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

        Add-BeadsStopHook -HooksPath $hooksPath -Command 'pwsh -File C:\managed\beads-stop-nudge.ps1'
        $firstHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($hooksPath)))
        Add-BeadsStopHook -HooksPath $hooksPath -Command 'pwsh -File C:\managed\beads-stop-nudge.ps1'
        $secondHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($hooksPath)))
        Assert-Equal $firstHash $secondHash '再実行後のhooks.jsonハッシュが変わりました。'

        $parsed = [System.IO.File]::ReadAllText($hooksPath) | ConvertFrom-Json
        $commands = @($parsed.hooks.Stop.hooks.command)
        Assert-Equal 1 (@($commands | Where-Object { $_ -eq 'echo preserve-this-hook' }).Count) '既存フックが失われました。'
        Assert-Equal 1 (@($commands | Where-Object { $_ -eq 'pwsh -File C:\managed\beads-stop-nudge.ps1' }).Count) '管理フックが重複しました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'Stopフックの追加は移設前の管理フックを現在のパスへ置き換える' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $hooksPath = Join-Path $root 'hooks.json'
        $oldCommand = 'pwsh -NoProfile -File "D:\old-codex\my-codex-rules-beads\beads-stop-nudge.ps1"'
        $currentCommand = 'pwsh -NoProfile -File "C:\current-codex\my-codex-rules-beads\beads-stop-nudge.ps1"'
        $data = [ordered]@{
            hooks = [ordered]@{
                Stop = @(
                    [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = $oldCommand }) },
                    [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = 'echo preserve' }) }
                )
            }
        }
        [System.IO.File]::WriteAllText($hooksPath, ($data | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

        Add-BeadsStopHook -HooksPath $hooksPath -Command $currentCommand

        $parsed = [System.IO.File]::ReadAllText($hooksPath) | ConvertFrom-Json
        $commands = @($parsed.hooks.Stop.hooks.command)
        Assert-Equal 2 $commands.Count '置き換え後のフック数が不正です。'
        Assert-Equal 0 (@($commands | Where-Object { $_ -eq $oldCommand }).Count) '移設前の管理フックが残りました。'
        Assert-Equal 1 (@($commands | Where-Object { $_ -eq $currentCommand }).Count) '現在の管理フックが1件になっていません。'
        Assert-Equal 1 (@($commands | Where-Object { $_ -eq 'echo preserve' }).Count) '利用者のフックが失われました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '通常の取り消しは管理フックだけを削除する' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $hooksPath = Join-Path $root 'hooks.json'
        $data = [ordered]@{
            hooks = [ordered]@{
                Stop = @(
                    [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = 'echo preserve' }) },
                    [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = 'pwsh -File C:\managed\beads-stop-nudge.ps1' }) }
                )
            }
        }
        [System.IO.File]::WriteAllText($hooksPath, ($data | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

        Remove-BeadsStopHook -HooksPath $hooksPath -Command 'pwsh -File C:\managed\beads-stop-nudge.ps1'

        $parsed = [System.IO.File]::ReadAllText($hooksPath) | ConvertFrom-Json
        $commands = @($parsed.hooks.Stop.hooks.command)
        Assert-Equal 1 $commands.Count '取り消し後のフック数が不正です。'
        Assert-Equal 'echo preserve' $commands[0] '利用者のフックが失われました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '通常の取り消しは移設前の管理フックも削除する' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $hooksPath = Join-Path $root 'hooks.json'
        $oldCommand = 'pwsh -NoProfile -File "D:\old-codex\my-codex-rules-beads\beads-stop-nudge.ps1"'
        $currentCommand = 'pwsh -NoProfile -File "C:\current-codex\my-codex-rules-beads\beads-stop-nudge.ps1"'
        $data = [ordered]@{
            hooks = [ordered]@{
                Stop = @(
                    [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = 'echo preserve' }) },
                    [ordered]@{ hooks = @([ordered]@{ type = 'command'; command = $oldCommand }) }
                )
            }
        }
        [System.IO.File]::WriteAllText($hooksPath, ($data | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))

        Remove-BeadsStopHook -HooksPath $hooksPath -Command $currentCommand

        $parsed = [System.IO.File]::ReadAllText($hooksPath) | ConvertFrom-Json
        $commands = @($parsed.hooks.Stop.hooks.command)
        Assert-Equal 1 $commands.Count '取り消し後のフック数が不正です。'
        Assert-Equal 'echo preserve' $commands[0] '利用者のフックが失われました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'バックアップ復元は存在状態とバイト列を戻す' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $codexHome = Join-Path $root 'codex-home'
        $backupRoot = Join-Path $root 'backup'
        [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
        $agentsPath = Join-Path $codexHome 'AGENTS.md'
        $hooksPath = Join-Path $codexHome 'hooks.json'
        $original = [byte[]](0xEF, 0xBB, 0xBF, 0x41, 0x0D, 0x0A)
        [System.IO.File]::WriteAllBytes($agentsPath, $original)

        $manifestPath = New-BeadsBackup -CodexHome $codexHome -BackupRoot $backupRoot
        [System.IO.File]::WriteAllText($agentsPath, 'changed')
        [System.IO.File]::WriteAllText($hooksPath, '{}')

        Restore-BeadsBackup -ManifestPath $manifestPath

        $restored = [System.IO.File]::ReadAllBytes($agentsPath)
        Assert-Equal ([Convert]::ToBase64String($original)) ([Convert]::ToBase64String($restored)) '元ファイルのバイト列が一致しません。'
        Assert-True (-not (Test-Path -LiteralPath $hooksPath)) '導入前に存在しなかったファイルが残りました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'セットアップと取り消しのスクリプトが存在する' {
    Assert-PathExists $setupPath
    Assert-PathExists $teardownPath
}
