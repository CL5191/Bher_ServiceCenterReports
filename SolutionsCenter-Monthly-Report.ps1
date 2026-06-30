[CmdletBinding()]
param(
    [switch]$SkipEmail
)

& (Join-Path $PSScriptRoot "Scripts\Monthly-Report-SolutionsCenter.ps1") -SkipEmail:$SkipEmail
