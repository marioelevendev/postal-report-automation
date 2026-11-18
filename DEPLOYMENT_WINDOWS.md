# Windows deployment guide

This project supports two deployment methods:

1. A tracked Git checkout, recommended for the PyCharm computer.
2. A credential-free ZIP, useful for a Windows machine without Git.

## Tracked checkout

Use this location:

```text
C:\Users\m.diles\PycharmProjects\postal_report_automation
```

Run:

```powershell
Set-Location "C:\Users\m.diles\PycharmProjects"
git clone https://github.com/marioelevendev/postal-report-automation.git
Set-Location ".\postal_report_automation"
.\setup.ps1
```

Copy or create the private `.env`, then enable production delivery:

```dotenv
POSTAL_HEADLESS=true
POSTAL_COPY_TO_TALEND=true
POSTAL_TALEND_TRIGGER_DIR=\\FILE-SRV01\epa_files\EpaSyn2\Talend_Triggers
POSTAL_APPEND_NETWORK_LOG=true
POSTAL_NETWORK_LOG_FILE=\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs\postal-report-automation-1001234.txt
POSTAL_RETRY_DELAY_SECONDS=60
POSTAL_ERROR_LOG_DIR=\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs
```

Verify the environment:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe .\main.py --dry-run
Test-Path "\\FILE-SRV01\epa_files\EpaSyn2\Talend_Triggers"
Test-Path "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs"
```

Install the task:

```powershell
.\install_daily_task.ps1
```

Enter the Windows password when prompted. The password-backed task runs daily
at 07:05 even while the user is logged out and retains UNC-share access.

Test and inspect it:

```powershell
Start-ScheduledTask -TaskName "Postal Report Automation"
Get-ScheduledTaskInfo -TaskName "Postal Report Automation"
Get-ChildItem .\logs | Sort-Object LastWriteTime -Descending
```

## Updating the tracked checkout

```powershell
Set-Location "C:\Users\m.diles\PycharmProjects\postal_report_automation"
git pull --ff-only
.\setup.ps1
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

The private `.env`, `.venv`, reports, and logs are ignored by Git.

## Building a credential-free deployment ZIP

On the tracked development computer:

```powershell
.\build_deployment.ps1
```

This creates:

```text
dist\postal-report-automation-deployment.zip
dist\postal-report-automation-deployment.zip.sha256.txt
```

The package excludes `.env`, `.venv`, Git metadata, IDE settings, reports,
logs, caches, and earlier deployment archives.

## First ZIP deployment

The production installation root is:

```text
C:\AutomationProcess\postal-report-automation
```

On the deployment computer, create the transfer directory:

```powershell
New-Item -ItemType Directory -Path "C:\AutomationProcess\postal-report-automation\dist" -Force
```

Copy these two files from the tracked development computer's `dist` directory
into that deployment `dist` directory:

```text
postal-report-automation-deployment.zip
postal-report-automation-deployment.zip.sha256.txt
```

On the deployment computer, verify and extract them:

```powershell
$projectRoot = "C:\AutomationProcess\postal-report-automation"
$zip = "$projectRoot\dist\postal-report-automation-deployment.zip"
$hashFile = "$zip.sha256.txt"
$expectedHash = ((Get-Content -LiteralPath $hashFile -Raw).Trim() -split "\s+")[0]
$actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Deployment ZIP checksum verification failed."
}
Expand-Archive -LiteralPath $zip -DestinationPath $projectRoot -Force
Set-Location $projectRoot
.\setup.ps1
```

For a new installation, configure the private file:

```powershell
notepad .env
```

Set the credentials and use safe visible-test options first:

```dotenv
POSTAL_HEADLESS=false
POSTAL_COPY_TO_TALEND=false
POSTAL_TALEND_TRIGGER_DIR=\\FILE-SRV01\epa_files\EpaSyn2\Talend_Triggers
POSTAL_APPEND_NETWORK_LOG=true
POSTAL_NETWORK_LOG_FILE=\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs\postal-report-automation-1001234.txt
POSTAL_RETRY_DELAY_SECONDS=60
POSTAL_ERROR_LOG_DIR=\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs
```

Run the tests, dry run, and one visible local-download test:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
.\.venv\Scripts\python.exe .\main.py --dry-run
.\run_now.ps1
Test-Path "\\FILE-SRV01\epa_files\EpaSyn2\Talend_Triggers"
Test-Path "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs"
```

After the visible test succeeds and `Test-Path` returns `True`, change:

```dotenv
POSTAL_HEADLESS=true
POSTAL_COPY_TO_TALEND=true
```

Then install the daily 07:05 task:

```powershell
.\install_daily_task.ps1
```

## Updating an existing ZIP installation

Use these steps for every redeployment.

There are **two different computers** in this procedure:

| Computer | Project directory | Purpose |
| --- | --- | --- |
| Development computer | `C:\Users\m.diles\PycharmProjects\postal_report_automation` | Pulls source code, runs development tests, and builds the deployment files. |
| Deployment computer (`RPA15`) | `C:\AutomationProcess\postal-report-automation` | Runs the production scheduled task and receives the built deployment files. |

Commands under one computer's heading must be run on that computer. Building
the ZIP on the development computer does not automatically place it on RPA15.

### 1. Development computer: update and verify the tracked checkout

On the development computer:

```powershell
Set-Location "C:\Users\m.diles\PycharmProjects\postal_report_automation"
git status --short
git pull --ff-only
.\setup.ps1
.\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

