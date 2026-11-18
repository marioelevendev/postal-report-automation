<#
.SYNOPSIS
Creates or appends the dated Postal Report Automation error report.

.DESCRIPTION
The exact daily filename is yyyyMMdd-error_postal-report-automation-1001234.
Multiple failures or a successful retry on the same day are appended so no
earlier diagnostic information is overwritten.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ErrorDirectory,

    [Parameter(Mandatory = $true)]
    [datetime]$RunStarted,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 100)]
    [int]$AttemptNumber,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 100)]
    [int]$MaximumAttempts,

    [Parameter(Mandatory = $true)]
    [int]$ExitCode,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Failed", "Recovered")]
    [string]$Outcome,

    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$ErrorText,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceLog,

    [Parameter()]
    [ValidateRange(1, 20)]
    [int]$RetryCount = 3,

    [Parameter()]
    [ValidateRange(0, 300)]
    [int]$RetryDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$fileName = $RunStarted.ToString("yyyyMMdd") + "-error_postal-report-automation-1001234"
$destinationFile = Join-Path $ErrorDirectory $fileName
$recordedAt = Get-Date
$separator = "=" * 80
$payloadLines = @(
    $separator
    "Postal Report Automation error event"
    "Run started: $($RunStarted.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Recorded: $($recordedAt.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Machine: $env:COMPUTERNAME"
    "Windows user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    "Attempt: $AttemptNumber of $MaximumAttempts"
    "Outcome: $Outcome"
    "Exit code: $ExitCode"
    "Local source log: $SourceLog"
    $separator
    $ErrorText.TrimEnd()
    $separator
    ""
)
$payload = ($payloadLines -join [Environment]::NewLine) + [Environment]::NewLine
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$lastError = $null

for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
    try {
        if (-not (Test-Path -LiteralPath $ErrorDirectory -PathType Container)) {
            throw "The error-report directory is unavailable: $ErrorDirectory"
        }

        [System.IO.File]::AppendAllText($destinationFile, $payload, $utf8WithoutBom)
        Write-Output $destinationFile
        return
    }
    catch {
        $lastError = $_
        if ($attempt -lt $RetryCount) {
            Write-Warning (
                "Error-file write attempt $attempt of $RetryCount failed: " +
                "$($_.Exception.Message). Retrying in $RetryDelaySeconds seconds."
            )
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

throw (
    "Unable to write '$destinationFile' after $RetryCount attempts. " +
    $lastError.Exception.Message
)
