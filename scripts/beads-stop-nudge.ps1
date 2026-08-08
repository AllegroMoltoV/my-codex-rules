[CmdletBinding()]
param(
    [switch]$LibraryMode,
    [ValidateRange(0, 1440)]
    [int]$StaleMinutes = 15,
    [ValidateRange(0, 1440)]
    [int]$CooldownMinutes = 15
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-BeadsStopDecision {
    [CmdletBinding()]
    param(
        $InputObject,
        [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow,
        [ValidateRange(0, 1440)]
        [int]$StaleMinutes = 15,
        [ValidateRange(0, 1440)]
        [int]$CooldownMinutes = 15,
        [scriptblock]$RepositoryCheck,
        [scriptblock]$IssueProvider,
        [string]$CooldownDirectory = $(Join-Path ([System.IO.Path]::GetTempPath()) 'my-codex-rules-beads-nudge')
    )

    try {
        if ($null -eq $InputObject -or $InputObject -is [System.Array]) {
            return $null
        }
        $activeProperty = $InputObject.PSObject.Properties['stop_hook_active']
        if ($null -ne $activeProperty -and $activeProperty.Value -isnot [bool]) {
            return $null
        }
        if ($null -ne $activeProperty -and [bool]$activeProperty.Value) {
            return $null
        }
        $cwdProperty = $InputObject.PSObject.Properties['cwd']
        if ($null -eq $cwdProperty -or [string]::IsNullOrWhiteSpace([string]$cwdProperty.Value)) {
            return $null
        }
        $repositoryPath = [System.IO.Path]::GetFullPath([string]$cwdProperty.Value)
        if ([System.IO.File]::Exists((Join-Path $repositoryPath '.beads-optout'))) {
            return $null
        }

        if ($null -eq $RepositoryCheck) {
            $RepositoryCheck = { param($Path) [System.IO.Directory]::Exists((Join-Path $Path '.beads')) }
        }
        if (-not (& $RepositoryCheck $repositoryPath)) {
            return $null
        }

        $pathBytes = [System.Text.Encoding]::UTF8.GetBytes($repositoryPath.ToUpperInvariant())
        $repositoryHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($pathBytes))
        $cooldownPath = Join-Path $CooldownDirectory "$repositoryHash.txt"
        if ([System.IO.File]::Exists($cooldownPath)) {
            $lastText = [System.IO.File]::ReadAllText($cooldownPath)
            $lastNotification = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($lastText, [ref]$lastNotification)) {
                if (($NowUtc - $lastNotification).TotalMinutes -lt $CooldownMinutes) {
                    return $null
                }
            }
        }

        if ($null -eq $IssueProvider) {
            $IssueProvider = {
                param($Path)
                $originalLocation = Get-Location
                try {
                    Set-Location -LiteralPath $Path
                    $json = & bd list --status in_progress --json 2>$null
                    if ($LASTEXITCODE -ne 0) {
                        throw 'bd list failed'
                    }
                    if ([string]::IsNullOrWhiteSpace(($json -join "`n"))) {
                        return @()
                    }
                    return @(($json -join "`n") | ConvertFrom-Json)
                }
                finally {
                    Set-Location -LiteralPath $originalLocation
                }
            }
        }

        $issues = @(& $IssueProvider $repositoryPath)
        $staleIssues = [System.Collections.Generic.List[object]]::new()
        foreach ($issue in $issues) {
            if ($null -eq $issue) { continue }
            $updatedProperty = $issue.PSObject.Properties['updated_at']
            if ($null -eq $updatedProperty) { continue }
            $updatedAt = [DateTimeOffset]::MinValue
            if (-not [DateTimeOffset]::TryParse([string]$updatedProperty.Value, [ref]$updatedAt)) { continue }
            $age = $NowUtc - $updatedAt.ToUniversalTime()
            if ($age.TotalMinutes -ge $StaleMinutes) {
                $staleIssues.Add($issue)
            }
        }
        if ($staleIssues.Count -eq 0) {
            return $null
        }

        $summaries = @(
            foreach ($issue in @($staleIssues)[0..([Math]::Min($staleIssues.Count - 1, 4))]) {
                $id = [string]$issue.id
                $title = ([string]$issue.title).Replace("`r", ' ').Replace("`n", ' ')
                "$id $title"
            }
        )
        $reason = "未更新のBeads課題があります。進捗または判明事項をbd noteで記録してから終了してください: " + ($summaries -join '; ')
        [System.IO.Directory]::CreateDirectory($CooldownDirectory) | Out-Null
        [System.IO.File]::WriteAllText($cooldownPath, $NowUtc.ToUniversalTime().ToString('o'), [System.Text.UTF8Encoding]::new($false))
        return [pscustomobject]@{ decision = 'block'; reason = $reason }
    }
    catch {
        return $null
    }
}

if ($LibraryMode) {
    return
}

try {
    $inputText = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($inputText)) {
        exit 0
    }
    $inputObject = $inputText | ConvertFrom-Json
    $decision = Get-BeadsStopDecision -InputObject $inputObject -StaleMinutes $StaleMinutes -CooldownMinutes $CooldownMinutes
    if ($null -ne $decision) {
        [Console]::Out.Write(($decision | ConvertTo-Json -Compress -Depth 10))
    }
}
catch {
    exit 0
}

exit 0
