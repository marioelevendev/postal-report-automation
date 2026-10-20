[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$logDirectory = Join-Path $projectDirectory 'logs'
$logFileName = (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '.log'
$logFile = Join-Path $logDirectory $logFileName

# Keep one log per scheduled run so failures can be diagnosed later.
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

try {
    & (Join-Path $projectDirectory 'run_now.ps1') -Headless *>&1 |
        Tee-Object -FilePath $logFile
    exit $LASTEXITCODE
}
catch {
    $_ | Out-String | Set-Content -LiteralPath $logFile
    throw
}

