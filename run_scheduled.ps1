[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonExecutable = Join-Path $projectDirectory ".venv\Scripts\python.exe"
$mainScript = Join-Path $projectDirectory "main.py"
$environmentFile = Join-Path $projectDirectory ".env"
$networkLogWriter = Join-Path $projectDirectory "append_network_log.ps1"
$errorReportWriter = Join-Path $projectDirectory "write_error_report.ps1"
$runStarted = Get-Date
$maxAutomationAttempts = 2

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
$networkLogFile = Get-PostalSetting -Name "POSTAL_NETWORK_LOG_FILE" -DefaultValue $defaultNetworkLogFile
$defaultErrorLogDirectory = Split-Path -Parent $networkLogFile
$errorLogDirectory = Get-PostalSetting -Name "POSTAL_ERROR_LOG_DIR" -DefaultValue $defaultErrorLogDirectory
$retryDelayText = Get-PostalSetting -Name "POSTAL_RETRY_DELAY_SECONDS" -DefaultValue "60"
$retryDelaySeconds = 0
if (
    -not [int]::TryParse($retryDelayText, [ref]$retryDelaySeconds) -or
    $retryDelaySeconds -lt 0 -or
    $retryDelaySeconds -gt 3600
) {
    throw "POSTAL_RETRY_DELAY_SECONDS must be a whole number from 0 to 3600."
}

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
if (-not (Test-Path -LiteralPath $errorReportWriter -PathType Leaf)) {
    throw "Error-report helper was not found: $errorReportWriter"
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

function Invoke-PostalAutomationAttempt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExecutable,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$LocalLog
    )

    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    $pythonProcess = $null
    $standardOutput = ""
    $standardError = ""
    $exitCode = 1

    try {
        # Run Python through System.Diagnostics instead of PowerShell's native
        # stderr pipeline, which can stop after the first traceback line.
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $PythonExecutable
        $startInfo.Arguments = ('"{0}" --headless' -f $ScriptPath)
        $startInfo.WorkingDirectory = $WorkingDirectory
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = $utf8WithoutBom
        $startInfo.StandardErrorEncoding = $utf8WithoutBom
        $startInfo.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8"
        $startInfo.EnvironmentVariables["PYTHONUNBUFFERED"] = "1"

        $pythonProcess = [System.Diagnostics.Process]::new()
        $pythonProcess.StartInfo = $startInfo
        if (-not $pythonProcess.Start()) {
            throw "Python could not be started: $PythonExecutable"
        }

        # Read both streams asynchronously so a long traceback cannot fill a
        # pipe and block the process.
        $standardOutputTask = $pythonProcess.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $pythonProcess.StandardError.ReadToEndAsync()
        $pythonProcess.WaitForExit()
        $standardOutput = $standardOutputTask.Result
        $standardError = $standardErrorTask.Result
        $exitCode = $pythonProcess.ExitCode
    }
    catch {
        $standardError = $_ | Out-String
        $exitCode = 1
    }
    finally {
        if ($null -ne $pythonProcess) {
            $pythonProcess.Dispose()
        }
    }

    # Append captured strings explicitly as UTF-8. Tee-Object would use UTF-16
    # under Windows PowerShell 5.1 and reintroduce spaces between letters.
    if (-not [string]::IsNullOrEmpty($standardOutput)) {
        Write-Host $standardOutput.TrimEnd()
        [System.IO.File]::AppendAllText($LocalLog, $standardOutput, $utf8WithoutBom)
        if (-not $standardOutput.EndsWith("`n")) {
            [System.IO.File]::AppendAllText($LocalLog, [Environment]::NewLine, $utf8WithoutBom)
        }
    }
    if (-not [string]::IsNullOrEmpty($standardError)) {
        [Console]::Error.Write($standardError)
        [System.IO.File]::AppendAllText($LocalLog, $standardError, $utf8WithoutBom)
        if (-not $standardError.EndsWith("`n")) {
            [System.IO.File]::AppendAllText($LocalLog, [Environment]::NewLine, $utf8WithoutBom)
        }
    }

    return [pscustomobject]@{
        ExitCode      = $exitCode
        StandardOutput = $standardOutput
        StandardError  = $standardError
    }
}

