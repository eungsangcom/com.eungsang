#Requires -Version 5.1
param(
    [string]$TaskName = "Eungsang-WindowsMetricsAgent"
)

$ErrorActionPreference = "Stop"

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) {
    Write-Host "Task not found: $TaskName"
    exit 0
}

$running = Get-ScheduledTask -TaskName $TaskName | Get-ScheduledTaskInfo
if ($running.LastTaskResult -eq 267009) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
Write-Host "Removed: $TaskName"
