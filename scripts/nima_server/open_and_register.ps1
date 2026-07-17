$ErrorActionPreference = "Continue"
Write-Host "==> firewall"
try {
    $existing = Get-NetFirewallRule -DisplayName "Eungsang NIMA Server" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "firewall rule exists"
    } else {
        New-NetFirewallRule -DisplayName "Eungsang NIMA Server" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8428 -Profile Any | Out-Null
        Write-Host "firewall-ok"
    }
} catch {
    Write-Host "New-NetFirewallRule failed: $($_.Exception.Message)"
    netsh advfirewall firewall add rule name="Eungsang NIMA Server" dir=in action=allow protocol=TCP localport=8428
}

Write-Host "==> listen"
Get-NetTCPConnection -LocalPort 8428 -State Listen -ErrorAction SilentlyContinue | Format-Table LocalAddress,LocalPort,OwningProcess -AutoSize

Write-Host "==> local health"
try {
    (Invoke-WebRequest -Uri "http://127.0.0.1:8428/health" -UseBasicParsing -TimeoutSec 5).Content
} catch {
    Write-Host "local health fail: $($_.Exception.Message)"
}

Write-Host "==> install task"
& powershell -NoProfile -ExecutionPolicy Bypass -File "G:\project\com.eungsang\scripts\nima_server\install_task.ps1"
