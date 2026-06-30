[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$AutomationAccountName,

    [string]$RunbookName = "Monthly-ServiceCenterReport",
    [string]$ScheduleName = "Monthly-ServiceCenterReport-0600",
    [string]$TimeZone = "Eastern Standard Time"
)

$startTime = (Get-Date -Day 1 -Hour 6 -Minute 0 -Second 0).AddMonths(1)

Write-Host "Use the following Azure PowerShell commands to register schedule and link runbook:"
Write-Host ""
Write-Host ("New-AzAutomationSchedule -AutomationAccountName '{0}' -ResourceGroupName '{1}' -Name '{2}' -StartTime '{3}' -MonthInterval 1 -TimeZone '{4}'" -f $AutomationAccountName, $ResourceGroupName, $ScheduleName, $startTime.ToString("o"), $TimeZone)
Write-Host ("Register-AzAutomationScheduledRunbook -AutomationAccountName '{0}' -ResourceGroupName '{1}' -RunbookName '{2}' -ScheduleName '{3}'" -f $AutomationAccountName, $ResourceGroupName, $RunbookName, $ScheduleName)
