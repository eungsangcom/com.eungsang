$ErrorActionPreference = "Continue"
$root = "G:\project\com.eungsang\scripts\nima_server"
$log = Join-Path $root "logs\server.log"

Write-Host "==> last log"
if (Test-Path $log) {
    Get-Content $log -Tail 80
} else {
    Write-Host "no log yet"
}

Write-Host "==> kill old 8428"
Get-NetTCPConnection -LocalPort 8428 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}

Write-Host "==> start task"
Start-ScheduledTask -TaskName "Eungsang-NimaServer" -ErrorAction SilentlyContinue
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$root\run_server.bat`"" -WorkingDirectory $root -WindowStyle Hidden

for ($i = 1; $i -le 24; $i++) {
    Start-Sleep -Seconds 3
    try {
        $c = (Invoke-WebRequest -Uri "http://127.0.0.1:8428/health" -UseBasicParsing -TimeoutSec 3).Content
        Write-Host "HEALTH $c"
        Get-NetTCPConnection -LocalPort 8428 -State Listen | Format-Table LocalAddress,LocalPort,OwningProcess -AutoSize
        exit 0
    } catch {
        Write-Host "wait $i"
    }
}

Write-Host "==> still down, log tail"
if (Test-Path $log) { Get-Content $log -Tail 80 }
exit 2
