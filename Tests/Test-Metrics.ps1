$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "Modules\Metrics-Calculation.ps1")

$rows = @(
    [pscustomobject]@{ QueueName="Q1"; Answered=$true; HandleSeconds=120; WaitSeconds=20; Voicemail=$false; Abandoned=$false; AnsweredUnderSLA=$true; AgentName="A1"; AgentId="1" },
    [pscustomobject]@{ QueueName="Q1"; Answered=$false; HandleSeconds=$null; WaitSeconds=$null; Voicemail=$false; Abandoned=$true; AnsweredUnderSLA=$false; AgentName=$null; AgentId=$null },
    [pscustomobject]@{ QueueName="Q1"; Answered=$true; HandleSeconds=240; WaitSeconds=45; Voicemail=$false; Abandoned=$false; AnsweredUnderSLA=$true; AgentName="A1"; AgentId="1" }
)

$queueSummary = Get-QueueSummary -MetricRows $rows
if ($queueSummary[0].Offered -ne 3) { throw "Expected Offered=3" }
if ($queueSummary[0].Answered -ne 2) { throw "Expected Answered=2" }
if ($queueSummary[0].Abandoned -ne 1) { throw "Expected Abandoned=1" }

$agentSummary = Get-AgentSummary -MetricRows $rows
if ($agentSummary[0].AnsweredCalls -ne 2) { throw "Expected Agent AnsweredCalls=2" }

Write-Host "Test-Metrics passed."
