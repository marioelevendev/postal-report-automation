<#
.SYNOPSIS
Installs or removes the daily Postal Report Automation scheduled task.

.DESCRIPTION
The task runs every day at 07:05 by default. It uses a password-backed Windows
logon so the automation can access the configured UNC Talend directory even
while the user is logged out.

.EXAMPLE
.\install_daily_task.ps1

.EXAMPLE
.\install_daily_task.ps1 -DailyAt 07:05 -Force

.EXAMPLE
.\install_daily_task.ps1 -Uninstall
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TaskName = "Postal Report Automation",

    [Parameter()]
    [ValidatePattern("^([01]\d|2[0-3]):[0-5]\d$")]
    [string]$DailyAt = "07:05",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RunAsUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,

    [Parameter()]
    [string]$PythonExecutable,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$Uninstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Import-Module ScheduledTasks -ErrorAction Stop

function Resolve-ProjectPython {
    param(
        [Parameter()]
        [string]$RequestedPython,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    if ($RequestedPython) {
        if (-not (Test-Path -LiteralPath $RequestedPython -PathType Leaf)) {
            throw "The requested Python executable does not exist: $RequestedPython"
        }
        return (Resolve-Path -LiteralPath $RequestedPython).Path
    }

    $virtualEnvironmentPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
    if (-not (Test-Path -LiteralPath $virtualEnvironmentPython -PathType Leaf)) {
        throw "Virtual-environment Python was not found. Run .\setup.ps1 first."
    }
    return (Resolve-Path -LiteralPath $virtualEnvironmentPython).Path
}

if ($Uninstall) {
    $installedTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $installedTask) {
        Write-Host "Scheduled task '$TaskName' is not installed."
        return
    }

    if ($PSCmdlet.ShouldProcess($TaskName, "Unregister scheduled task")) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed scheduled task '$TaskName'."
    }
    return
}

$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$runnerScript = Join-Path $projectRoot "run_scheduled.ps1"
$environmentFile = Join-Path $projectRoot ".env"

if (-not (Test-Path -LiteralPath $runnerScript -PathType Leaf)) {
    throw "run_scheduled.ps1 was not found in the project folder: $projectRoot"
}
if (-not (Test-Path -LiteralPath $environmentFile -PathType Leaf)) {
    throw "The project .env file is missing. Run .\setup.ps1 and configure it."
}

$resolvedPython = Resolve-ProjectPython -RequestedPython $PythonExecutable -ProjectRoot $projectRoot

# Discover dependency problems during installation instead of at 07:05.
& $resolvedPython -c "import dotenv, playwright"
if ($LASTEXITCODE -ne 0) {
    throw "The selected Python interpreter is missing project dependencies: $resolvedPython"
}

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($null -ne $existingTask -and -not $Force) {
    throw "Scheduled task '$TaskName' already exists. Use -Force to replace it."
}

$runTime = [datetime]::ParseExact(
    $DailyAt,
    "HH:mm",
    [System.Globalization.CultureInfo]::InvariantCulture
)

$powerShellExecutable = Join-Path $PSHOME "powershell.exe"
$actionParameters = @{
    Execute          = $powerShellExecutable
    Argument         = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $runnerScript)
    WorkingDirectory = $projectRoot
}
$action = New-ScheduledTaskAction @actionParameters -ErrorAction Stop
$trigger = New-ScheduledTaskTrigger -Daily -At $runTime -ErrorAction Stop
$settingsParameters = @{
    StartWhenAvailable         = $true
    MultipleInstances          = "IgnoreNew"
    ExecutionTimeLimit         = (New-TimeSpan -Minutes 30)
    RestartCount               = 3
    RestartInterval            = (New-TimeSpan -Minutes 5)
    AllowStartIfOnBatteries    = $true
    DontStopIfGoingOnBatteries = $true
}
$settings = New-ScheduledTaskSettingsSet @settingsParameters -ErrorAction Stop

$description = (
    "Downloads and delivers the Postal Management report every day at {0}. " +
    "Installed from {1}."
) -f $DailyAt, $projectRoot

Write-Host "Task name:       $TaskName"
Write-Host "Schedule:        Every day at $DailyAt"
Write-Host "Python:          $resolvedPython"
Write-Host "Working folder:  $projectRoot"
Write-Host "Windows account: $RunAsUser"

if (-not $PSCmdlet.ShouldProcess($TaskName, "Register daily scheduled task")) {
    return
}

# Password logon is required for UNC access while the user is logged out.
$credential = Get-Credential -UserName $RunAsUser -Message (
    "Enter the Windows password for the Postal Report scheduled task."
)
if ($null -eq $credential) {
    throw "Credential entry was cancelled; the scheduled task was not installed."
}

$registrationParameters = @{
    TaskName    = $TaskName
    Action      = $action
    Trigger     = $trigger
    Settings    = $settings
    User        = $credential.UserName
    Password    = $credential.GetNetworkCredential().Password
    RunLevel    = "Limited"
    Description = $description
    Force       = $Force.IsPresent
}

try {
    Register-ScheduledTask @registrationParameters | Out-Null
}
finally {
    $registrationParameters.Password = $null
}

$registeredTask = Get-ScheduledTask -TaskName $TaskName
$taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName

Write-Host ""
Write-Host "Scheduled task installed successfully." -ForegroundColor Green
Write-Host "State:            $($registeredTask.State)"
Write-Host "Next run:         $($taskInfo.NextRunTime.ToString('yyyy-MM-dd HH:mm'))"
Write-Host ""
Write-Host "Test it now with:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "Then inspect logs and the enabled Talend destination."

