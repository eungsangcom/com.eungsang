$ErrorActionPreference = "Continue"
Write-Host "==> restart SigLIP for CUDA"
Get-NetTCPConnection -LocalPort 8427 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
$siglip = "G:\project\com.eungsang\scripts\siglip_server"
# Prefer scheduled task if present
$task = Get-ScheduledTask -TaskName "Eungsang-SiglipServer" -ErrorAction SilentlyContinue
if ($task) {
    Start-ScheduledTask -TaskName "Eungsang-SiglipServer"
} else {
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$siglip\run_server.bat`"" -WorkingDirectory $siglip -WindowStyle Hidden
}
for ($i=1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    try {
        $c = (Invoke-WebRequest http://127.0.0.1:8427/health -UseBasicParsing -TimeoutSec 3).Content
        Write-Host "SIGLIP $c"
        break
    } catch { Write-Host "wait $i" }
}
try { Write-Host ("NIMA " + (Invoke-WebRequest http://127.0.0.1:8428/health -UseBasicParsing -TimeoutSec 3).Content) } catch { Write-Host "NIMA-DOWN" }
