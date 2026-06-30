function Convert-CallDetailsToSegments {
    param(
        [Parameter(Mandatory = $true)]
        $Call
    )

    $segments = @()

    foreach ($session in ($Call.sessions | Where-Object { $_ })) {
        foreach ($segment in ($session.segments | Where-Object { $_ })) {
            $segments += [PSCustomObject]@{
                Start      = $segment.startDateTime
                End        = $segment.endDateTime
                Caller      = $segment.caller.identity.user.id
                Callee      = $segment.callee.identity.user.id
                CallerName  = $segment.caller.identity.user.displayName
                CalleeName  = $segment.callee.identity.user.displayName
                CallerType  = $segment.caller.endpointType
                CalleeType  = $segment.callee.endpointType
            }
        }
    }

    return $segments
}

function Get-SegmentDurationSeconds {
    param(
        [Parameter(Mandatory = $true)]
        $Segment
    )

    if ([string]::IsNullOrWhiteSpace($Segment.Start) -or [string]::IsNullOrWhiteSpace($Segment.End)) {
        return $null
    }

    return [Math]::Round((([datetime]$Segment.End) - ([datetime]$Segment.Start)).TotalSeconds, 0)
}

function Get-AnsweringAgentSegment {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Segments,

        [Parameter(Mandatory = $true)]
        [string]$QueueId,

        [Parameter(Mandatory = $true)]
        [string[]]$QueueIds,

        [Parameter(Mandatory = $true)]
        [datetime]$InboundStart
    )

    return $Segments |
        Where-Object {
            $_.Caller -eq $QueueId -and
            $_.Callee -and
            -not ($QueueIds -contains $_.Callee) -and
            [datetime]$_.Start -ge $InboundStart -and
            (Get-SegmentDurationSeconds -Segment $_) -gt 0
        } |
        Sort-Object Start |
        Select-Object -First 1
}

function Get-FallbackAnswerSegment {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Segments,

        [Parameter(Mandatory = $true)]
        [string[]]$QueueIds,

        [Parameter(Mandatory = $true)]
        [datetime]$InboundStart,

        [int]$MinDurationSeconds = 10
    )

    return $Segments |
        Where-Object {
            [datetime]$_.Start -ge $InboundStart -and
            (Get-SegmentDurationSeconds -Segment $_) -ge $MinDurationSeconds -and
            -not (
                ($_.Caller -and ($QueueIds -contains $_.Caller)) -or
                ($_.Callee -and ($QueueIds -contains $_.Callee))
            ) -and
            (
                ($_.Caller -and -not ($QueueIds -contains $_.Caller)) -or
                ($_.Callee -and -not ($QueueIds -contains $_.Callee))
            )
        } |
        Sort-Object Start |
        Select-Object -First 1
}

function Test-VoicemailCall {
    param(
        [Parameter(Mandatory = $true)]
        $Call
    )

    $json = $Call | ConvertTo-Json -Depth 100
    return [bool]($json -match "voicemail|voice mail")
}

function Convert-CallRecordToMetricRow {
    param(
        [Parameter(Mandatory = $true)]
        $Call,

        [Parameter(Mandatory = $true)]
        [string]$QueueId,

        [Parameter(Mandatory = $true)]
        [string]$QueueName,

        [Parameter(Mandatory = $true)]
        [string[]]$QueueIds,

        [Parameter(Mandatory = $true)]
        [int]$SlaSeconds
    )

    $durationSeconds = Get-CallDurationSeconds -StartTime $Call.startDateTime -EndTime $Call.endDateTime
    if (-not $durationSeconds -or $durationSeconds -le 0) {
        return $null
    }

    $segments = Convert-CallDetailsToSegments -Call $Call
    $incomingToQueue = $segments |
        Where-Object {
            $_.Callee -eq $QueueId -and
            -not ($_.Caller -and ($QueueIds -contains $_.Caller))
        } |
        Sort-Object Start |
        Select-Object -First 1

    if (-not $incomingToQueue) {
        return $null
    }

    $incomingDurationSeconds = Get-SegmentDurationSeconds -Segment $incomingToQueue
    if (-not $incomingDurationSeconds -or $incomingDurationSeconds -le 0) {
        return $null
    }

    $callStart = [datetime]$Call.startDateTime
    $callEnd = if ($Call.endDateTime) { [datetime]$Call.endDateTime } else { $null }

    $isVoicemail = Test-VoicemailCall -Call $Call
    $agentSegment = Get-AnsweringAgentSegment -Segments $segments -QueueId $QueueId -QueueIds $QueueIds -InboundStart ([datetime]$incomingToQueue.Start)
    $answeredByFallback = $false

    if (-not $agentSegment -and -not $isVoicemail) {
        $agentSegment = Get-FallbackAnswerSegment -Segments $segments -QueueIds $QueueIds -InboundStart ([datetime]$incomingToQueue.Start)
        $answeredByFallback = $null -ne $agentSegment
    }

    $answered = $false
    $answerTime = $null
    $waitSeconds = $null
    $handleSeconds = $null
    $agentName = $null
    $agentId = $null

    if ($agentSegment -and -not $isVoicemail) {
        $answered = $true
        $answerTime = [datetime]$agentSegment.Start
        $waitSeconds = [Math]::Round(($answerTime - [datetime]$incomingToQueue.Start).TotalSeconds, 0)
        if ($waitSeconds -lt 0) {
            $waitSeconds = 0
        }

        if ($callEnd) {
            $handleSeconds = [Math]::Round(($callEnd - $answerTime).TotalSeconds, 0)
            if ($handleSeconds -lt 0) {
                $handleSeconds = $null
            }
        }

        if ($agentSegment.Callee -and -not ($QueueIds -contains $agentSegment.Callee)) {
            $agentId = $agentSegment.Callee
            $agentName = $agentSegment.CalleeName
        }
        elseif ($agentSegment.Caller -and -not ($QueueIds -contains $agentSegment.Caller)) {
            $agentId = $agentSegment.Caller
            $agentName = $agentSegment.CallerName
        }
    }

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

    return [PSCustomObject]@{
        QueueName          = $QueueName
        QueueResourceId    = $QueueId
        CallId             = $Call.id
        StartTime          = $Call.startDateTime
        EndTime            = $Call.endDateTime
        DurationSeconds    = $durationSeconds
        InboundDurationSeconds = $incomingDurationSeconds
        AgentName          = $agentName
        AgentId            = $agentId
        AnswerTime         = $answerTime
        WaitSeconds        = $waitSeconds
        HandleSeconds      = $handleSeconds
        Offered            = $true
        Answered           = $answered
        AnsweredUnderSLA   = ($answered -and $waitSeconds -le $SlaSeconds)
        Voicemail          = $voicemail
        Abandoned          = $abandoned
        AnsweredByFallback = $answeredByFallback
    }
}

function Convert-QueueCallsToMetricRows {
    param(
        [AllowEmptyCollection()]
        [array]$QueueCalls,

        [Parameter(Mandatory = $true)]
        [int]$SlaSeconds
    )

    $rows = @()
    if (-not $QueueCalls -or $QueueCalls.Count -eq 0) {
        return $rows
    }

    $queueIds = $QueueCalls.QueueId | Select-Object -Unique

    foreach ($item in $QueueCalls) {
        $row = Convert-CallRecordToMetricRow -Call $item.Call -QueueId $item.QueueId -QueueName $item.QueueName -QueueIds $queueIds -SlaSeconds $SlaSeconds
        if ($row) {
            $rows += $row
        }
    }

    return $rows
}
