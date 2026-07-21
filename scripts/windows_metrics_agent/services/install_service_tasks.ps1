#Requires -Version 5.1
<#
.SYNOPSIS
  GPU 서비스 작업 스케줄러 등록 — 부팅 정책 + 원격 기동용.

  부팅 시 자동 ON : Ollama, SigLIP, NIMA
  기본 OFF (수동/원격만): 임베딩, ArtiMuse

.USAGE
  cd G:\project\com.eungsang\scripts\windows_metrics_agent\services
  Set-ExecutionPolicy -Scope Process Bypass
  .\install_service_tasks.ps1

  제거:
  .\install_service_tasks.ps1 -Remove
#>
param(
    [switch]$Remove,
    [int]$StartupDelaySec = 90
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path

$BootTasks = @(
    @{ Name = "Eungsang-Ollama"; Bat = Join-Path $ScriptDir "start_ollama.bat"; Description = "Eungsang — Ollama serve (port 11434, boot)"; Delay = $StartupDelaySec },
    @{ Name = "Eungsang-SiglipServer"; Bat = Join-Path $ScriptDir "start_siglip.bat"; Description = "Eungsang — SigLIP server (port 8437, boot)"; Delay = ($StartupDelaySec + 30) },
    @{ Name = "Eungsang-NimaServer"; Bat = Join-Path $ScriptDir "start_nima.bat"; Description = "Eungsang — NIMA server (port 8428, boot)"; Delay = ($StartupDelaySec + 60) }
)

$ManualTasks = @(
    @{ Name = "Eungsang-KureEmbed"; Bat = Join-Path $ScriptDir "start_embedding.bat"; Description = "Eungsang — KURE embed server (port 8420, manual)" },
    @{ Name = "Eungsang-ArtiMuseServer"; Bat = Join-Path $ScriptDir "start_artimuse.bat"; Description = "Eungsang — ArtiMuse server (port 8426, manual)" }
)

function Remove-StartTask {
    param([string]$Name)
    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $existing) { return }
    try {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        Write-Host "Removed: $Name"
    } catch {
        Write-Warning "Could not remove $Name (access denied). Run as Administrator or the task owner."
    }
}

function Register-BootTask {
    param(
        [string]$Name,
        [string]$BatPath,
        [string]$Description,
        [int]$DelaySec
    )
    if (-not (Test-Path $BatPath)) {
        throw "Batch not found: $BatPath"
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        throw "Boot tasks require Administrator. Re-run PowerShell as admin."
    }

    Remove-StartTask $Name

    $Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$BatPath`"" -WorkingDirectory $ScriptDir
    $TriggerObj = New-ScheduledTaskTrigger -AtStartup
    $TriggerObj.Delay = "PT${DelaySec}S"
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $TriggerObj -Principal $Principal -Settings $Settings -Description $Description | Out-Null
    Write-Host "Registered (boot): $Name (delay ${DelaySec}s)"
}

function Register-ManualTask {
    param(
        [string]$Name,
        [string]$BatPath,
        [string]$Description
    )
    if (-not (Test-Path $BatPath)) {
        throw "Batch not found: $BatPath"
    }

    Remove-StartTask $Name

    $Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$BatPath`"" -WorkingDirectory $ScriptDir
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $Name -Action $Action -Principal $Principal -Settings $Settings -Description $Description | Out-Null
    Write-Host "Registered (manual): $Name"
}

if ($Remove) {
    foreach ($task in $BootTasks + $ManualTasks) {
        Remove-StartTask $task.Name
    }
    exit 0
}

Write-Host "==> Boot ON: Ollama, SigLIP, NIMA"
foreach ($task in $BootTasks) {
    Register-BootTask -Name $task.Name -BatPath $task.Bat -Description $task.Description -DelaySec $task.Delay
}

Write-Host ""
Write-Host "==> Default OFF (manual/remote): Embedding, ArtiMuse"
foreach ($task in $ManualTasks) {
    Register-ManualTask -Name $task.Name -BatPath $task.Bat -Description $task.Description
}

Write-Host ""
Write-Host "Boot policy applied. Repo: $RepoRoot"
Write-Host "Manual start examples:"
Write-Host "  Start-ScheduledTask -TaskName Eungsang-KureEmbed"
Write-Host "  Start-ScheduledTask -TaskName Eungsang-ArtiMuseServer"
