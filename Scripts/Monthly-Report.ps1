[CmdletBinding()]
param(
    [switch]$SkipEmail
)

$repoRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $repoRoot "Config\config.ps1")
. (Join-Path $repoRoot "Modules\Logging.ps1")
. (Join-Path $repoRoot "Modules\Graph-Operations.ps1")
. (Join-Path $repoRoot "Modules\Call-Classification.ps1")
. (Join-Path $repoRoot "Modules\Metrics-Calculation.ps1")
. (Join-Path $repoRoot "Modules\Export-Excel.ps1")
. (Join-Path $repoRoot "Modules\Export-PDF.ps1")
. (Join-Path $repoRoot "Modules\Email-Report.ps1")

$config = Get-ReportConfig
$run = New-RunContext -LogsPath $config.Reporting.LogsPath

try {
    Write-ReportLog -LogFile $run.LogFile -Message "Monthly report run started. RunId=$($run.RunId)"

    $queueMapPath = $config.Files.QueueMapFile
    $queueMap = Get-Content -LiteralPath $queueMapPath -Raw | ConvertFrom-Json -AsHashtable

    $now = Get-Date
    $end = $now
    $start = $end.AddDays(-28)

    $rawFromUtc = $start.ToUniversalTime()
    $rawToUtc = $end.ToUniversalTime()

    $window = Get-CallRecordsSafeWindow -FromUtc $rawFromUtc -ToUtc $rawToUtc
    $fromUtc = $window.FromUtc
    $toUtc = $window.ToUtc

    foreach ($note in $window.Adjustments) {
        Write-ReportLog -LogFile $run.LogFile -Level WARN -Message $note
    }

    Write-ReportLog -LogFile $run.LogFile -Message "Effective UTC window: $($fromUtc.ToString('o')) to $($toUtc.ToString('o'))"

    Connect-ReportGraph -GraphConfig $config.Graph

    $queueCalls = Get-QueueCallRecords -FromUtc $fromUtc -ToUtc $toUtc -QueueMap $queueMap -GraphConfig $config.Graph -ProgressCallback {
        param($message)
        Write-ReportLog -LogFile $run.LogFile -Message $message
    }

    if (-not $queueCalls) {
        $queueCalls = @()
    }

    $detailRows = Convert-QueueCallsToMetricRows -QueueCalls $queueCalls -SlaSeconds $config.Reporting.SLASeconds
    if (-not $detailRows) {
        $detailRows = @()
        Write-ReportLog -LogFile $run.LogFile -Level WARN -Message "No qualifying inbound non-zero-duration calls found in the selected window."
    }

    $missingAgentIds = @(
        $detailRows |
        Where-Object { $_.Answered -eq $true -and $_.AgentId -and [string]::IsNullOrWhiteSpace([string]$_.AgentName) } |
        Select-Object -ExpandProperty AgentId -Unique
    )
    if ($missingAgentIds.Count -gt 0) {
        $agentNameMap = Resolve-UserDisplayNameMap -UserIds $missingAgentIds -GraphConfig $config.Graph
        $resolvedCount = 0
        foreach ($row in $detailRows) {
            if ($row.Answered -eq $true -and $row.AgentId -and [string]::IsNullOrWhiteSpace([string]$row.AgentName) -and $agentNameMap.ContainsKey([string]$row.AgentId)) {
                $mappedName = [string]$agentNameMap[[string]$row.AgentId]
                if (-not [string]::IsNullOrWhiteSpace($mappedName)) {
                    $row.AgentName = $mappedName
                    $resolvedCount++
                }
            }
        }
        $unresolvedCount = $missingAgentIds.Count - $resolvedCount
        Write-ReportLog -LogFile $run.LogFile -Message "Resolved display names for $resolvedCount of $($missingAgentIds.Count) previously unnamed answering agents."
        if ($unresolvedCount -gt 0) {
            Write-ReportLog -LogFile $run.LogFile -Level WARN -Message "Could not resolve $unresolvedCount answering agent IDs to user display names."
        }
    }

    $queueSummary = Get-QueueSummary -MetricRows $detailRows
    $agentSummary = Get-AgentSummary -MetricRows $detailRows

    if (-not (Test-Path -LiteralPath $config.Reporting.ReportsPath)) {
        New-Item -Path $config.Reporting.ReportsPath -ItemType Directory -Force | Out-Null
    }

    $stamp = "{0}_to_{1}" -f $start.ToString("yyyyMMdd"), $end.ToString("yyyyMMdd")
    $outputName = "Behr-ServiceCenter-Monthly"
    $xlsxPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}.xlsx" -f $outputName, $stamp)
    $pdfPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}.pdf" -f $outputName, $stamp)
    $finalXlsxPath = $xlsxPath
    $finalPdfPath = $pdfPath

    try {
        Export-ReportWorkbook -DetailRows $detailRows -QueueSummary $queueSummary -AgentSummary $agentSummary -WorkbookPath $finalXlsxPath | Out-Null
        Export-ReportPdf -QueueSummary $queueSummary -AgentSummary $agentSummary -PdfPath $finalPdfPath -PdfGenerator $config.Reporting.PdfGenerator | Out-Null
    }
    catch {
        $message = [string]$_.Exception.Message
        if ($message -match 'being used by another process|Could not open Excel Package') {
            $suffix = "_{0}" -f $run.RunId
            $finalXlsxPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}{2}.xlsx" -f $outputName, $stamp, $suffix)
            $finalPdfPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}{2}.pdf" -f $outputName, $stamp, $suffix)

            Write-ReportLog -LogFile $run.LogFile -Level WARN -Message "Primary output file is locked. Retrying with alternate filenames: $finalXlsxPath and $finalPdfPath"

            Export-ReportWorkbook -DetailRows $detailRows -QueueSummary $queueSummary -AgentSummary $agentSummary -WorkbookPath $finalXlsxPath | Out-Null
            Export-ReportPdf -QueueSummary $queueSummary -AgentSummary $agentSummary -PdfPath $finalPdfPath -PdfGenerator $config.Reporting.PdfGenerator | Out-Null
        }
        else {
            throw
        }
    }

    if (-not $SkipEmail) {
        $subject = "{0} - Monthly (Last 28 Days) ({1})" -f $config.Email.SubjectPrefix, $stamp
        $body = "<p>Attached are the service center queue reports for the last 28 days (<b>$stamp</b>).</p><p>Run ID: $($run.RunId)</p>"
        Send-ReportEmail -EmailConfig $config.Email -Subject $subject -BodyHtml $body -AttachmentPaths @($finalXlsxPath, $finalPdfPath) -GraphConfig $config.Graph
    }

    Write-ReportLog -LogFile $run.LogFile -Message "Monthly report run completed. Output: $finalXlsxPath, $finalPdfPath"
}
catch {
    Write-ReportLog -LogFile $run.LogFile -Level ERROR -Message ("Monthly report failed: {0}" -f $_.Exception.Message)
    throw
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
