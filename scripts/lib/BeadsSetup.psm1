Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ManagedFileNames = @('AGENTS.md', 'hooks.json', 'config.toml')

function ConvertTo-CanonicalJsonValue {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        $keys = @($Value.Keys)
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        foreach ($key in $keys) {
            $result[[string]$key] = ConvertTo-CanonicalJsonValue -Value $Value[$key]
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $items.Add((ConvertTo-CanonicalJsonValue -Value $item))
        }
        return ,@($items)
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        $names = @($Value.PSObject.Properties | ForEach-Object { $_.Name })
        [Array]::Sort($names, [System.StringComparer]::Ordinal)
        foreach ($name in $names) {
            $result[$name] = ConvertTo-CanonicalJsonValue -Value $Value.PSObject.Properties[$name].Value
        }
        return $result
    }
    return $Value
}
function Write-Utf8JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $InputObject
    )

    $directory = Split-Path -Parent $Path
    if ($directory) {
        [System.IO.Directory]::CreateDirectory($directory) | Out-Null
    }

    $canonicalValue = ConvertTo-CanonicalJsonValue -Value $InputObject
    $json = $canonicalValue | ConvertTo-Json -Depth 100
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::ReadAllText($temporaryPath) | ConvertFrom-Json | Out-Null
        [System.IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Remove-TomlComment {
    param([string]$Line)

    $quote = [char]0
    $escaped = $false
    for ($index = 0; $index -lt $Line.Length; $index++) {
        $character = $Line[$index]
        if ($quote -eq [char]0) {
            if ($character -eq '#') {
                return $Line.Substring(0, $index)
            }
            if ($character -eq '"' -or $character -eq "'") {
                $quote = $character
            }
            continue
        }

        if ($quote -eq '"' -and $character -eq '\' -and -not $escaped) {
            $escaped = $true
            continue
        }
        if ($character -eq $quote -and -not $escaped) {
            $quote = [char]0
        }
        $escaped = $false
    }
    return $Line
}

function Get-TomlOpenMultilineDelimiter {
    param([string]$Code)

    $state = 'Normal'
    $delimiter = $null
    $escaped = $false
    for ($index = 0; $index -lt $Code.Length; $index++) {
        $character = $Code[$index]
        $threeCharacters = if ($index + 2 -lt $Code.Length) { $Code.Substring($index, 3) } else { $null }

        if ($state -eq 'Multiline') {
            if ($threeCharacters -eq $delimiter) {
                $state = 'Normal'
                $delimiter = $null
                $index += 2
            }
            continue
        }
        if ($state -eq 'Basic') {
            if ($character -eq '\' -and -not $escaped) {
                $escaped = $true
                continue
            }
            if ($character -eq '"' -and -not $escaped) {
                $state = 'Normal'
            }
            $escaped = $false
            continue
        }
        if ($state -eq 'Literal') {
            if ($character -eq "'") {
                $state = 'Normal'
            }
            continue
        }

        if ($threeCharacters -eq '"""' -or $threeCharacters -eq "'''") {
            $state = 'Multiline'
            $delimiter = $threeCharacters
            $index += 2
        }
        elseif ($character -eq '"') {
            $state = 'Basic'
        }
        elseif ($character -eq "'") {
            $state = 'Literal'
        }
    }

    if ($state -eq 'Multiline') {
        return $delimiter
    }
    return $null
}

function Add-CodexApprovalDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath
    )

    $content = if ([System.IO.File]::Exists($ConfigPath)) {
        [System.IO.File]::ReadAllText($ConfigPath)
    }
    else {
        ''
    }
    $newLine = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = @($content -split '\r?\n', 0)
    $firstTableLine = $lines.Count
    $approvalLines = [System.Collections.Generic.List[string]]::new()
    $reviewerLines = [System.Collections.Generic.List[string]]::new()
    $multilineDelimiter = $null

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($null -ne $multilineDelimiter) {
            if ($line.Contains($multilineDelimiter)) {
                $multilineDelimiter = $null
            }
            continue
        }

        $code = Remove-TomlComment -Line $line
        $multilineDelimiter = Get-TomlOpenMultilineDelimiter -Code $code

        if ($code -match '^\s*\[\[?[^\]]+\]\]?\s*$') {
            $firstTableLine = $index
            break
        }
        if ($code -match '^\s*(?:approval_policy|"approval_policy"|''approval_policy'')\s*=') {
            $approvalLines.Add($line)
        }
        if ($code -match '^\s*(?:approvals_reviewer|"approvals_reviewer"|''approvals_reviewer'')\s*=') {
            $reviewerLines.Add($line)
        }
    }

    if ($approvalLines.Count -gt 1) {
        throw "config.tomlのルートにapproval_policyが重複しています: $ConfigPath"
    }
    if ($reviewerLines.Count -gt 1) {
        throw "config.tomlのルートにapprovals_reviewerが重複しています: $ConfigPath"
    }

    $approvalMatchesDefault = $approvalLines.Count -eq 0 -or $approvalLines[0] -match '^\s*(?:approval_policy|"approval_policy"|''approval_policy'')\s*=\s*["'']on-request["'']\s*(?:#.*)?$'
    $reviewerMatchesDefault = $reviewerLines.Count -eq 0 -or $reviewerLines[0] -match '^\s*(?:approvals_reviewer|"approvals_reviewer"|''approvals_reviewer'')\s*=\s*["'']auto_review["'']\s*(?:#.*)?$'
    $missingLines = [System.Collections.Generic.List[string]]::new()
    if ($approvalLines.Count -eq 0) {
        $missingLines.Add('approval_policy = "on-request"')
    }
    if ($reviewerLines.Count -eq 0) {
        $missingLines.Add('approvals_reviewer = "auto_review"')
    }

    if ($missingLines.Count -gt 0) {
        $rootLines = [System.Collections.Generic.List[string]]::new()
        for ($index = 0; $index -lt $firstTableLine; $index++) {
            $rootLines.Add($lines[$index])
        }
        while ($rootLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($rootLines[$rootLines.Count - 1])) {
            $rootLines.RemoveAt($rootLines.Count - 1)
        }
        if ($rootLines.Count -gt 0) {
            $rootLines.Add('')
        }
        foreach ($line in $missingLines) {
            $rootLines.Add($line)
        }
        if ($firstTableLine -lt $lines.Count) {
            $rootLines.Add('')
            for ($index = $firstTableLine; $index -lt $lines.Count; $index++) {
                $rootLines.Add($lines[$index])
            }
        }

        $updated = [string]::Join($newLine, $rootLines)
        if (-not $updated.EndsWith($newLine, [System.StringComparison]::Ordinal)) {
            $updated += $newLine
        }
        $directory = Split-Path -Parent $ConfigPath
        if ($directory) {
            [System.IO.Directory]::CreateDirectory($directory) | Out-Null
        }
        $temporaryPath = "$ConfigPath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            [System.IO.File]::WriteAllText($temporaryPath, $updated, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::Move($temporaryPath, $ConfigPath, $true)
        }
        finally {
            if (Test-Path -LiteralPath $temporaryPath) {
                Remove-Item -LiteralPath $temporaryPath -Force
            }
        }
    }

    return [pscustomobject]@{
        ApprovalPolicyExisted = $approvalLines.Count -eq 1
        ApprovalPolicyMatchesDefault = $approvalMatchesDefault
        ApprovalsReviewerExisted = $reviewerLines.Count -eq 1
        ApprovalsReviewerMatchesDefault = $reviewerMatchesDefault
        Changed = $missingLines.Count -gt 0
    }
}

