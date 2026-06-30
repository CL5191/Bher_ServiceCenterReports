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

$fallbackCallerSideCall = @{
    id = "call-2"
    startDateTime = "2026-06-01T11:00:00Z"
    endDateTime = "2026-06-01T11:03:00Z"
    sessions = @(
        @{
            segments = @(
                @{
                    startDateTime = "2026-06-01T11:00:00Z"
                    endDateTime = "2026-06-01T11:00:20Z"
                    caller = @{ identity = @{ user = @{ id = "external"; displayName = "External Caller" } }; endpointType = "default" }
                    callee = @{ identity = @{ user = @{ id = "queue1"; displayName = "Queue" } }; endpointType = "applicationInstance" }
                },
                @{
                    startDateTime = "2026-06-01T11:00:40Z"
                    endDateTime = "2026-06-01T11:02:40Z"
                    caller = @{ identity = @{ user = @{ id = "agent2"; displayName = "Agent Two" } }; endpointType = "default" }
                    callee = @{ identity = @{ user = @{ id = $null; displayName = $null } }; endpointType = "default" }
                }
            )
        }
    )
}

$fallbackRow = Convert-CallRecordToMetricRow -Call $fallbackCallerSideCall -QueueId "queue1" -QueueName "Queue 1" -QueueIds @("queue1") -SlaSeconds 60
if (-not $fallbackRow.Answered) { throw "Expected fallback Answered=true" }
if (-not $fallbackRow.AnsweredByFallback) { throw "Expected AnsweredByFallback=true" }
if ($fallbackRow.Abandoned) { throw "Expected fallback Abandoned=false" }

$shortFallbackCall = @{
    id = "call-3"
    startDateTime = "2026-06-01T12:00:00Z"
    endDateTime = "2026-06-01T12:01:00Z"
    sessions = @(
        @{
            segments = @(
                @{
                    startDateTime = "2026-06-01T12:00:00Z"
                    endDateTime = "2026-06-01T12:00:20Z"
                    caller = @{ identity = @{ user = @{ id = "external"; displayName = "External Caller" } }; endpointType = "default" }
                    callee = @{ identity = @{ user = @{ id = "queue1"; displayName = "Queue" } }; endpointType = "applicationInstance" }
                },
                @{
                    startDateTime = "2026-06-01T12:00:25Z"
                    endDateTime = "2026-06-01T12:00:30Z"
                    caller = @{ identity = @{ user = @{ id = "agent3"; displayName = "Agent Three" } }; endpointType = "default" }
                    callee = @{ identity = @{ user = @{ id = $null; displayName = $null } }; endpointType = "default" }
                }
            )
        }
    )
}

$shortFallbackRow = Convert-CallRecordToMetricRow -Call $shortFallbackCall -QueueId "queue1" -QueueName "Queue 1" -QueueIds @("queue1") -SlaSeconds 60
if ($shortFallbackRow.Answered) { throw "Expected short fallback segment to remain unanswered" }
if ($shortFallbackRow.AnsweredByFallback) { throw "Expected AnsweredByFallback=false for short segment" }

Write-Host "Test-Classification passed."
