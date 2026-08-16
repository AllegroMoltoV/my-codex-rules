[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TestCount = 0
$script:FailureCount = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()

function Invoke-TestCase {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Test
    )

    $script:TestCount++
    try {
        & $Test
        Write-Host "PASS: $Name"
    }
    catch {
        $script:FailureCount++
        $message = "FAIL: $Name`n$($_.Exception.Message)"
        $script:Failures.Add($message)
        Write-Host $message
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected=[$Expected] Actual=[$Actual]"
    }
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "必要なファイルがありません: $Path"
    }
}

function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("my-codex-rules-test-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($path) | Out-Null
    return $path
}

$testFiles = @(
    'BeadsSetup.Tests.ps1',
    'BeadsStopNudge.Tests.ps1',
    'ProjectBootstrap.Tests.ps1',
    'Rules.Tests.ps1'
)

foreach ($testFile in $testFiles) {
    $testPath = Join-Path $PSScriptRoot $testFile
    try {
        . $testPath
    }
    catch {
        $script:TestCount++
        $script:FailureCount++
        $message = "FAIL: テストファイルを読み込む: $testFile`n$($_.Exception.Message)"
        $script:Failures.Add($message)
        Write-Host $message
    }
}

Write-Host "TOTAL: $script:TestCount"
Write-Host "FAILED: $script:FailureCount"

if ($script:FailureCount -gt 0) {
    exit 1
}

exit 0
