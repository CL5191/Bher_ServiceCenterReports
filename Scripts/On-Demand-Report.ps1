[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [datetime]$StartDate,

    [Parameter(Mandatory = $true)]
    [datetime]$EndDate,

    [string]$OutputName = "ServiceCenterReport",

    [switch]$SkipEmail
)

if ($EndDate -le $StartDate) {
    throw "EndDate must be later than StartDate."
}

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
    Write-ReportLog -LogFile $run.LogFile -Message "On-demand report run started. RunId=$($run.RunId)"

    $queueMapPath = $config.Files.QueueMapFile
    $queueMap = Get-Content -LiteralPath $queueMapPath -Raw | ConvertFrom-Json -AsHashtable

    $effectiveEnd = $EndDate
    if ($EndDate.TimeOfDay -eq [TimeSpan]::Zero) {
        $effectiveEnd = $EndDate.Date.AddDays(1)
    }

    $rawFromUtc = $StartDate.ToUniversalTime()
    $rawToUtc = $effectiveEnd.ToUniversalTime()

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

    $queueSummary = Get-QueueSummary -MetricRows $detailRows
    $agentSummary = Get-AgentSummary -MetricRows $detailRows

    if (-not (Test-Path -LiteralPath $config.Reporting.ReportsPath)) {
        New-Item -Path $config.Reporting.ReportsPath -ItemType Directory -Force | Out-Null
    }

    $stamp = "{0}_to_{1}" -f $StartDate.ToString("yyyyMMdd"), $EndDate.ToString("yyyyMMdd")
    $xlsxPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}.xlsx" -f $OutputName, $stamp)
    $pdfPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}.pdf" -f $OutputName, $stamp)
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
            $finalXlsxPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}{2}.xlsx" -f $OutputName, $stamp, $suffix)
            $finalPdfPath = Join-Path $config.Reporting.ReportsPath ("{0}_{1}{2}.pdf" -f $OutputName, $stamp, $suffix)

            Write-ReportLog -LogFile $run.LogFile -Level WARN -Message "Primary output file is locked. Retrying with alternate filenames: $finalXlsxPath and $finalPdfPath"

            Export-ReportWorkbook -DetailRows $detailRows -QueueSummary $queueSummary -AgentSummary $agentSummary -WorkbookPath $finalXlsxPath | Out-Null
            Export-ReportPdf -QueueSummary $queueSummary -AgentSummary $agentSummary -PdfPath $finalPdfPath -PdfGenerator $config.Reporting.PdfGenerator | Out-Null
        }
        else {
            throw
        }
    }

    if (-not $SkipEmail) {
        $subject = "{0} - On Demand ({1})" -f $config.Email.SubjectPrefix, $stamp
        $body = "<p>Attached are the on-demand service center queue reports for <b>$stamp</b>.</p><p>Run ID: $($run.RunId)</p>"
        Send-ReportEmail -EmailConfig $config.Email -Subject $subject -BodyHtml $body -AttachmentPaths @($finalXlsxPath, $finalPdfPath) -GraphConfig $config.Graph
    }

    Write-ReportLog -LogFile $run.LogFile -Message "On-demand report run completed. Output: $finalXlsxPath, $finalPdfPath"
}
catch {
    Write-ReportLog -LogFile $run.LogFile -Level ERROR -Message ("On-demand report failed: {0}" -f $_.Exception.Message)
    throw
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
