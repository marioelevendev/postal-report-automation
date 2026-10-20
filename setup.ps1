[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# All paths are resolved from this script, so setup works from any directory.
$projectDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$virtualEnvironment = Join-Path $projectDirectory '.venv'
$pythonExecutable = Join-Path $virtualEnvironment 'Scripts\python.exe'
$exampleEnvironment = Join-Path $projectDirectory '.env.example'
$privateEnvironment = Join-Path $projectDirectory '.env'

# Create an isolated Python environment only when one does not already exist.
if (-not (Test-Path -LiteralPath $pythonExecutable)) {
    Write-Host 'Creating the Python virtual environment...'
    py -m venv $virtualEnvironment
}

# Install the exact project dependencies into the isolated environment.
Write-Host 'Installing project dependencies...'
& $pythonExecutable -m pip install --upgrade pip
& $pythonExecutable -m pip install -r (Join-Path $projectDirectory 'requirements.txt')

# Create a private configuration file without overwriting existing secrets.
if (-not (Test-Path -LiteralPath $privateEnvironment)) {
    Copy-Item -LiteralPath $exampleEnvironment -Destination $privateEnvironment
    Write-Host 'Created .env. Add POSTAL_USERNAME and POSTAL_PASSWORD before running.'
}
else {
    Write-Host '.env already exists; it was left unchanged.'
}

Write-Host 'Setup completed.'

