#Requires -Version 5.1
<#
.SYNOPSIS
  윈도우 GPU 서버 — Ollama·KURE 임베딩 작업 스케줄러 등록 (수동/원격 기동용).

.USAGE
  .\install_tasks.ps1
  .\install_tasks.ps1 -Remove
#>
param([switch]$Remove)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OllamaBat = Join-Path $ScriptDir "start_ollama.bat"
$EmbedBat = Join-Path $ScriptDir "start_embedding.bat"

function Register-StartTask {
    param(
        [string]$Name,
        [string]$BatPath,
        [string]$Description
    )
    if (-not (Test-Path $BatPath)) {
        throw "Batch not found: $BatPath"
    }
    $Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$BatPath`"" -WorkingDirectory $ScriptDir
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
    }
    Register-ScheduledTask -TaskName $Name -Action $Action -Principal $Principal -Settings $Settings -Description $Description | Out-Null
    Write-Host "Registered: $Name"
}

function Remove-StartTask {
    param([string]$Name)
    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false
        Write-Host "Removed: $Name"
    }
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
