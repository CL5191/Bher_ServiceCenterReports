function Connect-ReportGraph {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$GraphConfig
    )

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    Connect-MgGraph `
        -TenantId $GraphConfig.TenantId `
        -ClientId $GraphConfig.ClientId `
        -CertificateThumbprint $GraphConfig.CertificateThumbprint `
        -NoWelcome | Out-Null
}

function Get-CallRecordsSafeWindow {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$FromUtc,

        [Parameter(Mandatory = $true)]
        [datetime]$ToUtc,

        [int]$MaxLookbackDays = 30
    )

    $safeFrom = $FromUtc
    $safeTo = $ToUtc
    $adjustments = @()
    $nowUtc = (Get-Date).ToUniversalTime()

    if ($safeTo -gt $nowUtc) {
        $safeTo = $nowUtc
        $adjustments += "End date adjusted to current UTC time because Graph callRecords does not allow future dates."
    }

    $minUtc = $nowUtc.AddDays(-$MaxLookbackDays).AddMinutes(5)
    if ($safeFrom -lt $minUtc) {
        $safeFrom = $minUtc
        $adjustments += "Start date adjusted to the last $MaxLookbackDays days (with a 5-minute safety buffer) to satisfy Graph callRecords limits."
    }

    if ($safeTo -le $safeFrom) {
        throw "Invalid reporting window after normalization. Ensure StartDate is earlier than EndDate and within the last $MaxLookbackDays days."
    }

    return [PSCustomObject]@{
        FromUtc = $safeFrom
        ToUtc = $safeTo
        Adjustments = $adjustments
    }
}

function Get-GraphHttpStatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $response = $ErrorRecord.Exception.Response
    if ($response -and $response.StatusCode) {
        return [int]$response.StatusCode
    }

    $message = [string]$ErrorRecord.Exception.Message
    if ($message -match '\b(4\d\d|5\d\d)\b') {
        return [int]$matches[1]
    }

    return $null
}

function Invoke-GraphWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [object]$Body,

        [Parameter(Mandatory = $true)]
        [hashtable]$GraphConfig
    )

    $attempt = 0
    $delay = [int]$GraphConfig.InitialRetryDelaySeconds

    while ($true) {
        try {
            if ($Method -eq "POST") {
                $requestBody = $Body
                if ($null -ne $Body -and $Body -isnot [string]) {
                    # Normalize nested hashtables/arrays into raw JSON to avoid SDK serialization edge cases.
                    $requestBody = $Body | ConvertTo-Json -Depth 32 -Compress
                }

                return Invoke-MgGraphRequest -Method $Method -Uri $Uri -Body $requestBody -ContentType "application/json"
            }

            return Invoke-MgGraphRequest -Method $Method -Uri $Uri
        }
        catch {
            $statusCode = Get-GraphHttpStatusCode -ErrorRecord $_

            if ($statusCode -and $statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
                throw
            }

            $attempt++
            if ($attempt -ge [int]$GraphConfig.MaxRetryCount) {
                throw
            }

            Start-Sleep -Seconds $delay
            $delay = [Math]::Min($delay * 2, 60)
        }
    }
}

function Invoke-GraphPaged {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$GraphConfig
    )

    $items = @()
    $next = $Uri

    do {
        $response = Invoke-GraphWithRetry -Method GET -Uri $next -GraphConfig $GraphConfig
        if ($response.value) {
            $items += $response.value
        }

        $next = $response."@odata.nextLink"
    }
    while ($next)

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

    return [Math]::Round((([datetime]$EndTime) - ([datetime]$StartTime)).TotalSeconds, 0)
}

function Get-QueueCallRecords {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$FromUtc,

        [Parameter(Mandatory = $true)]
        [datetime]$ToUtc,

        [Parameter(Mandatory = $true)]
        [hashtable]$QueueMap,

        [Parameter(Mandatory = $true)]
        [hashtable]$GraphConfig,

        [scriptblock]$ProgressCallback
    )

    $fromText = $FromUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $toText = $ToUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $results = @()

    foreach ($queueId in $QueueMap.Keys) {
        $queueName = $QueueMap[$queueId]
        if ($ProgressCallback) {
            & $ProgressCallback "Querying queue '$queueName' ($queueId)."
        }

        $filter = "startDateTime ge $fromText and startDateTime lt $toText and participants_v2/any(p:p/id eq '$queueId')"
        $encodedFilter = [System.Uri]::EscapeDataString($filter)
        $listUri = "https://graph.microsoft.com/v1.0/communications/callRecords?`$filter=$encodedFilter"

        $calls = Invoke-GraphPaged -Uri $listUri -GraphConfig $GraphConfig

        if ($ProgressCallback) {
            & $ProgressCallback "Queue '$queueName' returned $($calls.Count) call record headers."
        }

        foreach ($call in $calls) {
            $detailUri = "https://graph.microsoft.com/v1.0/communications/callRecords/$($call.id)?`$expand=sessions(`$expand=segments)"
            $detail = Invoke-GraphWithRetry -Method GET -Uri $detailUri -GraphConfig $GraphConfig

            $results += [PSCustomObject]@{
                QueueId   = $queueId
                QueueName = $queueName
                Call      = $detail
            }
        }

        if ($ProgressCallback) {
            & $ProgressCallback "Completed queue '$queueName'."
        }
    }

    return $results
}
