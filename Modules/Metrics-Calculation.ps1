function Get-QueueSummary {
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [array]$MetricRows
    )

    if (-not $MetricRows -or $MetricRows.Count -eq 0) {
        return @()
    }

    return $MetricRows | Group-Object QueueName | ForEach-Object {
        $queueCalls = $_.Group
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

        [PSCustomObject]@{
            QueueName          = $_.Name
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
