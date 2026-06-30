function Export-ReportPdf {
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [array]$QueueSummary,

        [Parameter()]
        [AllowEmptyCollection()]
        [array]$AgentSummary,

        [Parameter(Mandatory = $true)]
        [string]$PdfPath,

        [Parameter(Mandatory = $true)]
        [string]$PdfGenerator
    )

    $generatorCommand = Get-Command $PdfGenerator -ErrorAction SilentlyContinue
    if (-not $generatorCommand -and $PdfGenerator -ieq "wkhtmltopdf") {
        $fallbackCandidates = @(
            "C:\Program Files\wkhtmltopdf\bin\wkhtmltopdf.exe",
            "C:\Program Files (x86)\wkhtmltopdf\bin\wkhtmltopdf.exe"
        )

        $resolved = $fallbackCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($resolved) {
            $generatorCommand = [PSCustomObject]@{
                Source = $resolved
            }
        }
    }

    if (-not $generatorCommand) {
        throw "PDF generation tool '$PdfGenerator' not found. Install wkhtmltopdf or set Reporting.PdfGenerator in config."
    }

    $tempHtml = [System.IO.Path]::GetTempFileName().Replace(".tmp", ".html")

    if (-not $QueueSummary -or $QueueSummary.Count -eq 0) {
        $queueRows = "<tr><td colspan='6'>No queue data found for this reporting window.</td></tr>"
    }
    else {
        $queueRows = ($QueueSummary | ForEach-Object {
            "<tr><td>$($_.QueueName)</td><td>$($_.Offered)</td><td>$($_.Answered)</td><td>$($_.Voicemail)</td><td>$($_.Abandoned)</td><td>$($_.SLAPercent)%</td></tr>"
        }) -join [Environment]::NewLine
    }

    if (-not $AgentSummary -or $AgentSummary.Count -eq 0) {
        $agentRows = "<tr><td colspan='4'>No agent data found for this reporting window.</td></tr>"
    }
    else {
        $agentRows = ($AgentSummary | Select-Object -First 50 | ForEach-Object {
            "<tr><td>$($_.QueueName)</td><td>$($_.AgentName)</td><td>$($_.AnsweredCalls)</td><td>$($_.AvgWaitSeconds)</td></tr>"
        }) -join [Environment]::NewLine
    }

    $html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<title>Service Center Report</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; }
h1, h2 { color: #1f4e79; }
table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background-color: #f2f2f2; }
small { color: #555; }
</style>
</head>
<body>
<h1>Service Center Call Queue Report</h1>
<small>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</small>

<h2>Queue Summary</h2>
<table>
<tr><th>Queue</th><th>Offered</th><th>Answered</th><th>Voicemail</th><th>Abandoned</th><th>SLA %</th></tr>
$queueRows
</table>

<h2>Top Agents by Answered Calls</h2>
<table>
<tr><th>Queue</th><th>Agent</th><th>Answered Calls</th><th>Avg Wait Seconds</th></tr>
$agentRows
</table>
</body>
</html>
"@

    Set-Content -Path $tempHtml -Value $html -Encoding UTF8

    & $generatorCommand.Source --enable-local-file-access $tempHtml $PdfPath | Out-Null

    Remove-Item -LiteralPath $tempHtml -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $PdfPath)) {
        throw "PDF generation failed: $PdfPath"
    }

    return $PdfPath
}
