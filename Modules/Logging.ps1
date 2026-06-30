function New-RunContext {
    param(
        [string]$LogsPath
    )

    if (-not (Test-Path -LiteralPath $LogsPath)) {
        New-Item -Path $LogsPath -ItemType Directory -Force | Out-Null
    }

    $runId = [guid]::NewGuid().Guid
    $logFile = Join-Path $LogsPath ("run_{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $runId)

    return [PSCustomObject]@{
        RunId = $runId
        LogFile = $logFile
    }
}

function Write-ReportLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $true)]
        [string]$LogFile
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogFile -Value $line

    switch ($Level) {
        "ERROR" { Write-Error $Message }
        "WARN" { Write-Warning $Message }
        default { Write-Host $Message }
    }
}
