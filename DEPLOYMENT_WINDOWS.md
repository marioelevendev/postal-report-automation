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

### 1. Update and verify the tracked development checkout

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

### 2. Build the new deployment package

```powershell
.\build_deployment.ps1
```

This refreshes both files in the development checkout's `dist` directory:

```text
postal-report-automation-deployment.zip
postal-report-automation-deployment.zip.sha256.txt
```

### 3. Transfer both deployment files

Copy both files into this directory on the deployment computer, replacing the
older ZIP and checksum:

```text
C:\AutomationProcess\postal-report-automation\dist
```

Do not copy the development `.env`, `.venv`, downloads, or logs.

### 4. Apply the verified update

On the deployment computer, preferably outside the 07:05 run window:

```powershell
Set-Location "C:\AutomationProcess\postal-report-automation"
.\update_from_deployment.ps1
```

The updater verifies SHA-256, prevents updates during a running scheduled task,
temporarily disables the task, preserves `.env` and `.venv`, installs
dependencies, runs tests, and restores the task's enabled state.

### 5. Add new private settings after this redeployment

Because updates deliberately preserve `.env`, add the new shared-log settings
once on the deployment computer:

```powershell
notepad .env
```

Add or update:

```dotenv
POSTAL_APPEND_NETWORK_LOG=true
POSTAL_NETWORK_LOG_FILE=\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs\postal-report-automation-1001234.txt
```

Confirm that the task account has create/append access. An interactive
`Test-Path` proves only the currently signed-in user's access:

```powershell
Test-Path "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs"
```

### 6. Verify the redeployment

The existing task does not need to be reinstalled because it already points to
the same `run_scheduled.ps1` path. Reinstall it only if its account, time,
project path, or task definition must change.

Run a controlled scheduled-mode test, then inspect the local and shared logs:

```powershell
.\run_scheduled.ps1
Get-ChildItem .\logs | Sort-Object LastWriteTime -Descending | Select-Object -First 3
Get-Content "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs\postal-report-automation-1001234.txt" -Tail 40
Get-ScheduledTaskInfo -TaskName "Postal Report Automation"
```

`run_scheduled.ps1` performs a real headless report run. It respects
`POSTAL_COPY_TO_TALEND=false`, so the report will remain local while that flag
is disabled. A successful log publication prints `Appended scheduled-run
output to network log`.