function Get-JsonProperty {
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return $InputObject.PSObject.Properties[$Name]
}

function Set-JsonProperty {
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        $Value
    )

    $property = Get-JsonProperty -InputObject $InputObject -Name $Name
    if ($null -eq $property) {
        $InputObject | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
    else {
        $property.Value = $Value
    }
}

function Remove-JsonProperty {
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -ne (Get-JsonProperty -InputObject $InputObject -Name $Name)) {
        $InputObject.PSObject.Properties.Remove($Name)
    }
}

function Read-HooksFile {
    param(
        [Parameter(Mandatory)]
        [string]$HooksPath
    )

    if (-not (Test-Path -LiteralPath $HooksPath)) {
        return [pscustomobject]@{
            description = 'Codex lifecycle hooks.'
            hooks = [pscustomobject]@{}
        }
    }

    $content = [System.IO.File]::ReadAllText($HooksPath)
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw "hooks.jsonが空です: $HooksPath"
    }

    $configuration = $content | ConvertFrom-Json
    if ($configuration -is [System.Array]) {
        throw "hooks.jsonのルートはオブジェクトである必要があります: $HooksPath"
    }

    $hooksProperty = Get-JsonProperty -InputObject $configuration -Name 'hooks'
    if ($null -eq $hooksProperty) {
        Set-JsonProperty -InputObject $configuration -Name 'hooks' -Value ([pscustomobject]@{})
    }
    elseif ($null -eq $hooksProperty.Value -or $hooksProperty.Value -is [System.Array]) {
        throw "hooks.jsonのhooksはオブジェクトである必要があります: $HooksPath"
    }

    return $configuration
}

