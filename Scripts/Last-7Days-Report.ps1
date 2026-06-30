[CmdletBinding()]
param(
    [switch]$SkipEmail
)

$now = Get-Date
$start = $now.Date.AddDays(-7)
$end = $now

& (Join-Path $PSScriptRoot "On-Demand-Report.ps1") -StartDate $start -EndDate $end -SkipEmail:$SkipEmail -OutputName "Behr-ServiceCenter-Weekly"
