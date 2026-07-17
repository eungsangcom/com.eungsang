$ErrorActionPreference = "Stop"
Set-Location "G:\project\com.eungsang"

Write-Host "==> fetch origin/winpc"
git fetch origin winpc

Write-Host "==> checkout scripts/nima_server"
git checkout origin/winpc -- scripts/nima_server

if (-not (Test-Path "scripts\nima_server\nima_server.py")) {
    throw "nima_server.py missing after checkout"
}
Write-Host "files:"
Get-ChildItem "scripts\nima_server" | ForEach-Object { Write-Host (" - " + $_.Name) }

$py = "C:\ProgramData\anaconda3\envs\artimuse\python.exe"
if (-not (Test-Path $py)) {
    throw "artimuse python missing: $py"
}
Write-Host "PY=$py"

$cfg = "scripts\nima_server\config.cmd"
@(
    "@echo off",
    "set `"PY=$py`"",
    "set `"NIMA_DEVICE=cuda:0`"",
    "set `"NIMA_METRIC=nima`"",
    "set `"NIMA_PORT=8428`"",
    "set `"NIMA_LAZY_LOAD=1`"",
    "set `"NIMA_IDLE_UNLOAD_SEC=300`""
) | Set-Content -Path $cfg -Encoding ASCII
Write-Host "wrote $cfg"

Write-Host "==> torch check"
& $py -c "import torch; print('torch', torch.__version__, 'cuda', torch.cuda.is_available())"

Write-Host "==> deps check"
& $py -c "import fastapi, uvicorn, PIL, pyiqa; print('deps ok')"
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> pip install requirements"
    & $py -m pip install -r "scripts\nima_server\requirements.txt"
    if ($LASTEXITCODE -ne 0) { throw "pip install failed" }
    & $py -c "import fastapi, uvicorn, PIL, pyiqa; print('deps ok')"
    if ($LASTEXITCODE -ne 0) { throw "deps still missing" }
}

# Stop anything already on 8428
$conns = Get-NetTCPConnection -LocalPort 8428 -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    try {
        Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
        Write-Host "stopped pid $($c.OwningProcess) on 8428"
    } catch {}
}

$logDir = "scripts\nima_server\logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Write-Host "==> start NIMA server"
$bat = Resolve-Path "scripts\nima_server\run_server.bat"
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$bat`"" -WorkingDirectory (Split-Path $bat) -WindowStyle Hidden
Write-Host "started run_server.bat"

# Wait for health
$ok = $false
for ($i = 1; $i -le 36; $i++) {
    Start-Sleep -Seconds 5
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:8428/health" -UseBasicParsing -TimeoutSec 3
        Write-Host ("health attempt {0}: {1}" -f $i, $resp.Content)
        $ok = $true
        break
    } catch {
        Write-Host ("health attempt {0}: waiting..." -f $i)
    }
}

if (-not $ok) {
    Write-Host "WARN: health not ready yet. last log lines:"
    if (Test-Path "scripts\nima_server\logs\server.log") {
        Get-Content "scripts\nima_server\logs\server.log" -Tail 40
    }
    exit 2
}

# Firewall (may fail without admin)
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\nima_server\open_firewall_port.ps1"
} catch {
    Write-Host "firewall skip: $($_.Exception.Message)"
}

# Register scheduled task for reboot persistence
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\nima_server\install_task.ps1"
} catch {
    Write-Host "install_task skip: $($_.Exception.Message)"
}

Write-Host "==> DONE"