function Test-BeadsStopNudgeCommand {
    param(
        [AllowNull()]
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return $false
    }

    return $Command -match '(?i)(?:^|[\\/])beads-stop-nudge\.ps1"?\s*$'
}

function Add-BeadsStopHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HooksPath,

        [Parameter(Mandatory)]
        [string]$Command
    )

    $configuration = Read-HooksFile -HooksPath $HooksPath
    $stopProperty = Get-JsonProperty -InputObject $configuration.hooks -Name 'Stop'
    $groups = if ($null -eq $stopProperty) { @() } else { @($stopProperty.Value) }

    $remainingGroups = [System.Collections.Generic.List[object]]::new()
    foreach ($group in $groups) {
        $handlersProperty = Get-JsonProperty -InputObject $group -Name 'hooks'
        if ($null -eq $handlersProperty) {
            $remainingGroups.Add($group)
            continue
        }

        $remainingHandlers = @(
            foreach ($handler in @($handlersProperty.Value)) {
                $commandProperty = Get-JsonProperty -InputObject $handler -Name 'command'
                $commandValue = if ($null -eq $commandProperty) { $null } else { [string]$commandProperty.Value }
                if (-not (Test-BeadsStopNudgeCommand -Command $commandValue) -and $commandValue -ne $Command) {
                    $handler
                }
            }
        )

        if ($remainingHandlers.Count -gt 0) {
            Set-JsonProperty -InputObject $group -Name 'hooks' -Value $remainingHandlers
            $remainingGroups.Add($group)
        }
    }

    $managedGroup = [pscustomobject]@{
        hooks = @(
            [pscustomobject]@{
                type = 'command'
                command = $Command
                timeout = 30
                statusMessage = 'Checking Beads progress'
            }
        )
    }

    Set-JsonProperty -InputObject $configuration.hooks -Name 'Stop' -Value (@($remainingGroups) + @($managedGroup))
    Write-Utf8JsonFile -Path $HooksPath -InputObject $configuration
}

function Remove-BeadsStopHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HooksPath,

        [Parameter(Mandatory)]
        [string]$Command
    )

    if (-not (Test-Path -LiteralPath $HooksPath)) {
        return
    }

    $configuration = Read-HooksFile -HooksPath $HooksPath
    $stopProperty = Get-JsonProperty -InputObject $configuration.hooks -Name 'Stop'
    if ($null -eq $stopProperty) {
        return
    }

    $remainingGroups = [System.Collections.Generic.List[object]]::new()
    $changed = $false
    foreach ($group in @($stopProperty.Value)) {
        $handlersProperty = Get-JsonProperty -InputObject $group -Name 'hooks'
        if ($null -eq $handlersProperty) {
            $remainingGroups.Add($group)
            continue
        }

        $remainingHandlers = @(
            foreach ($handler in @($handlersProperty.Value)) {
                $commandProperty = Get-JsonProperty -InputObject $handler -Name 'command'
                $commandValue = if ($null -eq $commandProperty) { $null } else { [string]$commandProperty.Value }
                if ((Test-BeadsStopNudgeCommand -Command $commandValue) -or $commandValue -eq $Command) {
                    $changed = $true
                }
                else {
                    $handler
                }
            }
        )

        if ($remainingHandlers.Count -gt 0) {
            Set-JsonProperty -InputObject $group -Name 'hooks' -Value $remainingHandlers
            $remainingGroups.Add($group)
        }
    }

    if (-not $changed) {
        return
    }

    if ($remainingGroups.Count -eq 0) {
        Remove-JsonProperty -InputObject $configuration.hooks -Name 'Stop'
    }
    else {
        Set-JsonProperty -InputObject $configuration.hooks -Name 'Stop' -Value @($remainingGroups)
    }

    Write-Utf8JsonFile -Path $HooksPath -InputObject $configuration
}

