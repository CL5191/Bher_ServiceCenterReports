# Behr Service Center Reports v2

This repository now includes a new modular reporting program that leaves `AAGraphreport.ps1` unchanged.

## What it does

- Pulls call records for configured queue resource accounts from Microsoft Graph.
- Classifies calls into offered, answered, voicemail, abandoned, and answered-under-SLA.
- Produces charted Excel output (`.xlsx`) and PDF output (`.pdf`).
- Sends report artifacts to a configured distribution list via Graph Mail.Send.
- Supports both monthly scheduled execution and on-demand execution.
- Uses standard output names for scheduled reports:
   - Monthly: `Behr-ServiceCenter-Monthly`
   - Last 7 days: `Behr-ServiceCenter-Weekly`

## New structure

- `Config/config.ps1`: Core settings (Graph auth, output paths, email, SLA).
- `Config/queues.json`: Queue resource account ID to queue name map.
- `Modules/*.ps1`: Reusable modules for logging, Graph operations, classification, metrics, exports, and email.
- `Scripts/Monthly-Report.ps1`: Scheduled monthly orchestrator.
- `Scripts/On-Demand-Report.ps1`: Ad-hoc date-range orchestrator.
- `Scheduled-Tasks/Install-AzureAutomationSchedule.ps1`: Helper to create Azure Automation schedule commands.
- `Tests/*.ps1`: Basic unit-style checks for classification and metrics.

## Prerequisites

1. PowerShell 7+
1. Graph app registration with application permissions and admin consent:
   - `CallRecords.Read.All`
   - `Mail.Send`
1. Certificate uploaded and available for non-interactive auth.
1. Modules:
   - `Microsoft.Graph.Authentication`
   - `ImportExcel`
1. PDF engine installed in runtime path:
   - `wkhtmltopdf`

Install modules:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force
Install-Module ImportExcel -Scope CurrentUser -Force
```

## Configure

1. Update `Config/config.ps1`:
   - `Graph.TenantId`
   - `Graph.ClientId`
   - `Graph.CertificateThumbprint`
   - `Email.SenderMailbox`
   - `Email.ToRecipients`
2. Update `Config/queues.json` with all queue resource account IDs.
3. Standalone Solutions Center report uses `Config/queues-solutions-center.json` and does not depend on `Config/queues.json`.

## Run

Monthly (previous month range):

```powershell
pwsh ./Scripts/Monthly-Report.ps1
```

On-demand:

```powershell
pwsh ./Scripts/On-Demand-Report.ps1 -StartDate "2026-06-01" -EndDate "2026-07-01"
```

On-demand with custom output name:

```powershell
pwsh ./Scripts/On-Demand-Report.ps1 -StartDate "2026-06-01" -EndDate "2026-07-01" -OutputName "My-Custom-Report"
```

Last 7 days (separate process):

```powershell
pwsh ./Last-7Days-Report.ps1
```

Dry-run without email:

```powershell
pwsh ./Scripts/On-Demand-Report.ps1 -StartDate "2026-06-01" -EndDate "2026-07-01" -SkipEmail
```

Dry-run last 7 days:

```powershell
pwsh ./Last-7Days-Report.ps1 -SkipEmail
```

## Standalone Solutions Center CQ

This report stream is separate from the default multi-queue reports and uses only queue ID `fa4b81a5-854d-45ee-9708-7b79d1866371` (`Behr Solutions Center cQ`).

Weekly (output base name: `Behr-SolutionsCenterWeekly`):

```powershell
pwsh ./SolutionsCenter-Last-7Days-Report.ps1
```

Monthly 28-day window (output base name: `Behr-SolutionsCenterMonthly`):

```powershell
pwsh ./SolutionsCenter-Monthly-Report.ps1
```

On-demand for custom range:

```powershell
pwsh ./Scripts/On-Demand-Report-SolutionsCenter.ps1 -StartDate "2026-06-01" -EndDate "2026-07-01"
```

Dry-run without email:

```powershell
pwsh ./SolutionsCenter-Last-7Days-Report.ps1 -SkipEmail
pwsh ./SolutionsCenter-Monthly-Report.ps1 -SkipEmail
```

## Azure Automation scheduling

Use helper script to print `Az.Automation` commands for monthly day-1 6:00 AM schedule:

```powershell
pwsh ./Scheduled-Tasks/Install-AzureAutomationSchedule.ps1 -ResourceGroupName <rg> -AutomationAccountName <account>
```

## Notes

- `AAGraphreport.ps1` is unchanged and can be retained as legacy reference.
- Graph call records have retention/latency constraints; schedule runs accordingly.
- PDF generation requires `wkhtmltopdf` to be available on the host running scripts.
