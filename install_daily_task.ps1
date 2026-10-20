[CmdletBinding()]
param(
    # The default implements the requested daily execution time.
    [string]$DailyAt = '07:00'
)

$ErrorActionPreference = 'Stop'
$taskName = 'Postal Report Automation - 07-00'
$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$runnerScript = Join-Path $projectDirectory 'run_scheduled.ps1'
$pythonExecutable = Join-Path $projectDirectory '.venv\Scripts\python.exe'
$privateEnvironment = Join-Path $projectDirectory '.env'

# Validate prerequisites before changing Windows Task Scheduler.
if (-not (Test-Path -LiteralPath $pythonExecutable)) {
    throw 'The virtual environment is missing. Run .\setup.ps1 first.'
}
if (-not (Test-Path -LiteralPath $privateEnvironment)) {
    throw 'The .env file is missing. Run .\setup.ps1 and configure it first.'
}

try {
    $runTime = [datetime]::ParseExact(
        $DailyAt,
        'HH:mm',
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}
catch {
    throw 'DailyAt must use 24-hour HH:mm format, for example 07:00.'
}

# PowerShell launches the logging wrapper without showing an interactive prompt.
$powerShellExecutable = Join-Path $PSHOME 'powershell.exe'
$actionArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$runnerScript`""
$action = New-ScheduledTaskAction `
    -Execute $powerShellExecutable `
    -Argument $actionArguments `
    -WorkingDirectory $projectDirectory

$trigger = New-ScheduledTaskTrigger -Daily -At $runTime

# InteractiveToken avoids saving the user's Windows password. The trade-off is
# that the task runs only while this user is logged on to Windows.
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$principal = New-ScheduledTaskPrincipal `
    -UserId $currentUser `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

$task = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description 'Downloads the daily Postal Management report at 07:00.'

# Register-ScheduledTask updates the existing task when -Force is used.
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Write-Host "Scheduled task '$taskName' is active every day at $DailyAt."

