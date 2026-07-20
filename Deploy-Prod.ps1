[CmdletBinding()]
param(
    [string]$RepoPath = $PSScriptRoot,
    [string]$Branch = "main",
    [string]$Tag,
    [switch]$AllowDirty,
    [switch]$RunValidation,
    [datetime]$ValidationStartDate,
    [datetime]$ValidationEndDate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-DeployLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line

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
            Write-DeployLog -Message ("git {0}" -f $line)
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
$script:LogFile = Join-Path $logDir ("deploy_{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $runId)
Write-DeployLog -Message ("Deployment started. RunId={0}" -f $runId)
Write-DeployLog -Message ("RepoPath={0}" -f $repoFullPath)
Write-DeployLog -Message ("Branch={0}; Tag={1}" -f $Branch, $(if ([string]::IsNullOrWhiteSpace($Tag)) { "<none>" } else { $Tag }))

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

    Invoke-Git -Arguments @("fetch", "origin", "--prune", "--tags") | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        $verifyTag = Invoke-Git -Arguments @("rev-parse", "--verify", "refs/tags/$Tag") -AllowFailure
        if ($verifyTag.ExitCode -ne 0) {
            throw "Tag not found: $Tag"
        }

        Invoke-Git -Arguments @("checkout", "--detach", "tags/$Tag") | Out-Null
        Write-DeployLog -Message ("Checked out deployment tag: {0}" -f $Tag)
    }
    else {
        Invoke-Git -Arguments @("checkout", $Branch) | Out-Null
        Invoke-Git -Arguments @("pull", "--ff-only", "origin", $Branch) | Out-Null
        Write-DeployLog -Message ("Updated branch from origin: {0}" -f $Branch)
    }

    $newHead = ((Invoke-Git -Arguments @("rev-parse", "--short", "HEAD")).Output | Select-Object -Last 1).Trim()
    $newDesc = ((Invoke-Git -Arguments @("describe", "--tags", "--always", "--dirty")).Output | Select-Object -Last 1).Trim()

    Write-DeployLog -Message ("Previous ref: {0} ({1})" -f $previousHead, $previousDesc)
    Write-DeployLog -Message ("Current ref:  {0} ({1})" -f $newHead, $newDesc)

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

        Write-DeployLog -Message ("Running validation: {0} -> {1}" -f $ValidationStartDate.ToString("yyyy-MM-dd"), $ValidationEndDate.ToString("yyyy-MM-dd"))

        $validationArgs = @(
            "-NoProfile",
            "-File", $validationScript,
            "-StartDate", $ValidationStartDate.ToString("yyyy-MM-dd"),
            "-EndDate", $ValidationEndDate.ToString("yyyy-MM-dd"),
            "-OutputName", "DeployValidation",
            "-SkipEmail"
        )

        & pwsh @validationArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Validation run failed with exit code $LASTEXITCODE"
        }

        Write-DeployLog -Message "Validation run completed successfully."
    }
    else {
        Write-DeployLog -Message "Validation step skipped. Use -RunValidation to enable it." -Level WARN
    }

    Write-DeployLog -Message "Deployment completed successfully."
    Write-Host "Deployment complete. Log: $script:LogFile"
}
catch {
    Write-DeployLog -Level ERROR -Message ("Deployment failed: {0}" -f $_.Exception.Message)
    throw
}
finally {
    Pop-Location
}
