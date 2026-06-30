
# -----------------------------
# CONFIG
# -----------------------------
$QueueMap = @{
    "349ff28d-ad37-488a-b495-a04517900cb4" = "Behr Sauk Village Service Center CQ"
    "e73c0939-3e77-47ad-aa22-a223065d1b04" = "Behr Orlando Service Center"
    "3233a4be-c77c-49c9-b090-4774520c567b" = "Behr Kutzwtown Service Center"
    "f8f665d0-3c75-47c9-93d4-a1a3a48b4a4f" = "Behr Roanoke Service Center"
    "159d7490-3cea-43ab-affb-e4ee28b43be6" = "Behr Standard Service Center"

}

$QueueResourceAccountIds = @($QueueMap.Keys)

$DaysBack = 7
$OutputFile = "C:\Temp\CQ_CallStats.csv"
$SummaryFile = "C:\Temp\CQ_CallStats_Summary.csv"

# -----------------------------
# FUNCTIONS
# -----------------------------
function Invoke-GraphPaged {
    param([string]$Uri)

    $items = @()

    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $Uri
        if ($response.value) {
            $items += $response.value
        }
        $Uri = $response.'@odata.nextLink'
    } while ($Uri)

    return $items
}

function Get-CallDurationSeconds {
    param(
        [string]$StartTime,
        [string]$EndTime
    )

    if ([string]::IsNullOrWhiteSpace($StartTime) -or [string]::IsNullOrWhiteSpace($EndTime)) {
        return $null
    }

    return [math]::Round((([datetime]$EndTime) - ([datetime]$StartTime)).TotalSeconds, 0)
}

# -----------------------------
# PREP
# -----------------------------
New-Item -ItemType Directory -Path (Split-Path $OutputFile) -Force | Out-Null

$fromDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$results = @()

Write-Host "From: $fromDate"

