$ErrorActionPreference = "Continue"
try { Write-Host ("NIMA: " + (Invoke-WebRequest http://127.0.0.1:8428/health -UseBasicParsing -TimeoutSec 3).Content) } catch { Write-Host "NIMA-DOWN" }
try { Write-Host ("SIGLIP: " + (Invoke-WebRequest http://127.0.0.1:8427/health -UseBasicParsing -TimeoutSec 3).Content) } catch { Write-Host "SIGLIP-DOWN" }
Write-Host "config.cmd:"
Get-Content "G:\project\com.eungsang\scripts\nima_server\config.cmd" -ErrorAction SilentlyContinue
Write-Host "listeners:"
Get-NetTCPConnection -LocalPort 8427,8428 -State Listen -ErrorAction SilentlyContinue | Format-Table LocalPort,OwningProcess -AutoSize
Write-Host "nima log tail:"
Get-Content "G:\project\com.eungsang\scripts\nima_server\logs\server.log" -Tail 20 -ErrorAction SilentlyContinue
