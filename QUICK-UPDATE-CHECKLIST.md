# Definitive Safe Update Checklist

Use this exact process every time. Do not skip steps.

## Pocket Version (One Glance)

1. Local PC:

```powershell
git checkout dev
git pull origin dev
git status
git add .
git diff --cached --name-status
git commit -m "Describe exactly what changed"
git push origin dev
```

2. GitHub:

- Open PR: `dev` -> `master`
- Review files and merge

3. Production VM:

```powershell
Set-Location C:\BehrReports\Behr_ServiceCenterReports
pwsh ./Deploy-Prod.ps1 -RepoPath . -Branch master -RunValidation
git log -1 --oneline
```

4. If issue:

```powershell
pwsh ./Rollback-Prod.ps1 -RepoPath . -ListAvailable
pwsh ./Rollback-Prod.ps1 -RepoPath . -Tag <good-tag> -RunValidation
```

## A) Local PC update to dev (safe path)

1. Sync and confirm you are on `dev`:

```powershell
git checkout dev
git pull origin dev
```

2. Review current changes:

```powershell
git status
git diff
```

3. Stage changes:

- If you want everything changed in this repo:

```powershell
git add .
```

- If you want only specific files:

```powershell
git add <file1> <file2> <file3>
```

4. Safety check staged content (required):

```powershell
git diff --cached --name-status
```

If any file should not be included, stop and unstage it:

```powershell
git restore --staged <file>
```

5. Commit with a clear message:

```powershell
git commit -m "Describe exactly what changed"
```

6. Push to `dev`:

```powershell
git push origin dev
```

## B) Promote dev to production branch

1. Open GitHub Pull Request:

- Base: `master`
- Compare: `dev`

2. Review `Files changed` and merge only after review.

## C) Deploy to production VM

Run on the VM in the repo folder:

```powershell
Set-Location C:\BehrReports\Behr_ServiceCenterReports
pwsh ./Deploy-Prod.ps1 -RepoPath . -Branch master -RunValidation
git log -1 --oneline
```

## D) If production issue appears

1. List rollback targets:

```powershell
pwsh ./Rollback-Prod.ps1 -RepoPath . -ListAvailable
```

2. Roll back to known good tag:

```powershell
pwsh ./Rollback-Prod.ps1 -RepoPath . -Tag <good-tag> -RunValidation
```

3. After testing, return to production branch and log audit:

```powershell
pwsh ./Finalize-Prod-Update.ps1 -RepoPath . -SwitchToMain -Branch master -RunValidation -Note "Rollback tested"
```

## 15-second confidence check before every push

```powershell
git branch -vv
git status
git diff --cached --name-status
```

If branch is not `dev` or staged files are unexpected, stop.
