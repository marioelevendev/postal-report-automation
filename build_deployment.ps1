<#
.SYNOPSIS
Builds a credential-free Postal Report deployment ZIP and SHA-256 file.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot "dist\postal-report-automation-deployment.zip"
}
if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath

# The allow-list prevents .env, Git data, virtual environments, reports, and
# logs from entering the deployment package.
$rootFiles = @(
    ".env.example",
    ".gitignore",
    "append_network_log.ps1",
    "build_deployment.ps1",
    "dates.py",
    "DEPLOYMENT_WINDOWS.md",
    "file_delivery.py",
    "install_daily_task.ps1",
    "main.py",
    "README.md",
    "requirements.txt",
    "run_now.ps1",
    "run_scheduled.ps1",
    "setup.ps1",
    "update_from_deployment.ps1"
)
$sourceDirectories = @("tests")

foreach ($relativePath in $rootFiles + $sourceDirectories) {
    $requiredPath = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required deployment source is missing: $requiredPath"
    }
}

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$stagingDirectory = Join-Path $outputDirectory (".staging-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

try {
    foreach ($relativePath in $rootFiles) {
        Copy-Item -LiteralPath (Join-Path $projectRoot $relativePath) -Destination (
            Join-Path $stagingDirectory $relativePath
        )
    }

    foreach ($relativeDirectory in $sourceDirectories) {
        $sourceDirectory = Join-Path $projectRoot $relativeDirectory
        Get-ChildItem -LiteralPath $sourceDirectory -File -Recurse | Where-Object {
            $_.FullName -notmatch "[\\/]__pycache__[\\/]" -and
            $_.Extension -notin @(".pyc", ".pyo")
        } | ForEach-Object {
            $relativeFile = $_.FullName.Substring($projectRoot.Length).TrimStart("\", "/")
            $targetFile = Join-Path $stagingDirectory $relativeFile
            New-Item -ItemType Directory -Path (Split-Path -Parent $targetFile) -Force |
                Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $targetFile
        }
    }

    foreach ($runtimeDirectory in @("downloads", "logs")) {
        $stagedRuntimeDirectory = Join-Path $stagingDirectory $runtimeDirectory
        New-Item -ItemType Directory -Path $stagedRuntimeDirectory -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $stagedRuntimeDirectory ".gitkeep") |
            Out-Null
    }

    if (Test-Path -LiteralPath $resolvedOutputPath) {
        Remove-Item -LiteralPath $resolvedOutputPath -Force
    }
    Compress-Archive -Path (Join-Path $stagingDirectory "*") -DestinationPath (
        $resolvedOutputPath
    ) -CompressionLevel Optimal

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($resolvedOutputPath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName.Replace("\", "/") })
    }
    finally {
        $archive.Dispose()
    }

    $forbiddenEntries = @($entryNames | Where-Object {
        $_ -eq ".env" -or
        $_ -like ".git/*" -or
        $_ -like ".venv/*" -or
        $_ -like ".idea/*" -or
        $_ -like "dist/*" -or
        $_ -like "*/__pycache__/*" -or
        ($_.StartsWith("downloads/") -and $_ -ne "downloads/.gitkeep") -or
        ($_.StartsWith("logs/") -and $_ -ne "logs/.gitkeep")
    })
    if ($forbiddenEntries.Count -gt 0) {
        Remove-Item -LiteralPath $resolvedOutputPath -Force
        throw "Deployment safety check failed: $($forbiddenEntries -join ', ')"
    }

    $fileHash = Get-FileHash -LiteralPath $resolvedOutputPath -Algorithm SHA256
    $hashFile = "$resolvedOutputPath.sha256.txt"
    Set-Content -LiteralPath $hashFile -Value (
        "{0}  {1}" -f $fileHash.Hash, (Split-Path -Leaf $resolvedOutputPath)
    ) -Encoding ASCII

    Write-Host "Deployment package created successfully." -ForegroundColor Green
    Write-Host "ZIP:     $resolvedOutputPath"
    Write-Host "SHA256:  $($fileHash.Hash)"
    Write-Host "Entries: $($entryNames.Count)"
}
finally {
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
}
