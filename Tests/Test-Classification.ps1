$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $repoRoot "Modules\Graph-Operations.ps1")
. (Join-Path $repoRoot "Modules\Call-Classification.ps1")

$mockCall = @{
    id = "call-1"
    startDateTime = "2026-06-01T10:00:00Z"
    endDateTime = "2026-06-01T10:05:00Z"
    sessions = @(
        @{
            segments = @(
                @{
                    startDateTime = "2026-06-01T10:00:00Z"
                    endDateTime = "2026-06-01T10:00:30Z"
                    caller = @{ identity = @{ user = @{ id = "external"; displayName = "External Caller" } }; endpointType = "default" }
                    callee = @{ identity = @{ user = @{ id = "queue1"; displayName = "Queue" } }; endpointType = "applicationInstance" }
                },
                @{
                    startDateTime = "2026-06-01T10:00:30Z"
                    endDateTime = "2026-06-01T10:05:00Z"
                    caller = @{ identity = @{ user = @{ id = "queue1"; displayName = "Queue" } }; endpointType = "applicationInstance" }
                    callee = @{ identity = @{ user = @{ id = "agent1"; displayName = "Agent One" } }; endpointType = "default" }
                }
            )
        }
    )
}

$row = Convert-CallRecordToMetricRow -Call $mockCall -QueueId "queue1" -QueueName "Queue 1" -QueueIds @("queue1") -SlaSeconds 60
if (-not $row.Answered) { throw "Expected Answered=true" }
if ($row.Abandoned) { throw "Expected Abandoned=false" }
if (-not $row.AnsweredUnderSLA) { throw "Expected AnsweredUnderSLA=true" }

Write-Host "Test-Classification passed."
