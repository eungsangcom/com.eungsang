#Requires -Version 5.1
<#
.SYNOPSIS
  윈도우 git 자동 sync 에이전트를 작업 스케줄러에 등록한다.

.USAGE
  PowerShell:
    Set-ExecutionPolicy -Scope Process Bypass
    .\install_task.ps1
    .\install_task.ps1 -Trigger Startup
#>
param(
    [ValidateSet("Logon", "Startup")]
    [string]$Trigger = "Logon",
    [int]$StartupDelaySec = 90
)

$ErrorActionPreference = "Stop"
$TaskName = "Eungsang-WindowsGitSync"
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
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $TriggerObj `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Eungsang — auto git pull on Windows GPU server (port 8426)" | Out-Null

Write-Host "Registered: $TaskName"
Write-Host "  Trigger : $Trigger"
Write-Host "  Run     : $RunBat"
Write-Host "  Logs    : $(Join-Path $ScriptDir 'logs\sync.log')"
Write-Host ""
Write-Host "Test now:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Invoke-WebRequest http://127.0.0.1:8426/health"
Write-Host "  Invoke-WebRequest -Method POST http://127.0.0.1:8426/sync"
