[CmdletBinding()]
param(
    [switch]$SkipEmail
)

& (Join-Path $PSScriptRoot "Scripts\Last-7Days-Report.ps1") -SkipEmail:$SkipEmail
