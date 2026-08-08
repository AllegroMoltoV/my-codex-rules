[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TargetPath,
    [switch]$NoBeads,
    [string]$BdCommand = 'bd',
    [string]$GitCommand = 'git'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$implementationPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\project-bootstrap\scripts\bootstrap.ps1'
& $implementationPath @PSBoundParameters
