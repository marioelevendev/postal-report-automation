<#
.SYNOPSIS
Appends one complete local scheduled-run log to the shared RPA log file.

.DESCRIPTION
The destination is append-only: existing text is never replaced. Network
writes are retried, and any final failure is returned to run_scheduled.ps1 so
the Windows Scheduled Task records a non-zero result.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceLog,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DestinationLog,

    [Parameter(Mandatory = $true)]
    [datetime]$RunStarted,

    [Parameter(Mandatory = $true)]
    [int]$ExitCode,

    [Parameter()]
    [ValidateRange(1, 20)]
    [int]$RetryCount = 3,

    [Parameter()]
    [ValidateRange(0, 300)]
    [int]$RetryDelaySeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SourceLog -PathType Leaf)) {
    throw "The local scheduled-run log does not exist: $SourceLog"
}

$destinationDirectory = Split-Path -Parent $DestinationLog
if ([string]::IsNullOrWhiteSpace($destinationDirectory)) {
    throw "POSTAL_NETWORK_LOG_FILE must include a destination directory."
}
$sourcePath = (Resolve-Path -LiteralPath $SourceLog).Path
$localLogText = Get-Content -LiteralPath $sourcePath -Raw
$runFinished = Get-Date
$separator = "=" * 80
$payloadLines = @(
    $separator
    "Postal Report Automation run started: $($RunStarted.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Appended: $($runFinished.ToString('yyyy-MM-dd HH:mm:ss zzz'))"
    "Machine: $env:COMPUTERNAME"
    "Windows user: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    "Local source log: $sourcePath"
    "Automation exit code: $ExitCode"
    $separator
    $localLogText.TrimEnd()
    $separator
    "End of run"
    $separator
    ""
)
$payload = ($payloadLines -join [Environment]::NewLine) + [Environment]::NewLine
$utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
$lastError = $null

for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
    try {
        if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
            throw "The network log directory is unavailable: $destinationDirectory"
        }

        # AppendAllText creates the file when it does not yet exist and never
        # truncates an existing file.
        [System.IO.File]::AppendAllText($DestinationLog, $payload, $utf8WithoutBom)
        return
    }
    catch {
        $lastError = $_
        if ($attempt -lt $RetryCount) {
            Write-Warning (
                "Network log append attempt $attempt of $RetryCount failed: " +
                "$($_.Exception.Message). Retrying in $RetryDelaySeconds seconds."
            )
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

throw (
    "Unable to append to '$DestinationLog' after $RetryCount attempts. " +
    $lastError.Exception.Message
)