`git status --short` should be empty before the pull. The correct option is
`--ff-only` with two hyphens; `--f-only` is not a Git option.

### 2. Development computer: build the new deployment package

Remain in this development directory:

```text
C:\Users\m.diles\PycharmProjects\postal_report_automation
```

```powershell
.\build_deployment.ps1
```

This refreshes both files only in the development computer's directory:

```text
C:\Users\m.diles\PycharmProjects\postal_report_automation\dist\postal-report-automation-deployment.zip
C:\Users\m.diles\PycharmProjects\postal_report_automation\dist\postal-report-automation-deployment.zip.sha256.txt
```

Do not run `update_from_deployment.ps1` on the development computer. The next
step is a file transfer from the development computer to RPA15.

### 3. Between computers: transfer both deployment files to RPA15

Copy these two source files **from the development computer**:

```text
C:\Users\m.diles\PycharmProjects\postal_report_automation\dist\postal-report-automation-deployment.zip
C:\Users\m.diles\PycharmProjects\postal_report_automation\dist\postal-report-automation-deployment.zip.sha256.txt
```

Place them **on the deployment computer (`RPA15`)** in this destination
directory, replacing the older ZIP and checksum:

```text
C:\AutomationProcess\postal-report-automation\dist
```

This transfer can be performed through the approved shared folder, an RDP file
transfer, or the organization's normal deployment method. Merely running
`build_deployment.ps1` does not perform this cross-computer copy.

Do not copy the development `.env`, `.venv`, downloads, or logs.

### 4. Deployment computer (RPA15): apply the verified update

Open PowerShell on RPA15, preferably outside the 07:05 run window. The prompt
should change to `PS C:\AutomationProcess\postal-report-automation>` before the
updater is executed:

```powershell
Set-Location "C:\AutomationProcess\postal-report-automation"
.\update_from_deployment.ps1
```

The updater verifies SHA-256, prevents updates during a running scheduled task,
temporarily disables the task, preserves `.env` and `.venv`, installs
dependencies, runs tests, and restores the task's enabled state.

### 5. Deployment computer (RPA15): add new private settings

Because updates deliberately preserve `.env`, add the new shared-log settings
once on the deployment computer:

```powershell
notepad .env
```

Add or update:

```dotenv
POSTAL_APPEND_NETWORK_LOG=true
POSTAL_NETWORK_LOG_FILE=\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs\postal-report-automation-1001234.txt
POSTAL_RETRY_DELAY_SECONDS=60
POSTAL_ERROR_LOG_DIR=\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs
```

Confirm that the task account has create/append access. An interactive
`Test-Path` proves only the currently signed-in user's access:

```powershell
Test-Path "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs"
```

### 6. Deployment computer (RPA15): reinstall and verify the task

For this retry-policy release, reinstall the existing task once. Older task
definitions may contain Task Scheduler-level restart rules, which could start
another wrapper after its own two attempts. The project now owns the single
retry, so the task definition deliberately has no additional automatic restart:

```powershell
.\install_daily_task.ps1 -Force
```

Enter the Windows password for `EPA\rpasys` when prompted. Future application
updates do not require reinstalling the task unless its account, time, path, or
task settings change again.

This version also corrects the mixed UTF-8/UTF-16 scheduled-log output that
displayed spaces between letters. New local and shared-log sections will be
normal UTF-8 text. Previously appended malformed sections are historical data
and are intentionally left unchanged.

It also captures Python's complete standard-error stream. If the automation
fails, the next local and shared log will contain the full traceback and the
original Python exit code instead of stopping after `python.exe : Traceback`.

On the first failed attempt, the wrapper now creates or appends
`yyyyMMdd-error_postal-report-automation-1001234` in the configured `RPALogs`
directory, waits 60 seconds by default, and retries the complete automation one
time. A successful retry appends `Outcome: Recovered`; a second failure appends
its own error block and leaves the task result nonzero.

Run a controlled scheduled-mode test, then inspect the local and shared logs:

```powershell
.\run_scheduled.ps1
Get-ChildItem .\logs | Sort-Object LastWriteTime -Descending | Select-Object -First 3
Get-Content "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs\postal-report-automation-1001234.txt" -Tail 40
Get-ChildItem "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs" -Filter "*-error_postal-report-automation-1001234"
Get-ScheduledTaskInfo -TaskName "Postal Report Automation"
```

`run_scheduled.ps1` performs a real headless report run. It respects
`POSTAL_COPY_TO_TALEND=false`, so the report will remain local while that flag
is disabled. A successful log publication prints `Appended scheduled-run
output to network log`.
