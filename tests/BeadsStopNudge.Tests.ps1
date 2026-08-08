$repoRoot = Split-Path -Parent $PSScriptRoot
$nudgePath = Join-Path $repoRoot 'scripts\beads-stop-nudge.ps1'

Assert-PathExists $nudgePath
. $nudgePath -LibraryMode

function Import-BeadsStopNudge {}

Invoke-TestCase 'stop_hook_activeではBeadsを呼ばない' {
    Import-BeadsStopNudge
    $called = $false
    $inputObject = [pscustomobject]@{ stop_hook_active = $true; cwd = 'C:\repo' }
    $result = Get-BeadsStopDecision -InputObject $inputObject -IssueProvider {
        $called = $true
        return @()
    }
    Assert-True (-not $called) '再入時に課題取得処理が呼ばれました。'
    Assert-True ($null -eq $result) '再入時に通知が返りました。'
}

Invoke-TestCase '15分以上未更新の課題を通知する' {
    Import-BeadsStopNudge
    $now = [DateTimeOffset]::Parse('2026-08-08T00:15:00Z')
    $inputObject = [pscustomobject]@{ stop_hook_active = $false; cwd = 'C:\repo' }
    $result = Get-BeadsStopDecision -InputObject $inputObject -NowUtc $now -StaleMinutes 15 -CooldownMinutes 0 -RepositoryCheck { $true } -IssueProvider {
        @([pscustomobject]@{ id = 'bd-1'; title = '未更新課題'; updated_at = '2026-08-08T00:00:00Z' })
    }
    Assert-Equal 'block' $result.decision '継続判断が返りませんでした。'
    Assert-True ($result.reason.Contains('bd-1')) '通知理由に課題IDがありません。'
}

Invoke-TestCase '15分未満の課題は通知しない' {
    Import-BeadsStopNudge
    $now = [DateTimeOffset]::Parse('2026-08-08T00:14:59Z')
    $inputObject = [pscustomobject]@{ stop_hook_active = $false; cwd = 'C:\repo' }
    $result = Get-BeadsStopDecision -InputObject $inputObject -NowUtc $now -StaleMinutes 15 -CooldownMinutes 0 -RepositoryCheck { $true } -IssueProvider {
        @([pscustomobject]@{ id = 'bd-1'; title = '更新済み課題'; updated_at = '2026-08-08T00:00:00Z' })
    }
    Assert-True ($null -eq $result) '閾値未満の課題が通知されました。'
}

Invoke-TestCase '入力異常とBeads異常はフェイルオープンにする' {
    Import-BeadsStopNudge
    $invalidInputResult = Get-BeadsStopDecision -InputObject $null
    Assert-True ($null -eq $invalidInputResult) '入力異常で通知が返りました。'

    $inputObject = [pscustomobject]@{ stop_hook_active = $false; cwd = 'C:\repo' }
    $providerResult = Get-BeadsStopDecision -InputObject $inputObject -RepositoryCheck { $true } -IssueProvider { throw 'bd failed' }
    Assert-True ($null -eq $providerResult) 'Beads異常で通知が返りました。'
}

Invoke-TestCase 'opt-outされたリポジトリでは通知しない' {
    Import-BeadsStopNudge
    $root = New-TestDirectory
    try {
        [System.IO.File]::WriteAllText((Join-Path $root '.beads-optout'), '')
        $inputObject = [pscustomobject]@{ stop_hook_active = $false; cwd = $root }
        $result = Get-BeadsStopDecision -InputObject $inputObject -RepositoryCheck { $false } -IssueProvider { throw '呼ばれてはいけません' }
        Assert-True ($null -eq $result) 'opt-outで通知が返りました。'
    }
    finally {
        if (Test-Path -LiteralPath $root) {
            Remove-Item -LiteralPath $root -Recurse -Force
        }
    }
}