$automationExitCode = 1
$errorReportingFailed = $false
$errorFilePath = $null

for ($attempt = 1; $attempt -le $maxAutomationAttempts; $attempt++) {
    $attemptStarted = Get-Date
    Add-Content -LiteralPath $logFile -Value @(
        "Attempt $attempt of $maxAutomationAttempts started: $($attemptStarted.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
        ""
    ) -Encoding UTF8

    $attemptResult = Invoke-PostalAutomationAttempt `
        -PythonExecutable $pythonExecutable `
        -ScriptPath $mainScript `
        -WorkingDirectory $projectDirectory `
        -LocalLog $logFile
    $automationExitCode = $attemptResult.ExitCode

    if ($automationExitCode -eq 0) {
        $successLine = "Attempt $attempt of $maxAutomationAttempts completed successfully."
        Add-Content -LiteralPath $logFile -Value $successLine -Encoding UTF8
        Write-Host $successLine

        if ($attempt -gt 1 -and $null -ne $errorFilePath) {
            try {
                $errorFilePath = & $errorReportWriter `
                    -ErrorDirectory $errorLogDirectory `
                    -RunStarted $runStarted `
                    -AttemptNumber $attempt `
                    -MaximumAttempts $maxAutomationAttempts `
                    -ExitCode 0 `
                    -Outcome "Recovered" `
                    -ErrorText "The automatic retry completed successfully." `
                    -SourceLog $logFile
            }
            catch {
                $errorReportingFailed = $true
                $reportFailure = "Could not append retry recovery to the error file: $($_.Exception.Message)"
                Add-Content -LiteralPath $logFile -Value $reportFailure -Encoding UTF8
                [Console]::Error.WriteLine($reportFailure)
            }
        }
        break
    }

    $failureLine = "Attempt $attempt of $maxAutomationAttempts failed with exit code $automationExitCode."
    Add-Content -LiteralPath $logFile -Value $failureLine -Encoding UTF8
    [Console]::Error.WriteLine($failureLine)

    $errorDetails = $attemptResult.StandardError
    if ([string]::IsNullOrWhiteSpace($errorDetails)) {
        $errorDetails = "Python exited with code $automationExitCode without stderr output."
    }

    try {
        $errorFilePath = & $errorReportWriter `
            -ErrorDirectory $errorLogDirectory `
            -RunStarted $runStarted `
            -AttemptNumber $attempt `
            -MaximumAttempts $maxAutomationAttempts `
            -ExitCode $automationExitCode `
            -Outcome "Failed" `
            -ErrorText $errorDetails `
            -SourceLog $logFile
        $errorReportLine = "Error details written to: $errorFilePath"
        Add-Content -LiteralPath $logFile -Value $errorReportLine -Encoding UTF8
        Write-Host $errorReportLine
    }
    catch {
        $errorReportingFailed = $true
        $reportFailure = "Could not create or append the error file: $($_.Exception.Message)"
        Add-Content -LiteralPath $logFile -Value $reportFailure -Encoding UTF8
        [Console]::Error.WriteLine($reportFailure)
    }

    if ($attempt -lt $maxAutomationAttempts) {
        $retryLine = "Retrying the complete automation once in $retryDelaySeconds seconds."
        Add-Content -LiteralPath $logFile -Value @($retryLine, "") -Encoding UTF8
        Write-Host $retryLine
        if ($retryDelaySeconds -gt 0) {
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
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
if ($errorReportingFailed -and $finalExitCode -eq 0) {
    $finalExitCode = 1
}

if ($appendEnabled) {
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
