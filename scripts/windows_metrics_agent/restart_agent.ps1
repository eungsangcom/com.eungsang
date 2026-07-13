#Requires -Version 5.1
<#
.SYNOPSIS
  윈도우 메트릭 에이전트(:8425)를 재시작합니다. git pull 후 새 API 반영 시 사용.

.USAGE
  Set-ExecutionPolicy -Scope Process Bypass
  cd G:\project\com.eungsang\scripts\windows_metrics_agent
  .\restart_agent.ps1
#>
$ErrorActionPreference = "Stop"
$Port = if ($env:METRICS_AGENT_PORT) { [int]$env:METRICS_AGENT_PORT } else { 8425 }
$TaskName = if ($env:WINDOWS_METRICS_TASK) { $env:WINDOWS_METRICS_TASK } else { "Eungsang-WindowsMetricsAgent" }

Write-Host "==> stop listeners on port $Port"
Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }

Start-Sleep -Seconds 2

Write-Host "==> start scheduled task: $TaskName"
try {
  Start-ScheduledTask -TaskName $TaskName
} catch {
  Write-Warning "scheduled task failed; run_agent.ps1 fallback"
  & "$PSScriptRoot\run_agent.ps1"
}

Start-Sleep -Seconds 3
Invoke-WebRequest "http://127.0.0.1:$Port/health" | Select-Object -ExpandProperty Content
