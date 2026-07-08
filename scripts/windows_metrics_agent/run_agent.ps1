#Requires -Version 5.1
<#
  윈도우 메트릭 에이전트 실행 (PowerShell — run_agent.bat 대안)
  conda/artimuse 환경에서 권장:
    .\run_agent.ps1
#>
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..")).Path
$AgentPy = Join-Path $RepoRoot "windows_metrics_agent.py"
$LogDir = Join-Path $ScriptDir "logs"
$LogFile = Join-Path $LogDir "agent.log"

if (-not (Test-Path $AgentPy)) {
    throw "windows_metrics_agent.py not found: $AgentPy"
}
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$python = if ($env:PY) { $env:PY } else { "python" }

& $python -c "import fastapi, uvicorn, psutil" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing dependencies..."
    & $python -m pip install -r (Join-Path $ScriptDir "requirements.txt")
    if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
}

if (-not $env:METRICS_AGENT_PORT) { $env:METRICS_AGENT_PORT = "8425" }
if (-not $env:METRICS_OLLAMA_PORT) { $env:METRICS_OLLAMA_PORT = "11434" }
if (-not $env:METRICS_EMBED_PORT) { $env:METRICS_EMBED_PORT = "8420" }

Set-Location $RepoRoot
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Add-Content -Path $LogFile -Value "[$stamp] Starting metrics agent on port $($env:METRICS_AGENT_PORT)"
Write-Host "Starting metrics agent on http://0.0.0.0:$($env:METRICS_AGENT_PORT) (log: $LogFile)"
& $python $AgentPy 2>&1 | Tee-Object -FilePath $LogFile -Append
