# Production Script Update Workflow

This document defines a safe, repeatable process to:

1. Update scripts from your local PC.
2. Push changes to `dev` for validation.
3. Promote approved changes to `main`.
4. Pull and deploy `main` on the production VM.

Use this workflow every time you change reporting scripts.

## Branch model used by this repo

- `main`: production-ready code only.
- `dev`: integration branch for testing before production.
- Optional feature branches: short-lived branches created from `dev`.

## One-time setup

### Local PC

1. Confirm your repo has `origin` set:

```powershell
git remote -v
```

2. Confirm both `dev` and `main` exist on remote:

```powershell
git fetch origin --prune
git branch -r
```

### Production VM

1. Install Git (one time).
2. Clone the repo to a stable path, example:

```powershell
git clone <REPO_URL> C:\BehrReports\Behr_ServiceCenterReports
```

3. Configure line endings to avoid script diffs:

```powershell
git config --global core.autocrlf true
```

4. Verify scheduled tasks point to scripts in this clone path.

## Standard update flow (PC to dev)

### 1. Sync and branch from `dev`

From your local repo:

```powershell
git checkout dev
git pull origin dev
git checkout -b feature/<short-change-name>
```

### 2. Make script/config/module updates

Update files as needed, then review changes:

```powershell
git status
git diff
```

### 3. Run local validation

Run the relevant scripts before pushing:

```powershell
pwsh ./Tests/Test-Classification.ps1
pwsh ./Tests/Test-Metrics.ps1
pwsh ./Scripts/On-Demand-Report.ps1 -StartDate "2026-07-01" -EndDate "2026-07-08" -SkipEmail
```

If your change is Solutions Center specific, also run:

```powershell
pwsh ./Scripts/On-Demand-Report-SolutionsCenter.ps1 -StartDate "2026-07-01" -EndDate "2026-07-08" -SkipEmail
```

### 4. Commit and push feature branch

```powershell
git add .
git commit -m "<clear summary of change>"
git push -u origin feature/<short-change-name>
```

### 5. Merge into `dev`

Use a Pull Request from `feature/...` -> `dev` and complete required review/checks.

If you merge directly (only if your process allows it):

```powershell
git checkout dev
git pull origin dev
git merge --no-ff feature/<short-change-name>
git push origin dev
```

## Promote from dev to main

### 1. Verify `dev` is stable

At minimum:

1. All tests pass.
2. Dry-run report generation succeeds.
3. Any output naming behavior is confirmed.

### 2. Create Pull Request `dev` -> `main`

Recommended method:

1. Open PR from `dev` to `main`.
2. Require approval.
3. Use merge commit (keeps release traceability).

Alternative direct merge from local (if approved in your process):

```powershell
git checkout main
git pull origin main
git merge --no-ff dev
git push origin main
```

### 3. Tag the production release

After `main` is updated:

```powershell
git checkout main
git pull origin main
git tag -a v2026.07.20.1 -m "Prod release 2026-07-20"
git push origin v2026.07.20.1
```

Use a consistent tag format such as `vYYYY.MM.DD.N`.

## Deploy on production VM (pull from main)

### Option A: Use deployment script (recommended)

From the repo root on VM:

```powershell
pwsh ./Deploy-Prod.ps1 -RepoPath .
```

Deploy a specific release tag:

```powershell
pwsh ./Deploy-Prod.ps1 -RepoPath . -Tag v2026.07.20.1
```

Deploy and run validation dry-run:

```powershell
pwsh ./Deploy-Prod.ps1 -RepoPath . -RunValidation
```

Validation with explicit date range:

```powershell
pwsh ./Deploy-Prod.ps1 -RepoPath . -RunValidation -ValidationStartDate "2026-07-01" -ValidationEndDate "2026-07-08"
```

### Option B: Manual git commands

Run on the VM inside the repo path:

```powershell
Set-Location C:\BehrReports\Behr_ServiceCenterReports
git fetch origin --prune --tags
git checkout main
git pull origin main
git log -1 --oneline
```

If deploying by release tag instead of branch tip:

```powershell
git fetch origin --tags
git checkout tags/v2026.07.20.1
```

## Post-deploy verification on VM

1. Confirm latest files exist (`git status`, `git log -1`).
2. Run a dry run:

```powershell
pwsh ./Scripts/On-Demand-Report.ps1 -StartDate "2026-07-01" -EndDate "2026-07-08" -SkipEmail
```

3. Check generated outputs in `Output/Reports`.
4. Confirm Task Scheduler still points to expected script paths.

## Rollback procedure

### Option A: Use rollback script (recommended)

List recent tags/commits to choose from:

```powershell
pwsh ./Rollback-Prod.ps1 -RepoPath . -ListAvailable
```

Rollback to a known-good tag:

```powershell
pwsh ./Rollback-Prod.ps1 -RepoPath . -Tag v2026.07.10.1
```

Rollback to a specific commit:

```powershell
pwsh ./Rollback-Prod.ps1 -RepoPath . -Commit <commit-sha>
```

Rollback and run validation:

```powershell
pwsh ./Rollback-Prod.ps1 -RepoPath . -Tag v2026.07.10.1 -RunValidation
```

### Option B: Manual git commands

If production behavior is incorrect:

1. Find previous good tag/commit:

```powershell
git tag --sort=-creatordate
git log --oneline -20
```

2. Roll back to prior known-good tag:

```powershell
git checkout tags/<previous-good-tag>
```

3. Re-run a dry run and confirm expected output.
4. Record the rollback in your change log/PR notes.

## Daily command cheat sheet

### PC: quick update cycle

```powershell
git checkout dev
git pull origin dev
git checkout -b feature/<name>
# edit files
git add .
git commit -m "<message>"
git push -u origin feature/<name>
```

### VM: pull latest production

```powershell
Set-Location C:\BehrReports\Behr_ServiceCenterReports
git checkout main
git pull origin main
git log -1 --oneline
```

### VM: finalize after rollback testing

Switch back to `main`, pull latest, and record audit history:

```powershell
pwsh ./Finalize-Prod-Update.ps1 -RepoPath . -SwitchToMain -RunValidation -Note "Post-rollback verification complete"
```

Record history only (no branch switch):

```powershell
pwsh ./Finalize-Prod-Update.ps1 -RepoPath . -Note "Manual verification completed"
```

Deployment history file is written to:

- `Output/Logs/Deployments/deployment-history.log`

## Operational guardrails

1. Do not edit production files directly on VM unless emergency hotfix is required.
2. Keep all production changes traceable through Git commits and PRs.
3. Prefer PR-based merges over direct pushes to `main`.
4. Tag every production release so rollback is fast and low risk.
