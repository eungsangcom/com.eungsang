$ErrorActionPreference = "Stop"
$root = "G:\project\com.eungsang\scripts\nima_server"
if (-not (Test-Path "$root\nima_server.py")) {
    throw "nima_server.py missing at $root"
}

Set-Location $root
Write-Host "nima dir ok"

$py = "C:\ProgramData\anaconda3\envs\artimuse\python.exe"
if (-not (Test-Path $py)) { throw "missing $py" }
Write-Host "PY=$py"

@(
    "@echo off",
    "set `"PY=$py`"",
    "set `"NIMA_DEVICE=cuda:0`"",
    "set `"NIMA_METRIC=nima`"",
    "set `"NIMA_PORT=8428`"",
    "set `"NIMA_LAZY_LOAD=1`"",
    "set `"NIMA_IDLE_UNLOAD_SEC=300`""
) | Set-Content -Path "config.cmd" -Encoding ASCII

Write-Host "==> torch"
& $py -c "import torch; print(torch.__version__, torch.cuda.is_available())"

Write-Host "==> deps"
& $py -c "import fastapi, uvicorn, PIL, pyiqa; print('deps ok')"
if ($LASTEXITCODE -ne 0) {
    Write-Host "==> pip install"
    & $py -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) { throw "pip failed" }
    & $py -c "import fastapi, uvicorn, PIL, pyiqa; print('deps ok')"
    if ($LASTEXITCODE -ne 0) { throw "deps missing" }
}

$conns = Get-NetTCPConnection -LocalPort 8428 -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
    Write-Host "stopped $($c.OwningProcess)"
}

New-Item -ItemType Directory -Force -Path "logs" | Out-Null
$bat = Join-Path $root "run_server.bat"
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$bat`"" -WorkingDirectory $root -WindowStyle Hidden
Write-Host "started server"

for ($i = 1; $i -le 48; $i++) {
    Start-Sleep -Seconds 5
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:8428/health" -UseBasicParsing -TimeoutSec 3
        Write-Host "HEALTH $($resp.Content)"
        exit 0
    } catch {
        Write-Host "wait $i"
        if ($i -eq 12 -or $i -eq 24 -or $i -eq 36) {
            if (Test-Path "logs\server.log") { Get-Content "logs\server.log" -Tail 20 }
        }
    }
}

Write-Host "FAILED health"
if (Test-Path "logs\server.log") { Get-Content "logs\server.log" -Tail 50 }
exit 2
