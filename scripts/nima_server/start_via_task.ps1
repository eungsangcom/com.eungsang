$ErrorActionPreference = "Continue"
$TaskName = "Eungsang-NimaServer"

Write-Host "==> ensure scheduled task"
& powershell -NoProfile -ExecutionPolicy Bypass -File "G:\project\com.eungsang\scripts\nima_server\install_task.ps1"

Write-Host "==> stop any stray 8428"
Get-NetTCPConnection -LocalPort 8428 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}

Write-Host "==> run scheduled task (survives SSH disconnect)"
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName $TaskName

for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 2
    try {
        $c = (Invoke-WebRequest -Uri "http://127.0.0.1:8428/health" -UseBasicParsing -TimeoutSec 3).Content
        Write-Host "HEALTH $c"
        Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo | Format-List LastTaskResult,LastRunTime
        exit 0
    } catch {
        Write-Host "wait $i"
    }
}

Write-Host "FAILED"
Get-Content "G:\project\com.eungsang\scripts\nima_server\logs\server.log" -Tail 40
Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo | Format-List *
exit 2
