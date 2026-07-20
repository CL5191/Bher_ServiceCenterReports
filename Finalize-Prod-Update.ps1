[CmdletBinding()]
param(
    [string]$RepoPath = $PSScriptRoot,
    [string]$Branch = "main",
    [switch]$SwitchToMain,
    [switch]$AllowDirty,
    [switch]$RunValidation,
    [datetime]$ValidationStartDate,
    [datetime]$ValidationEndDate,
    [string]$Note = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-FinalizeLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $script:RunLogFile -Value $line

    switch ($Level) {
        "ERROR" { Write-Error $Message }
        "WARN" { Write-Warning $Message }
        default { Write-Host $Message }
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $output = & git @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($output) {
        foreach ($line in $output) {
            Write-FinalizeLog -Message ("git {0}" -f $line)
        }
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode"
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output = @($output)
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is not installed or not available in PATH."
}

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    throw "PowerShell 7 (pwsh) is required for validation runs."
}

if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    throw "RepoPath does not exist: $RepoPath"
}

$repoFullPath = (Resolve-Path -LiteralPath $RepoPath).Path
$logDir = Join-Path $repoFullPath "Output\Logs\Deployments"
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

$runId = [guid]::NewGuid().Guid
$script:RunLogFile = Join-Path $logDir ("finalize_{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $runId)
$historyFile = Join-Path $logDir "deployment-history.log"

Write-FinalizeLog -Message ("Finalize started. RunId={0}" -f $runId)
Write-FinalizeLog -Message ("RepoPath={0}" -f $repoFullPath)
Write-FinalizeLog -Message ("SwitchToMain={0}; Branch={1}" -f $SwitchToMain.IsPresent, $Branch)

Push-Location $repoFullPath
try {
    if (-not (Test-Path -LiteralPath (Join-Path $repoFullPath ".git"))) {
        throw "RepoPath is not a Git repository: $repoFullPath"
    }

    $statusResult = Invoke-Git -Arguments @("status", "--porcelain")
    if (-not $AllowDirty -and $statusResult.Output.Count -gt 0) {
        throw "Working tree has uncommitted changes. Commit/stash first, or re-run with -AllowDirty."
    }

    $previousHead = ((Invoke-Git -Arguments @("rev-parse", "--short", "HEAD")).Output | Select-Object -Last 1).Trim()
    $previousDesc = ((Invoke-Git -Arguments @("describe", "--tags", "--always", "--dirty")).Output | Select-Object -Last 1).Trim()

    if ($SwitchToMain) {
        Invoke-Git -Arguments @("fetch", "origin", "--prune", "--tags") | Out-Null
        Invoke-Git -Arguments @("checkout", $Branch) | Out-Null
        Invoke-Git -Arguments @("pull", "--ff-only", "origin", $Branch) | Out-Null
        Write-FinalizeLog -Message ("Switched to branch and updated from origin: {0}" -f $Branch)
    }
    else {
        Write-FinalizeLog -Message "Switch step skipped. Only recording deployment history." -Level WARN
    }

    $newHead = ((Invoke-Git -Arguments @("rev-parse", "--short", "HEAD")).Output | Select-Object -Last 1).Trim()
    $newDesc = ((Invoke-Git -Arguments @("describe", "--tags", "--always", "--dirty")).Output | Select-Object -Last 1).Trim()

    if ($RunValidation) {
        if (-not $PSBoundParameters.ContainsKey("ValidationEndDate")) {
            $ValidationEndDate = (Get-Date).Date
        }
        if (-not $PSBoundParameters.ContainsKey("ValidationStartDate")) {
            $ValidationStartDate = $ValidationEndDate.AddDays(-7)
        }
        if ($ValidationEndDate -le $ValidationStartDate) {
            throw "ValidationEndDate must be later than ValidationStartDate."
        }

        $validationScript = Join-Path $repoFullPath "Scripts\On-Demand-Report.ps1"
        if (-not (Test-Path -LiteralPath $validationScript -PathType Leaf)) {
            throw "Validation script not found: $validationScript"
        }

        Write-FinalizeLog -Message ("Running validation: {0} -> {1}" -f $ValidationStartDate.ToString("yyyy-MM-dd"), $ValidationEndDate.ToString("yyyy-MM-dd"))

        $validationArgs = @(
            "-NoProfile",
            "-File", $validationScript,
            "-StartDate", $ValidationStartDate.ToString("yyyy-MM-dd"),
            "-EndDate", $ValidationEndDate.ToString("yyyy-MM-dd"),
            "-OutputName", "FinalizeValidation",
            "-SkipEmail"
        )

        & pwsh @validationArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Validation run failed with exit code $LASTEXITCODE"
        }

        Write-FinalizeLog -Message "Validation run completed successfully."
    }

    if (-not (Test-Path -LiteralPath $historyFile -PathType Leaf)) {
        "TimestampUtc|User|Computer|Action|FromRef|ToRef|Note|RunLog" | Out-File -LiteralPath $historyFile -Encoding utf8
    }

    $action = if ($SwitchToMain) { "SwitchToMain" } else { "RecordOnly" }
    $userName = [Environment]::UserName
    $computerName = [Environment]::MachineName
    $safeNote = ($Note -replace "[\r\n|]", " ").Trim()
    $historyLine = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}" -f (
        (Get-Date).ToUniversalTime().ToString("o"),
        $userName,
        $computerName,
        $action,
        "{0} ({1})" -f $previousHead, $previousDesc,
        "{0} ({1})" -f $newHead, $newDesc,
        $safeNote,
        $script:RunLogFile
    )
    Add-Content -LiteralPath $historyFile -Value $historyLine

    Write-FinalizeLog -Message ("History updated: {0}" -f $historyFile)
    Write-FinalizeLog -Message "Finalize completed successfully."

    Write-Host "Finalize complete."
    Write-Host "Run log: $script:RunLogFile"
    Write-Host "History: $historyFile"
}
catch {
    Write-FinalizeLog -Level ERROR -Message ("Finalize failed: {0}" -f $_.Exception.Message)
    throw
}
finally {
    Pop-Location
}
