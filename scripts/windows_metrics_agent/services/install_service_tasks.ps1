#Requires -Version 5.1
<#
.SYNOPSIS
  GPU 서비스 작업 스케줄러 등록 — 로그온 자동 기동 + 원격 기동용.

  로그온 시 자동 ON : Ollama, SigLIP, NIMA (interactive user — conda/CUDA)
  기본 OFF (수동/원격만): 임베딩

  최초 1회: .\bootstrap_gpu_config.ps1 (config.cmd 생성 후 작업 재등록)

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
    @{ Name = "Eungsang-KureEmbed"; Bat = Join-Path $ScriptDir "start_embedding.bat"; Description = "Eungsang — KURE embed server (port 8420, manual)" }
)

function Remove-StartTask {
    param([string]$Name)
    $null = schtasks /Delete /TN $Name /F 2>&1
    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $existing) { return }
    try {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        Write-Host "Removed: $Name"
    } catch {
        Write-Warning "Could not remove $Name (access denied). Re-register with -Force or run PowerShell as Administrator."
    }
}

function Register-LogonBootTask {
    param(
        [string]$Name,
        [string]$BatPath,
        [string]$Description,
        [int]$DelaySec
    )
    if (-not (Test-Path $BatPath)) {
        throw "Batch not found: $BatPath"
    }

    Remove-StartTask $Name

    $Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$BatPath`"" -WorkingDirectory $ScriptDir
    $TriggerObj = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $TriggerObj.Delay = "PT${DelaySec}S"
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    try {
        Register-ScheduledTask `
            -TaskName $Name `
            -Action $Action `
            -Trigger $TriggerObj `
            -Principal $Principal `
            -Settings $Settings `
            -Description $Description `
            -Force `
            -ErrorAction Stop | Out-Null
        Write-Host "Registered (logon): $Name (delay ${DelaySec}s, user=$env:USERNAME)"
    } catch {
        Write-Warning "Could not register $Name : $($_.Exception.Message)"
        Write-Host "  Manual start: Start-ScheduledTask -TaskName '$Name'"
    }
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

    try {
        Register-ScheduledTask `
            -TaskName $Name `
            -Action $Action `
            -Principal $Principal `
            -Settings $Settings `
            -Description $Description `
            -Force `
            -ErrorAction Stop | Out-Null
        Write-Host "Registered (manual): $Name"
    } catch {
        Write-Warning "Could not register $Name : $($_.Exception.Message)"
        Write-Host "  Manual start: Start-ScheduledTask -TaskName '$Name'"
    }
}

if ($Remove) {
    foreach ($task in $BootTasks + $ManualTasks) {
        Remove-StartTask $task.Name
    }
    exit 0
}

Write-Host "==> Logon boot ON: Ollama, SigLIP, NIMA (interactive user — conda/CUDA PATH)"
Write-Host "    Run bootstrap_gpu_config.ps1 first if config.cmd is missing."
foreach ($task in $BootTasks) {
    Register-LogonBootTask -Name $task.Name -BatPath $task.Bat -Description $task.Description -DelaySec $task.Delay
}

Write-Host ""
Write-Host "==> Default OFF (manual/remote): Embedding"
foreach ($task in $ManualTasks) {
    Register-ManualTask -Name $task.Name -BatPath $task.Bat -Description $task.Description
}

Write-Host ""
Write-Host "Boot policy applied. Repo: $RepoRoot"
Write-Host "Manual start examples:"
Write-Host "  Start-ScheduledTask -TaskName Eungsang-KureEmbed"
