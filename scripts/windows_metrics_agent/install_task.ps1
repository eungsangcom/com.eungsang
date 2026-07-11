#Requires -Version 5.1
<#
.SYNOPSIS
  윈도우 메트릭 에이전트를 작업 스케줄러에 등록한다 (재부팅·로그온 시 자동 기동).

.USAGE
  PowerShell (관리자 권장):
    Set-ExecutionPolicy -Scope Process Bypass
    .\install_task.ps1
    .\install_task.ps1 -Trigger Startup   # 부팅 후 90초 (관리자 필요)
    .\install_task.ps1 -Trigger Logon     # 사용자 로그온 시 (기본)

  제거:
    .\uninstall_task.ps1
#>
param(
    [ValidateSet("Logon", "Startup")]
    [string]$Trigger = "Logon",
    [int]$StartupDelaySec = 90
)

$ErrorActionPreference = "Stop"
$TaskName = "Eungsang-WindowsMetricsAgent"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunBat = Join-Path $ScriptDir "run_agent.bat"

if (-not (Test-Path $RunBat)) {
    throw "run_agent.bat not found: $RunBat"
}

$Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$RunBat`"" -WorkingDirectory $ScriptDir

if ($Trigger -eq "Startup") {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        throw "Startup trigger requires Administrator. Re-run PowerShell as admin, or use -Trigger Logon."
    }
    $TriggerObj = New-ScheduledTaskTrigger -AtStartup
    $TriggerObj.Delay = "PT${StartupDelaySec}S"
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
} else {
    $TriggerObj = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
}

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Host "Task already exists: $TaskName (skipping re-register — access denied)."
        Write-Host "  The metrics agent task is already registered. Test with:"
        Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
        Write-Host "  Invoke-WebRequest http://127.0.0.1:8425/health"
        Write-Host ""
        Write-Host "  To replace the task, run PowerShell as Administrator."
        exit 0
    }
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $TriggerObj `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Eungsang facility dashboard — Windows GPU metrics agent (port 8425)" | Out-Null

Write-Host "Registered: $TaskName"
Write-Host "  Trigger : $Trigger"
Write-Host "  Run     : $RunBat"
Write-Host "  Logs    : $(Join-Path $ScriptDir 'logs\agent.log')"
Write-Host ""
Write-Host "Test now:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Invoke-WebRequest http://127.0.0.1:8425/health"
