<#
.SYNOPSIS
Safely updates an existing installation from a verified deployment ZIP.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
    [Parameter()]
    [string]$ProjectRoot,

    [Parameter()]
    [string]$ArchivePath,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TaskName = "Postal Report Automation",

    [Parameter()]
    [switch]$SkipTests
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $PSScriptRoot
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
    $ArchivePath = Join-Path $ProjectRoot "dist\postal-report-automation-deployment.zip"
}
$ArchivePath = [System.IO.Path]::GetFullPath($ArchivePath)
$hashFile = "$ArchivePath.sha256.txt"
$pythonExecutable = Join-Path $ProjectRoot ".venv\Scripts\python.exe"

foreach ($requiredFile in @($ArchivePath, $hashFile, $pythonExecutable)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required deployment file was not found: $requiredFile"
    }
}

$expectedHash = ((Get-Content -LiteralPath $hashFile -Raw).Trim() -split "\s+")[0]
$actualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Deployment ZIP checksum verification failed."
}
Write-Host "Deployment ZIP checksum verified." -ForegroundColor Green

$scheduledTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
$restoreEnabledTask = $false
if ($null -ne $scheduledTask) {
    if ($scheduledTask.State -eq "Running") {
        throw "Scheduled task '$TaskName' is running. Wait for it to finish."
    }
    if ($scheduledTask.State -ne "Disabled") {
        $restoreEnabledTask = $true
        if ($PSCmdlet.ShouldProcess($TaskName, "Temporarily disable scheduled task")) {
            Disable-ScheduledTask -TaskName $TaskName | Out-Null
        }
    }
}

try {
    if (-not $PSCmdlet.ShouldProcess($ProjectRoot, "Extract verified deployment ZIP")) {
        return
    }

    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ProjectRoot -Force

    Write-Host "Synchronizing Python dependencies..."
    & (Join-Path $ProjectRoot "setup.ps1")

    if (-not $SkipTests) {
        Write-Host "Running the test suite..."
        Push-Location $ProjectRoot
        try {
            & $pythonExecutable -m unittest discover -s tests -v
            if ($LASTEXITCODE -ne 0) {
                throw "Tests failed with exit code $LASTEXITCODE."
            }
        }
        finally {
            Pop-Location
        }
    }

    Write-Host "Application update completed successfully." -ForegroundColor Green
}
finally {
    if ($restoreEnabledTask) {
        if ($PSCmdlet.ShouldProcess($TaskName, "Restore enabled scheduled task")) {
            Enable-ScheduledTask -TaskName $TaskName | Out-Null
            Write-Host "Scheduled task re-enabled."
        }
    }
}

