$ErrorActionPreference = "Continue"
Write-Host "==> restart SigLIP with nima proxy"
# Find process listening on 8427 and kill, then start via existing start script if any
$conns = Get-NetTCPConnection -LocalPort 8427 -State Listen -ErrorAction SilentlyContinue
foreach ($c in $conns) {
    Write-Host "stop pid $($c.OwningProcess)"
    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$siglip = "G:\project\com.eungsang\scripts\siglip_server"
$bat = Join-Path $siglip "run_server.bat"
if (-not (Test-Path $bat)) { $bat = Join-Path $siglip "start_server.bat" }
if (-not (Test-Path $bat)) { $bat = Join-Path $siglip "start_gpu.bat" }
Write-Host "using $bat"
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$bat`"" -WorkingDirectory $siglip -WindowStyle Hidden

for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    try {
        $h = (Invoke-WebRequest -Uri "http://127.0.0.1:8427/health" -UseBasicParsing -TimeoutSec 3).Content
        Write-Host "SIGLIP $h"
        break
    } catch {
        Write-Host "siglip wait $i"
    }
}

Write-Host "==> nima local"
try { (Invoke-WebRequest -Uri "http://127.0.0.1:8428/health" -UseBasicParsing -TimeoutSec 3).Content } catch { Write-Host "nima down: $($_.Exception.Message)" }

Write-Host "==> proxy dry-run path exists only after restart"
