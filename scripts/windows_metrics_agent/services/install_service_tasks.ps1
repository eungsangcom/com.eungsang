#Requires -Version 5.1
<#
.SYNOPSIS
  Ollama·KURE 임베딩 작업 스케줄러 등록 (설비 담당 원격 기동용).

.USAGE
  cd G:\project\com.eungsang\scripts\windows_metrics_agent\services
  Set-ExecutionPolicy -Scope Process Bypass
  .\install_service_tasks.ps1

  제거:
  .\install_service_tasks.ps1 -Remove
#>
param([switch]$Remove)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OllamaBat = Join-Path $ScriptDir "start_ollama.bat"
$EmbedBat = Join-Path $ScriptDir "start_embedding.bat"

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

function Register-StartTask {
    param(
        [string]$Name,
        [string]$BatPath,
        [string]$Description
    )
    if (-not (Test-Path $BatPath)) {
        throw "Batch not found: $BatPath"
    }

    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        try {
            Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop
        } catch {
            Write-Host "Task already exists: $Name (skipping re-register — no permission to replace)."
            Write-Host "  To update, run PowerShell as Administrator or the user who created the task."
            return
        }
    }

    $Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$BatPath`"" -WorkingDirectory $ScriptDir
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $Name -Action $Action -Principal $Principal -Settings $Settings -Description $Description | Out-Null
    Write-Host "Registered: $Name"
}

if ($Remove) {
    Remove-StartTask "Eungsang-Ollama"
    Remove-StartTask "Eungsang-KureEmbed"
    exit 0
}

Register-StartTask -Name "Eungsang-Ollama" -BatPath $OllamaBat -Description "Eungsang — Ollama serve (port 11434)"
Register-StartTask -Name "Eungsang-KureEmbed" -BatPath $EmbedBat -Description "Eungsang — KURE embed server (port 8420)"
Write-Host ""
Write-Host "Manual start:"
Write-Host "  Start-ScheduledTask -TaskName Eungsang-Ollama"
Write-Host "  Start-ScheduledTask -TaskName Eungsang-KureEmbed"