# -----------------------------
# LOOP QUEUES
# -----------------------------
foreach ($queueId in $QueueResourceAccountIds) {

    $queueName = $QueueMap[$queueId]

    Write-Host ""
    Write-Host "Processing queue: $queueName"

    $filter = "startDateTime ge $fromDate and participants_v2/any(p:p/id eq '$queueId')"
    $encodedFilter = [System.Uri]::EscapeDataString($filter)

    $uri = "https://graph.microsoft.com/v1.0/communications/callRecords?`$filter=$encodedFilter"

    $calls = Invoke-GraphPaged -Uri $uri

    Write-Host "Calls found before filtering: $($calls.Count)"

    foreach ($call in $calls) {

        try {
            $detail = Invoke-MgGraphRequest -Method GET `
                -Uri "https://graph.microsoft.com/v1.0/communications/callRecords/$($call.id)?`$expand=sessions(`$expand=segments)"
        }
        catch {
            Write-Warning "Could not expand callRecord $($call.id)"
            continue
        }

        $callStart = [datetime]$detail.startDateTime
        $callEnd = if ($detail.endDateTime) { [datetime]$detail.endDateTime } else { $null }

        # -----------------------------
        # SKIP ZERO-DURATION CALLS
        # -----------------------------
        $durationSeconds = Get-CallDurationSeconds `
            -StartTime $detail.startDateTime `
            -EndTime $detail.endDateTime

        if (-not $durationSeconds -or $durationSeconds -le 0) {
            continue
        }

        $segments = @()

        foreach ($session in $detail.sessions) {
            foreach ($segment in $session.segments) {

                $segments += [PSCustomObject]@{
                    Start       = $segment.startDateTime
                    End         = $segment.endDateTime

                    Caller      = $segment.caller.identity.user.id
                    Callee      = $segment.callee.identity.user.id

                    CallerName  = $segment.caller.identity.user.displayName
                    CalleeName  = $segment.callee.identity.user.displayName

                    CallerType  = $segment.caller.endpointType
                    CalleeType  = $segment.callee.endpointType

                    SegmentJson = ($segment | ConvertTo-Json -Depth 20)
                }
            }
        }

        # -----------------------------
        # ONLY INCOMING CALLS
        # Incoming = queue resource account appears as callee
        # -----------------------------
        $incomingToQueue = $segments | Where-Object {
            $_.Callee -eq $queueId
        } | Select-Object -First 1

        if (-not $incomingToQueue) {
            continue
        }

        # -----------------------------
        # VOICEMAIL DETECTION
        # -----------------------------
        $detailJson = $detail | ConvertTo-Json -Depth 100

        $isVoicemail = $false

        if ($detailJson -match "voicemail|voice mail") {
            $isVoicemail = $true
        }

        # -----------------------------
        # FIND ANSWERING AGENT
        # First non-queue user after the call starts
        # -----------------------------
        $agent = $segments |
            Where-Object {
                (
                    $_.Caller -and
                    -not ($QueueResourceAccountIds -contains $_.Caller)
                ) -or (
                    $_.Callee -and
                    -not ($QueueResourceAccountIds -contains $_.Callee)
                )
            } |
            Sort-Object Start |
            Select-Object -First 1

        $answered = $false
        $answerTime = $null
        $waitSeconds = $null
        $handleSeconds = $null
        $agentName = $null
        $agentId = $null

        if ($agent -and -not $isVoicemail) {

            $answered = $true
            $answerTime = [datetime]$agent.Start
            $waitSeconds = [math]::Round(($answerTime - $callStart).TotalSeconds, 0)

            if ($callEnd) {
                $handleSeconds = [math]::Round(($callEnd - $answerTime).TotalSeconds, 0)

                if ($handleSeconds -lt 0) {
                    $handleSeconds = $null
                }
            }

            if ($agent.Callee -and -not ($QueueResourceAccountIds -contains $agent.Callee)) {
                $agentId = $agent.Callee
                $agentName = $agent.CalleeName
            }
            elseif ($agent.Caller -and -not ($QueueResourceAccountIds -contains $agent.Caller)) {
                $agentId = $agent.Caller
                $agentName = $agent.CallerName
            }
        }

        # -----------------------------
        # FINAL CLASSIFICATION
        # -----------------------------
        $voicemail = $false
        $abandoned = $false

        if (-not $answered) {
            if ($isVoicemail) {
                $voicemail = $true
            }
            else {
                $abandoned = $true
            }
        }

        $results += [PSCustomObject]@{
            QueueName          = $queueName
            QueueResourceId    = $queueId
            CallId             = $detail.id

            StartTime          = $detail.startDateTime
            EndTime            = $detail.endDateTime
            DurationSeconds    = $durationSeconds

            AgentName          = $agentName
            AgentId            = $agentId

            AnswerTime         = $answerTime
            WaitSeconds        = $waitSeconds
            HandleSeconds      = $handleSeconds

            Offered            = $true
            Answered           = $answered
            AnsweredUnder60Sec = ($answered -and $waitSeconds -le 60)

            Voicemail          = $voicemail
            Abandoned          = $abandoned
        }
    }
}

# -----------------------------
# EXPORT DETAIL
# -----------------------------
$results | Export-Csv $OutputFile -NoTypeInformation

# -----------------------------
# SUMMARY PER QUEUE
# -----------------------------
$summary = $results | Group-Object QueueName | ForEach-Object {

    $queueCalls = $_.Group
    $answeredCalls = $queueCalls | Where-Object { $_.Answered -eq $true }
    $handleCalls = $answeredCalls | Where-Object { $_.HandleSeconds -ne $null }

    $avgHandleSeconds = if ($handleCalls.Count -gt 0) {
        [math]::Round(($handleCalls | Measure-Object HandleSeconds -Average).Average, 0)
    }
    else {
        0
    }

    $avgHandleMinutes = if ($avgHandleSeconds -gt 0) {
        [math]::Round(($avgHandleSeconds / 60), 2)
    }
    else {
        0
    }

    $under60 = ($queueCalls | Where-Object { $_.AnsweredUnder60Sec -eq $true }).Count

    $slaPercent = if ($answeredCalls.Count -gt 0) {
        [math]::Round(($under60 / $answeredCalls.Count) * 100, 2)
    }
    else {
        0
    }

    [PSCustomObject]@{
        QueueName             = $_.Name
        Offered               = $queueCalls.Count
        Answered              = $answeredCalls.Count
        AnsweredUnder60Sec    = $under60
        SLAPercentUnder60     = $slaPercent
        Voicemail             = ($queueCalls | Where-Object { $_.Voicemail -eq $true }).Count
        Abandoned             = ($queueCalls | Where-Object { $_.Abandoned -eq $true }).Count
        AvgHandleSeconds      = $avgHandleSeconds
        AvgHandleMinutes      = $avgHandleMinutes
    }
}

$summary | Export-Csv $SummaryFile -NoTypeInformation

# -----------------------------
# DISPLAY SUMMARY
# -----------------------------
Write-Host ""
Write-Host "=============================="
Write-Host "QUEUE SUMMARY"
Write-Host "=============================="

$summary | ForEach-Object {
    Write-Host ""
    Write-Host "Queue: $($_.QueueName)"
    Write-Host "Offered: $($_.Offered)"
    Write-Host "Answered: $($_.Answered)"
    Write-Host "Answered <= 60 sec: $($_.AnsweredUnder60Sec)"
    Write-Host "SLA %: $($_.SLAPercentUnder60)%"
    Write-Host "Voicemail: $($_.Voicemail)"
    Write-Host "Abandoned: $($_.Abandoned)"
    Write-Host "Avg Handle Time: $($_.AvgHandleSeconds) sec / $($_.AvgHandleMinutes) min"
}

Write-Host ""
Write-Host "Detail export complete: $OutputFile"
Write-Host "Summary export complete: $SummaryFile"
