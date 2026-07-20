[CmdletBinding(DefaultParameterSetName = "Tag")]
param(
    [string]$RepoPath = $PSScriptRoot,

    [Parameter(Mandatory = $true, ParameterSetName = "Tag")]
    [string]$Tag,

    [Parameter(Mandatory = $true, ParameterSetName = "Commit")]
    [string]$Commit,

    [Parameter(Mandatory = $true, ParameterSetName = "List")]
    [switch]$ListAvailable,

    [switch]$AllowDirty,
    [switch]$RunValidation,
    [datetime]$ValidationStartDate,
    [datetime]$ValidationEndDate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-RollbackLog {
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
            Write-RollbackLog -Message ("git {0}" -f $line)
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
$script:LogFile = Join-Path $logDir ("rollback_{0}_{1}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"), $runId)
Write-RollbackLog -Message ("Rollback started. RunId={0}" -f $runId)
Write-RollbackLog -Message ("RepoPath={0}" -f $repoFullPath)

Push-Location $repoFullPath
try {
    if (-not (Test-Path -LiteralPath (Join-Path $repoFullPath ".git"))) {
        throw "RepoPath is not a Git repository: $repoFullPath"
    }

    Invoke-Git -Arguments @("fetch", "origin", "--prune", "--tags") | Out-Null

    if ($ListAvailable) {
        Write-RollbackLog -Message "Listing recent tags and commits."

        $tags = (Invoke-Git -Arguments @("tag", "--sort=-creatordate")).Output | Select-Object -First 15
        $commits = (Invoke-Git -Arguments @("log", "--oneline", "-15")).Output

        Write-Host "Recent tags:"
        if ($tags.Count -eq 0) {
            Write-Host "  (no tags found)"
        }
        else {
            foreach ($item in $tags) {
                Write-Host ("  {0}" -f $item)
            }
        }

        Write-Host ""
        Write-Host "Recent commits:"
        foreach ($item in $commits) {
            Write-Host ("  {0}" -f $item)
        }

        Write-RollbackLog -Message "List operation completed."
        Write-Host "Rollback list complete. Log: $script:LogFile"
        return
    }

    $statusResult = Invoke-Git -Arguments @("status", "--porcelain")
    if (-not $AllowDirty -and $statusResult.Output.Count -gt 0) {
        throw "Working tree has uncommitted changes. Commit/stash first, or re-run with -AllowDirty."
    }

    $previousHead = ((Invoke-Git -Arguments @("rev-parse", "--short", "HEAD")).Output | Select-Object -Last 1).Trim()
    $previousDesc = ((Invoke-Git -Arguments @("describe", "--tags", "--always", "--dirty")).Output | Select-Object -Last 1).Trim()

    $targetRef = ""
    if ($PSCmdlet.ParameterSetName -eq "Tag") {
        $verifyTag = Invoke-Git -Arguments @("rev-parse", "--verify", "refs/tags/$Tag") -AllowFailure
        if ($verifyTag.ExitCode -ne 0) {
            throw "Tag not found: $Tag"
        }

        $targetRef = "tags/$Tag"
        Write-RollbackLog -Message ("Rolling back to tag: {0}" -f $Tag)
    }
    elseif ($PSCmdlet.ParameterSetName -eq "Commit") {
        $verifyCommit = Invoke-Git -Arguments @("rev-parse", "--verify", $Commit) -AllowFailure
        if ($verifyCommit.ExitCode -ne 0) {
            throw "Commit not found: $Commit"
        }

        $targetRef = $Commit
        Write-RollbackLog -Message ("Rolling back to commit: {0}" -f $Commit)
    }

    Invoke-Git -Arguments @("checkout", "--detach", $targetRef) | Out-Null

    $newHead = ((Invoke-Git -Arguments @("rev-parse", "--short", "HEAD")).Output | Select-Object -Last 1).Trim()
    $newDesc = ((Invoke-Git -Arguments @("describe", "--tags", "--always", "--dirty")).Output | Select-Object -Last 1).Trim()

    Write-RollbackLog -Message ("Previous ref: {0} ({1})" -f $previousHead, $previousDesc)
    Write-RollbackLog -Message ("Current ref:  {0} ({1})" -f $newHead, $newDesc)

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

        Write-RollbackLog -Message ("Running validation: {0} -> {1}" -f $ValidationStartDate.ToString("yyyy-MM-dd"), $ValidationEndDate.ToString("yyyy-MM-dd"))

        $validationArgs = @(
            "-NoProfile",
            "-File", $validationScript,
            "-StartDate", $ValidationStartDate.ToString("yyyy-MM-dd"),
            "-EndDate", $ValidationEndDate.ToString("yyyy-MM-dd"),
            "-OutputName", "RollbackValidation",
            "-SkipEmail"
        )

        & pwsh @validationArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Validation run failed with exit code $LASTEXITCODE"
        }

        Write-RollbackLog -Message "Validation run completed successfully."
    }
    else {
        Write-RollbackLog -Message "Validation step skipped. Use -RunValidation to enable it." -Level WARN
    }

    Write-RollbackLog -Message "Rollback completed successfully."
    Write-Host "Rollback complete. Log: $script:LogFile"
}
catch {
    Write-RollbackLog -Level ERROR -Message ("Rollback failed: {0}" -f $_.Exception.Message)
    throw
}
finally {
    Pop-Location
}