function New-BeadsBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CodexHome,

        [Parameter(Mandatory)]
        [string]$BackupRoot
    )

    $resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
    $resolvedBackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
    if (Test-Path -LiteralPath $resolvedBackupRoot) {
        $existingItems = [System.IO.Directory]::GetFileSystemEntries($resolvedBackupRoot)
        if ($existingItems.Count -gt 0) {
            throw "バックアップ先が空ではありません: $resolvedBackupRoot"
        }
    }

    [System.IO.Directory]::CreateDirectory($resolvedBackupRoot) | Out-Null
    $filesDirectory = Join-Path $resolvedBackupRoot 'files'
    [System.IO.Directory]::CreateDirectory($filesDirectory) | Out-Null
    $entries = [System.Collections.Generic.List[object]]::new()

    foreach ($name in $script:ManagedFileNames) {
        $sourcePath = Join-Path $resolvedCodexHome $name
        $backupPath = Join-Path $filesDirectory $name
        $exists = [System.IO.File]::Exists($sourcePath)
        if ($exists) {
            [System.IO.File]::WriteAllBytes($backupPath, [System.IO.File]::ReadAllBytes($sourcePath))
        }

        $entries.Add([pscustomobject]@{
            name = $name
            existed = $exists
        })
    }

    $manifest = [pscustomobject]@{
        version = 1
        codex_home = $resolvedCodexHome
        created_at = [DateTimeOffset]::UtcNow.ToString('o')
        files = @($entries)
    }
    $manifestPath = Join-Path $resolvedBackupRoot 'manifest.json'
    Write-Utf8JsonFile -Path $manifestPath -InputObject $manifest
    return $manifestPath
}

function Restore-BeadsBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    $resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
    if (-not [System.IO.File]::Exists($resolvedManifestPath)) {
        throw "バックアップ記録がありません: $resolvedManifestPath"
    }

    $manifest = [System.IO.File]::ReadAllText($resolvedManifestPath) | ConvertFrom-Json
    if ($manifest.version -ne 1) {
        throw "未対応のバックアップ形式です: $($manifest.version)"
    }

    $codexHome = [System.IO.Path]::GetFullPath([string]$manifest.codex_home)
    [System.IO.Directory]::CreateDirectory($codexHome) | Out-Null
    $backupRoot = Split-Path -Parent $resolvedManifestPath
    $seenNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in @($manifest.files)) {
        $name = [string]$entry.name
        if ($script:ManagedFileNames -notcontains $name -or -not $seenNames.Add($name)) {
            throw "不正なバックアップ対象名です: $name"
        }

        $destinationPath = Join-Path $codexHome $name
        if ([bool]$entry.existed) {
            $backupPath = Join-Path (Join-Path $backupRoot 'files') $name
            if (-not [System.IO.File]::Exists($backupPath)) {
                throw "バックアップファイルがありません: $backupPath"
            }
            [System.IO.File]::WriteAllBytes($destinationPath, [System.IO.File]::ReadAllBytes($backupPath))
        }
        elseif ([System.IO.File]::Exists($destinationPath)) {
            Remove-Item -LiteralPath $destinationPath -Force
        }
    }

    if ($seenNames.Count -ne $script:ManagedFileNames.Count) {
        throw 'バックアップ記録に必要な対象がそろっていません。'
    }
}

function Test-ExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-BeadsManagedPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$HomePath,

        [Parameter(Mandatory)]
        [string]$CodexHome
    )

    $resolvedHome = [System.IO.Path]::GetFullPath($HomePath)
    $resolvedCodexHome = [System.IO.Path]::GetFullPath($CodexHome)
    $runtimeRoot = Join-Path $resolvedCodexHome 'my-codex-rules-beads'
    return [pscustomobject]@{
        HomePath = $resolvedHome
        CodexHome = $resolvedCodexHome
        HooksPath = Join-Path $resolvedCodexHome 'hooks.json'
        RuntimeRoot = $runtimeRoot
        NudgeScriptPath = Join-Path $runtimeRoot 'beads-stop-nudge.ps1'
        StatePath = Join-Path $runtimeRoot 'state.json'
        BackupRoot = Join-Path $runtimeRoot 'backup'
        ProjectBootstrapPath = Join-Path $resolvedHome '.agents\skills\project-bootstrap'
        JapaneseTechnicalWritingPath = Join-Path $resolvedHome '.agents\skills\japanese-technical-writing'
        BeadsSkillPath = Join-Path $resolvedHome '.agents\skills\beads'
    }
}

Export-ModuleMember -Function @(
    'Add-CodexApprovalDefaults',
    'Add-BeadsStopHook',
    'Get-BeadsManagedPaths',
    'New-BeadsBackup',
    'Remove-BeadsStopHook',
    'Restore-BeadsBackup',
    'Test-ExternalCommand',
    'Write-Utf8JsonFile'
)
