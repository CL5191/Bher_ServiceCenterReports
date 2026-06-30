[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$StartDate,

    [Parameter(Mandatory = $true)]
    [datetime]$EndDate,

    [switch]$SkipEmail
)

& (Join-Path $PSScriptRoot "Scripts\On-Demand-Report.ps1") -StartDate $StartDate -EndDate $EndDate -SkipEmail:$SkipEmail
