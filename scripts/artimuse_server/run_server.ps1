#Requires -Version 5.1
<#
  ArtiMuse 사진 심사 HTTP 서버 (PowerShell — run_server.bat 대안)
  conda activate artimuse 후:
    .\run_server.ps1
#>
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$ServerPy = Join-Path $ScriptDir "artimuse_server.py"
$LogDir = Join-Path $ScriptDir "logs"
$LogFile = Join-Path $LogDir "server.log"
$ConfigPs1 = Join-Path $ScriptDir "config.ps1"

if (Test-Path $ConfigPs1) {
    . $ConfigPs1
}

if (-not (Test-Path $ServerPy)) {
    throw "artimuse_server.py not found: $ServerPy"
}
if (-not $env:ARTIMUSE_REPO) {
    throw @"
ARTIMUSE_REPO is not set.
Copy config.ps1.example to config.ps1 and set ARTIMUSE_REPO (GitHub ArtiMuse clone path).
Example:
  `$env:ARTIMUSE_REPO = 'C:\ai\ArtiMuse'
"@
}
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$python = if ($env:PY) { $env:PY } else { "python" }

& $python -c "import fastapi, uvicorn, torch, transformers, PIL, anyio" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing server wrapper dependencies..."
    & $python -m pip install -r (Join-Path $ScriptDir "requirements.txt")
    if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
}

if (-not $env:ARTIMUSE_PORT) { $env:ARTIMUSE_PORT = "8426" }
if (-not $env:ARTIMUSE_LOAD_8BIT) { $env:ARTIMUSE_LOAD_8BIT = "1" }

Set-Location $RepoRoot
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "[$stamp] Starting ArtiMuse on port $($env:ARTIMUSE_PORT) repo=$($env:ARTIMUSE_REPO)"
Write-Host "Starting ArtiMuse on http://0.0.0.0:$($env:ARTIMUSE_PORT) (log: $LogFile)"
Write-Host "Model load may take 30-60s..."
& $python $ServerPy 2>&1 | Tee-Object -FilePath $LogFile -Append
