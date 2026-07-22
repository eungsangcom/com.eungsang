#Requires -Version 5.1
<#
  윈도우 git 자동 sync 에이전트 실행
    .\run_agent.ps1
#>
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$AgentPy = Join-Path $RepoRoot "windows_git_sync_agent.py"
$LogDir = Join-Path $ScriptDir "logs"
$LogFile = Join-Path $LogDir "agent.log"

if (-not (Test-Path $AgentPy)) {
    throw "windows_git_sync_agent.py not found: $AgentPy"
}
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$python = if ($env:PY) { $env:PY } else { "python" }

& $python -c "import fastapi, uvicorn" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing dependencies..."
    & $python -m pip install -r (Join-Path $ScriptDir "requirements.txt")
    if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
}

if (-not $env:WINDOWS_GIT_SYNC_REPO) { $env:WINDOWS_GIT_SYNC_REPO = $RepoRoot }
if (-not $env:WINDOWS_GIT_SYNC_BRANCH) { $env:WINDOWS_GIT_SYNC_BRANCH = "winpc" }
if (-not $env:WINDOWS_GIT_SYNC_POLL_SECONDS) { $env:WINDOWS_GIT_SYNC_POLL_SECONDS = "30" }
if (-not $env:WINDOWS_GIT_SYNC_PORT) { $env:WINDOWS_GIT_SYNC_PORT = "8426" }
if (-not $env:WINDOWS_GIT_SYNC_LOG_DIR) { $env:WINDOWS_GIT_SYNC_LOG_DIR = $LogDir }

Set-Location $RepoRoot
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "[$stamp] Starting git sync agent on port $($env:WINDOWS_GIT_SYNC_PORT)"
Write-Host "Starting git sync agent on http://0.0.0.0:$($env:WINDOWS_GIT_SYNC_PORT) (log: $LogFile)"
& $python $AgentPy 2>&1 | Tee-Object -FilePath $LogFile -Append
