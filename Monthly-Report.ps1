[CmdletBinding()]
param(
    [switch]$SkipEmail
)

& (Join-Path $PSScriptRoot "Scripts\Monthly-Report.ps1") -SkipEmail:$SkipEmail
