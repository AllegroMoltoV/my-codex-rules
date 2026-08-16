$repoRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repoRoot 'scripts\lib\BeadsSetup.psm1'
$setupPath = Join-Path $repoRoot 'scripts\setup-beads.ps1'
$teardownPath = Join-Path $repoRoot 'scripts\teardown-beads.ps1'
$verifyPath = Join-Path $repoRoot 'scripts\verify-beads.ps1'
$rulesPath = Join-Path $repoRoot 'rules\AGENTS.md'
$writingSkillPath = Join-Path $repoRoot 'skills\japanese-technical-writing\SKILL.md'

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

Invoke-TestCase '非空のグローバルoverrideを変更前に拒否する' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $codexHome = Join-Path $root 'codex-home'
        [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
        $agentsPath = Join-Path $codexHome 'AGENTS.md'
        $configPath = Join-Path $codexHome 'config.toml'
        $overridePath = Join-Path $codexHome 'AGENTS.override.md'
        [System.IO.File]::WriteAllText($agentsPath, 'preserve agents', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($configPath, "model = 'preserve'`r`n", [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText($overridePath, ' ', [System.Text.UTF8Encoding]::new($false))
        $agentsBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agentsPath))
        $configBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($configPath))

        $fakeCommand = Join-Path $root 'fake-command.cmd'
        [System.IO.File]::WriteAllText($fakeCommand, "@echo fake 1.0`r`n@exit /b 0`r`n", [System.Text.Encoding]::ASCII)
        $message = $null
        try {
            & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand
        }
        catch {
            $message = $_.Exception.Message
        }

        Assert-True (-not [string]::IsNullOrWhiteSpace($message)) '非空overrideで例外になりませんでした。'
        Assert-True ($message.Contains('AGENTS.override.md')) '例外にoverrideの名前がありません。'
        Assert-True ($message.Contains('AGENTS.md')) '例外に隠されるAGENTS.mdの説明がありません。'
        Assert-Equal $agentsBefore ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agentsPath))) '拒否時にAGENTS.mdが変わりました。'
        Assert-Equal $configBefore ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($configPath))) '拒否時にconfig.tomlが変わりました。'
        Assert-True (-not [System.IO.Directory]::Exists((Join-Path $codexHome 'my-codex-rules-beads'))) '拒否時に管理状態が作成されました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '0バイトのグローバルoverrideはセットアップを妨げない' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $codexHome = Join-Path $root 'codex-home'
        [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $codexHome 'AGENTS.override.md'), [byte[]]@())
        $fakeCommand = Join-Path $root 'fake-command.cmd'
        [System.IO.File]::WriteAllText($fakeCommand, "@echo fake 1.0`r`n@exit /b 0`r`n", [System.Text.Encoding]::ASCII)

        & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand

        Assert-True ([System.IO.File]::Exists((Join-Path $codexHome 'AGENTS.md'))) '0バイトoverrideがある環境でAGENTS.mdを導入できませんでした。'
        $config = [System.IO.File]::ReadAllText((Join-Path $codexHome 'config.toml'))
        Assert-True ($config.Contains('approvals_reviewer = "auto_review"')) '0バイトoverrideがある環境で承認設定を導入できませんでした。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '承認設定は既存TOMLを保持してルートへ不足値だけを追加する' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $configPath = Join-Path $root 'config.toml'
        $original = '# preserve comment' + [Environment]::NewLine +
            'model = "preserve-model"' + [Environment]::NewLine + [Environment]::NewLine +
            '[apps.example]' + [Environment]::NewLine +
            'approval_policy = "nested-value"' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($configPath, $original, [System.Text.UTF8Encoding]::new($false))

        $result = Add-CodexApprovalDefaults -ConfigPath $configPath

        $updated = [System.IO.File]::ReadAllText($configPath)
        Assert-True ($updated.Contains('# preserve comment')) '既存コメントが失われました。'
        Assert-True ($updated.Contains('model = "preserve-model"')) '既存のルート設定が失われました。'
        Assert-True ($updated.Contains('approval_policy = "nested-value"')) '別テーブルの同名設定が失われました。'
        $tableIndex = $updated.IndexOf('[apps.example]')
        Assert-True ($updated.IndexOf('approval_policy = "on-request"') -lt $tableIndex) 'approval_policyがルートへ追加されていません。'
        Assert-True ($updated.IndexOf('approvals_reviewer = "auto_review"') -lt $tableIndex) 'approvals_reviewerがルートへ追加されていません。'
        Assert-True $result.Changed '不足値を追加した結果が変更ありになっていません。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '既存の承認設定は上書きせず再実行でも変更しない' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $configPath = Join-Path $root 'config.toml'
        $original = 'approval_policy = "never"' + [Environment]::NewLine +
            'approvals_reviewer = "user"' + [Environment]::NewLine +
            'model = "preserve"' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($configPath, $original, [System.Text.UTF8Encoding]::new($false))

        $firstResult = Add-CodexApprovalDefaults -ConfigPath $configPath
        $firstHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($configPath)))
        $secondResult = Add-CodexApprovalDefaults -ConfigPath $configPath
        $secondHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($configPath)))

        Assert-Equal $original ([System.IO.File]::ReadAllText($configPath)) '既存の承認設定が変更されました。'
        Assert-Equal $firstHash $secondHash '再実行でconfig.tomlが変更されました。'
        Assert-True (-not $firstResult.Changed -and -not $secondResult.Changed) '既存値があるのに変更ありと報告されました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '承認設定は既存の一方を保持して不足する一方だけを追加する' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $configPath = Join-Path $root 'config.toml'
        $originalPolicy = 'approval_policy = "untrusted"'
        $original = $originalPolicy + [Environment]::NewLine + '[mcp_servers.example]' + [Environment]::NewLine + 'enabled = true' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($configPath, $original, [System.Text.UTF8Encoding]::new($false))

        $result = Add-CodexApprovalDefaults -ConfigPath $configPath

        $updated = [System.IO.File]::ReadAllText($configPath)
        Assert-Equal 1 ([regex]::Matches($updated, '(?m)^approval_policy\s*=').Count) '既存のapproval_policyが重複しました。'
        Assert-True ($updated.Contains($originalPolicy)) '既存のapproval_policyが上書きされました。'
        Assert-True ($updated.IndexOf('approvals_reviewer = "auto_review"') -lt $updated.IndexOf('[mcp_servers.example]')) '不足するapprovals_reviewerがルートへ追加されませんでした。'
        Assert-True ($result.ApprovalPolicyExisted -and -not $result.ApprovalPolicyMatchesDefault) '既存の非既定値を正しく報告していません。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '重複したルート承認設定は変更前に拒否する' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $configPath = Join-Path $root 'config.toml'
        $original = 'approval_policy = "on-request"' + [Environment]::NewLine + 'approval_policy = "never"' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($configPath, $original, [System.Text.UTF8Encoding]::new($false))
        $message = $null

        try {
            $null = Add-CodexApprovalDefaults -ConfigPath $configPath
        }
        catch {
            $message = $_.Exception.Message
        }

        Assert-True ($message -like '*重複*') '重複したルート設定を拒否しませんでした。'
        Assert-Equal $original ([System.IO.File]::ReadAllText($configPath)) '拒否時にconfig.tomlが変更されました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase 'コメント内の三重引用符をTOML構文として扱わない' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $configPath = Join-Path $root 'config.toml'
        $original = '# comment containing """ and approval settings' + [Environment]::NewLine +
            'approval_policy = "on-request"' + [Environment]::NewLine +
            'approvals_reviewer = "auto_review"' + [Environment]::NewLine +
            '[features]' + [Environment]::NewLine +
            'example = true' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($configPath, $original, [System.Text.UTF8Encoding]::new($false))

        $result = Add-CodexApprovalDefaults -ConfigPath $configPath

        Assert-True (-not $result.Changed) 'コメント内の三重引用符により既存設定を見失いました。'
        Assert-Equal $original ([System.IO.File]::ReadAllText($configPath)) 'コメントを含む既存config.tomlが変更されました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '単一行文字列内の三重引用符を複数行文字列として扱わない' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $configPath = Join-Path $root 'config.toml'
        $original = 'note = ''"""''' + [Environment]::NewLine +
            'approval_policy = "on-request"' + [Environment]::NewLine +
            'approvals_reviewer = "auto_review"' + [Environment]::NewLine
        [System.IO.File]::WriteAllText($configPath, $original, [System.Text.UTF8Encoding]::new($false))

        $result = Add-CodexApprovalDefaults -ConfigPath $configPath

        Assert-True (-not $result.Changed) '単一行文字列内の三重引用符により既存設定を見失いました。'
        Assert-Equal $original ([System.IO.File]::ReadAllText($configPath)) '単一行文字列を含む既存config.tomlが変更されました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '更新再実行の失敗は開始直前の管理状態へ戻す' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $codexHome = Join-Path $root 'codex-home'
        [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
        $fakeCommand = Join-Path $root 'fake-command.cmd'
        [System.IO.File]::WriteAllText($fakeCommand, "@echo fake 1.0`r`n@exit /b 0`r`n", [System.Text.Encoding]::ASCII)
        & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand

        $agentsPath = Join-Path $codexHome 'AGENTS.md'
        $configPath = Join-Path $codexHome 'config.toml'
        $hooksPath = Join-Path $codexHome 'hooks.json'
        $statePath = Join-Path $codexHome 'my-codex-rules-beads\state.json'
        [System.IO.File]::WriteAllText($hooksPath, '{invalid hooks', [System.Text.UTF8Encoding]::new($false))
        $agentsBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agentsPath))
        $configBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($configPath))
        $hooksBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($hooksPath))
        $stateBefore = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($statePath))
        $message = $null

        try {
            & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand
        }
        catch {
            $message = $_.Exception.Message
        }

        Assert-True (-not [string]::IsNullOrWhiteSpace($message)) '不正なhooks.jsonで更新再実行が失敗しませんでした。'
        Assert-True ([System.IO.File]::Exists($agentsPath)) '更新失敗後に導入済みAGENTS.mdが失われました。'
        Assert-Equal $agentsBefore ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($agentsPath))) '更新失敗後のAGENTS.mdが開始前と一致しません。'
        Assert-Equal $configBefore ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($configPath))) '更新失敗後のconfig.tomlが開始前と一致しません。'
        Assert-Equal $hooksBefore ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($hooksPath))) '更新失敗後のhooks.jsonが開始前と一致しません。'
        Assert-Equal $stateBefore ([Convert]::ToBase64String([System.IO.File]::ReadAllBytes($statePath))) '更新失敗後のstate.jsonが開始前と一致しません。'
        Assert-True ([System.IO.Directory]::Exists((Join-Path $root '.agents\skills\project-bootstrap'))) '更新失敗後にproject-bootstrapスキルが失われました。'
        Assert-True ([System.IO.Directory]::Exists((Join-Path $root '.agents\skills\japanese-technical-writing'))) '更新失敗後に日本語技術文書スキルが失われました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '通常取り消し後に変更されたAGENTS.mdを再導入で上書きしない' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $codexHome = Join-Path $root 'codex-home'
        [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
        $fakeCommand = Join-Path $root 'fake-command.cmd'
        [System.IO.File]::WriteAllText($fakeCommand, "@echo fake 1.0`r`n@exit /b 0`r`n", [System.Text.Encoding]::ASCII)
        & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand
        & $teardownPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand

        $agentsPath = Join-Path $codexHome 'AGENTS.md'
        $customContent = '利用者が通常取り消し後に変更した内容'
        [System.IO.File]::WriteAllText($agentsPath, $customContent, [System.Text.UTF8Encoding]::new($false))
        $message = $null
        try {
            & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand
        }
        catch {
            $message = $_.Exception.Message
        }

        Assert-True ($message -like '*変更されたグローバルAGENTS.md*') '通常取り消し後の利用者変更を拒否しませんでした。'
        Assert-Equal $customContent ([System.IO.File]::ReadAllText($agentsPath)) '通常取り消し後の利用者変更が上書きされました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}

Invoke-TestCase '完全復元後は導入前AGENTS.mdを確認して再導入できる' {
    Import-BeadsSetupModule
    $root = New-TestDirectory
    try {
        $codexHome = Join-Path $root 'codex-home'
        [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
        $agentsPath = Join-Path $codexHome 'AGENTS.md'
        $original = '導入前のAGENTS'
        [System.IO.File]::WriteAllText($agentsPath, $original, [System.Text.UTF8Encoding]::new($false))
        $fakeCommand = Join-Path $root 'fake-command.cmd'
        $fakeContent = [string]::Join([Environment]::NewLine, @('@echo fake 1.0', '@exit /b 0', ''))
        [System.IO.File]::WriteAllText($fakeCommand, $fakeContent, [System.Text.Encoding]::ASCII)

        & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand
        & $teardownPath -Restore -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand
        Assert-Equal $original ([System.IO.File]::ReadAllText($agentsPath)) '完全復元で導入前AGENTS.mdへ戻りませんでした。'

        & $setupPath -HomePath $root -CodexHome $codexHome -BdCommand $fakeCommand -JqCommand $fakeCommand -CodexCommand $fakeCommand

        Assert-True ([System.IO.File]::ReadAllText($agentsPath).Contains('## Project Rules')) '完全復元後に再導入できませんでした。'
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
    Assert-PathExists $verifyPath
}

Invoke-TestCase '隔離検証のCodex診断は一時プロジェクトを作業ディレクトリにする' {
    $verify = [System.IO.File]::ReadAllText($verifyPath)
    Assert-True ($verify.Contains('[System.IO.Path]::GetTempPath()')) '隔離検証領域が実リポジトリのACLを継承します。'
    Assert-True ($verify.Contains('Join-Path $doctorRoot ''.git''')) 'Codex診断用の隔離プロジェクト境界がありません。'
    Assert-True ($verify.Contains('codex -C $normalEnvironment.DoctorRoot doctor --json')) 'Codex診断の作業ディレクトリが隔離されていません。'
}

Invoke-TestCase 'グローバルセットアップは共通ルールを管理対象にする' {
    Assert-PathExists $rulesPath
    Assert-PathExists $writingSkillPath
    $setup = [System.IO.File]::ReadAllText($setupPath)
    Assert-True ($setup.Contains('rules\AGENTS.md')) 'グローバルルールの配布元がありません。'
    Assert-True ($setup.Contains('global_agents_digest')) 'グローバルAGENTS.mdの管理ハッシュがありません。'
    Assert-True ($setup.Contains('japanese_technical_writing_digest')) '日本語技術文書スキルの管理ハッシュがありません。'
}
