[CmdletBinding()]
param(
    # Use -Headless when the browser should remain hidden.
    [switch]$Headless
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonExecutable = Join-Path $projectDirectory '.venv\Scripts\python.exe'
$mainScript = Join-Path $projectDirectory 'main.py'

# Refuse to run before setup rather than falling back to an unrelated Python.
if (-not (Test-Path -LiteralPath $pythonExecutable)) {
    throw 'The virtual environment is missing. Run .\setup.ps1 first.'
}

# Forward the optional headless flag to the Python command-line interface.
if ($Headless) {
    & $pythonExecutable $mainScript --headless
}
else {
    & $pythonExecutable $mainScript
}

exit $LASTEXITCODE

