[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonExecutable = Join-Path $projectDirectory ".venv\Scripts\python.exe"
$mainScript = Join-Path $projectDirectory "main.py"
$environmentFile = Join-Path $projectDirectory ".env"
$networkLogWriter = Join-Path $projectDirectory "append_network_log.ps1"
$runStarted = Get-Date

function Get-PostalSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter()]
        [string]$DefaultValue = ""
    )

    # A process-level environment variable has the same precedence as it does
    # in python-dotenv. Otherwise, read the value from the private .env file.
    $processValue = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($processValue)) {
        return $processValue.Trim()
    }

    if (Test-Path -LiteralPath $environmentFile -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $environmentFile) {
            if ($line -match "^\s*$([regex]::Escape($Name))\s*=\s*(.*)\s*$") {
                $value = $Matches[1].Trim()
                if (
                    $value.Length -ge 2 -and
                    (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                     ($value.StartsWith("'") -and $value.EndsWith("'")))
                ) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                return $value
            }
        }
    }

    return $DefaultValue
}

function ConvertTo-PostalBoolean {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    switch ($Value.Trim().ToLowerInvariant()) {
        { $_ -in @("1", "true", "yes", "on") } { return $true }
        { $_ -in @("0", "false", "no", "off") } { return $false }
        default { throw "$Name must be true or false, but its value is '$Value'." }
    }
}

$configuredLogDirectory = Get-PostalSetting -Name "POSTAL_LOG_DIR"
if ([string]::IsNullOrWhiteSpace($configuredLogDirectory)) {
    $logDirectory = Join-Path $projectDirectory "logs"
}
elseif ([System.IO.Path]::IsPathRooted($configuredLogDirectory)) {
    $logDirectory = $configuredLogDirectory
}
else {
    $logDirectory = Join-Path $projectDirectory $configuredLogDirectory
}

$logFileName = $runStarted.ToString("yyyy-MM-dd_HH-mm-ss") + ".log"
$logFile = Join-Path $logDirectory $logFileName
$defaultNetworkLogFile = (
    "\\kronos.epa.aerioattikis.gr\EPA_Workspace\AutomationProcess\RPALogs" +
    "\postal-report-automation-1001234.txt"
)

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

if (-not (Test-Path -LiteralPath $pythonExecutable -PathType Leaf)) {
    throw "Virtual-environment Python was not found. Run .\setup.ps1 first."
}
if (-not (Test-Path -LiteralPath $mainScript -PathType Leaf)) {
    throw "main.py was not found: $mainScript"
}
if (-not (Test-Path -LiteralPath $networkLogWriter -PathType Leaf)) {
    throw "Network log helper was not found: $networkLogWriter"
}

$header = @(
    "Postal Report Automation scheduled run"
    "Started: $($runStarted.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Machine: $env:COMPUTERNAME"
    "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    "Project: $projectDirectory"
    ""
)
Set-Content -LiteralPath $logFile -Value $header -Encoding UTF8

$automationExitCode = 1
try {
    & $pythonExecutable $mainScript --headless *>&1 |
        Tee-Object -FilePath $logFile -Append
    $automationExitCode = $LASTEXITCODE
}
catch {
    $errorText = $_ | Out-String
    Add-Content -LiteralPath $logFile -Value $errorText -Encoding UTF8
    [Console]::Error.WriteLine($errorText)
}

$runFinished = Get-Date
$footer = @(
    ""
    "Finished: $($runFinished.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Automation exit code: $automationExitCode"
)
Add-Content -LiteralPath $logFile -Value $footer -Encoding UTF8

$appendEnabledText = Get-PostalSetting -Name "POSTAL_APPEND_NETWORK_LOG" -DefaultValue "false"
$appendEnabled = ConvertTo-PostalBoolean -Name "POSTAL_APPEND_NETWORK_LOG" -Value $appendEnabledText
$finalExitCode = $automationExitCode

if ($appendEnabled) {
    $networkLogFile = Get-PostalSetting -Name "POSTAL_NETWORK_LOG_FILE" -DefaultValue $defaultNetworkLogFile
    try {
        & $networkLogWriter -SourceLog $logFile -DestinationLog $networkLogFile -RunStarted $runStarted -ExitCode $automationExitCode
        $successMessage = "Appended scheduled-run output to network log: $networkLogFile"
        Add-Content -LiteralPath $logFile -Value $successMessage -Encoding UTF8
        Write-Host $successMessage
    }
    catch {
        $failureMessage = "Network log append failed. The local log remains at '$logFile'. $($_.Exception.Message)"
        Add-Content -LiteralPath $logFile -Value $failureMessage -Encoding UTF8
        [Console]::Error.WriteLine($failureMessage)
        if ($finalExitCode -eq 0) {
            $finalExitCode = 1
        }
    }
}
else {
    $disabledMessage = "Central network logging is disabled by POSTAL_APPEND_NETWORK_LOG."
    Add-Content -LiteralPath $logFile -Value $disabledMessage -Encoding UTF8
    Write-Host $disabledMessage
}

Write-Host "Local scheduled-run log: $logFile"
exit $finalExitCode
