function Get-QueueSummary {
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [array]$MetricRows,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$AllQueueNames
    )

    $summaryByQueue = @{}

    if ($MetricRows -and $MetricRows.Count -gt 0) {
        foreach ($group in ($MetricRows | Group-Object QueueName)) {
            $queueCalls = $group.Group
            $answeredCalls = $queueCalls | Where-Object { $_.Answered -eq $true }
            $handleCalls = @()
            foreach ($answeredCall in $answeredCalls) {
                if (($answeredCall.PSObject.Properties.Name -contains "HandleSeconds") -and $answeredCall.HandleSeconds) {
                    $handleCalls += $answeredCall
                }
            }

            $avgHandleSeconds = if ($handleCalls.Count -gt 0) {
                [Math]::Round(($handleCalls | Measure-Object HandleSeconds -Average).Average, 0)
            }
            else {
                0
            }

            $avgWaitSeconds = if ($answeredCalls.Count -gt 0) {
                [Math]::Round(($answeredCalls | Measure-Object WaitSeconds -Average).Average, 0)
            }
            else {
                0
            }

            $underSla = ($queueCalls | Where-Object { $_.AnsweredUnderSLA -eq $true }).Count
            $slaPercent = if ($answeredCalls.Count -gt 0) {
                [Math]::Round(($underSla / $answeredCalls.Count) * 100, 2)
            }
            else {
                0
            }

            $summaryByQueue[[string]$group.Name] = [PSCustomObject]@{
                QueueName          = $group.Name
                Offered            = $queueCalls.Count
                Answered           = $answeredCalls.Count
                AnsweredUnderSLA   = $underSla
                SLAPercent         = $slaPercent
                Voicemail          = ($queueCalls | Where-Object { $_.Voicemail -eq $true }).Count
                Abandoned          = ($queueCalls | Where-Object { $_.Abandoned -eq $true }).Count
                AvgWaitSeconds     = $avgWaitSeconds
                AvgHandleSeconds   = $avgHandleSeconds
                AvgHandleMinutes   = if ($avgHandleSeconds -gt 0) { [Math]::Round($avgHandleSeconds / 60, 2) } else { 0 }
            }
        }
    }

    foreach ($queueName in @($AllQueueNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        $name = [string]$queueName
        if (-not $summaryByQueue.ContainsKey($name)) {
            $summaryByQueue[$name] = [PSCustomObject]@{
                QueueName          = $name
                Offered            = 0
                Answered           = 0
                AnsweredUnderSLA   = 0
                SLAPercent         = 0
                Voicemail          = 0
                Abandoned          = 0
                AvgWaitSeconds     = 0
                AvgHandleSeconds   = 0
                AvgHandleMinutes   = 0
            }
        }
    }

    return @($summaryByQueue.Values | Sort-Object QueueName)
}

function Get-AgentSummary {
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [array]$MetricRows
    )

    if (-not $MetricRows -or $MetricRows.Count -eq 0) {
        return @()
    }

    $answered = $MetricRows | Where-Object { $_.Answered -eq $true -and $_.AgentName }

    return $answered | Group-Object QueueName, AgentName | ForEach-Object {
        $rows = $_.Group

        [PSCustomObject]@{
            QueueName      = $rows[0].QueueName
            AgentName      = $rows[0].AgentName
            AgentId        = $rows[0].AgentId
            AnsweredCalls  = $rows.Count
            AvgWaitSeconds = [Math]::Round(($rows | Measure-Object WaitSeconds -Average).Average, 0)
        }
    } | Sort-Object QueueName, AnsweredCalls -Descending
}
