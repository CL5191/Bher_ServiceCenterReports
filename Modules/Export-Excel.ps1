function Export-ReportWorkbook {
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [array]$DetailRows,

        [Parameter()]
        [AllowEmptyCollection()]
        [array]$QueueSummary,

        [Parameter()]
        [AllowEmptyCollection()]
        [array]$AgentSummary,

        [Parameter(Mandatory = $true)]
        [string]$WorkbookPath
    )

    Import-Module ImportExcel -ErrorAction Stop

    if (-not $DetailRows -or $DetailRows.Count -eq 0) {
        $DetailRows = @(
            [PSCustomObject]@{
                Message = "No call records found for the selected date range."
            }
        )
    }

    if (-not $QueueSummary -or $QueueSummary.Count -eq 0) {
        $QueueSummary = @(
            [PSCustomObject]@{
                QueueName        = "No Data"
                Offered          = 0
                Answered         = 0
                AnsweredUnderSLA = 0
                SLAPercent       = 0
                Voicemail        = 0
                Abandoned        = 0
                AvgWaitSeconds   = 0
                AvgHandleSeconds = 0
                AvgHandleMinutes = 0
            }
        )
    }

    if (-not $AgentSummary -or $AgentSummary.Count -eq 0) {
        $AgentSummary = @(
            [PSCustomObject]@{
                QueueName      = "No Data"
                AgentName      = "N/A"
                AgentId        = "N/A"
                AnsweredCalls  = 0
                AvgWaitSeconds = 0
            }
        )
    }

    if (Test-Path -LiteralPath $WorkbookPath) {
        Remove-Item -LiteralPath $WorkbookPath -Force
    }

    $DetailRows | Export-Excel -Path $WorkbookPath -WorksheetName "Detail" -TableName "CallDetail" -AutoSize -AutoFilter
    $QueueSummary | Export-Excel -Path $WorkbookPath -WorksheetName "QueueSummary" -TableName "QueueSummary" -AutoSize -AutoFilter -Append
    $AgentSummary | Export-Excel -Path $WorkbookPath -WorksheetName "AgentSummary" -TableName "AgentSummary" -AutoSize -AutoFilter -Append

    $lastDataRow = $QueueSummary.Count + 1
    $chartRow = $lastDataRow + 2

    $chartDefBar = New-ExcelChartDefinition -Title "Queue Volume" -ChartType ColumnClustered -XRange QueueSummary[QueueName] -YRange QueueSummary[Offered],QueueSummary[Answered],QueueSummary[Abandoned] -SeriesHeader "Offered","Answered","Abandoned" -Row $chartRow -Column 1 -Width 640 -Height 320 -NoLegend:$false
    # Place the second chart one worksheet column away from the first chart's footprint.
    $chartDefPie = New-ExcelChartDefinition -Title "Answered vs Voicemail vs Abandoned" -ChartType Pie -XRange QueueSummary[QueueName] -YRange QueueSummary[Answered] -Row $chartRow -Column 10 -Width 520 -Height 320 -NoLegend:$false

    Export-Excel -Path $WorkbookPath -WorksheetName "QueueSummary" -ExcelChartDefinition $chartDefBar -Append
    Export-Excel -Path $WorkbookPath -WorksheetName "QueueSummary" -ExcelChartDefinition $chartDefPie -Append

    return $WorkbookPath
}
