#Requires -Version 5.1
<#
.SYNOPSIS
  SigLIP·NIMA용 config.cmd 생성 및 GPU 부팅 작업 재등록 (로그온 트리거).

.USAGE
  cd G:\project\com.eungsang\scripts\windows_metrics_agent\services
  Set-ExecutionPolicy -Scope Process Bypass
  .\bootstrap_gpu_config.ps1
  .\bootstrap_gpu_config.ps1 -Py "C:\ProgramData\anaconda3\envs\artimuse\python.exe"
#>
param(
    [string]$Py = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentDir = Join-Path $ScriptDir ".."
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..\..\..")).Path
$AgentConfig = Join-Path $AgentDir "config.cmd"

if (-not $Py -and (Test-Path $AgentConfig)) {
    $line = Get-Content $AgentConfig | Where-Object { $_ -match '^\s*set\s+"?PY=' } | Select-Object -First 1
    if ($line -match 'PY=(.+)$') {
        $Py = $Matches[1].Trim().Trim('"')
    }
}

if (-not $Py) {
    $candidates = @(
        "C:\ProgramData\anaconda3\envs\artimuse\python.exe",
        "C:\ProgramData\anaconda3\python.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $Py = $candidate
            break
        }
    }
}

if (-not $Py -or -not (Test-Path $Py)) {
    throw "Python not found. Pass -Py or create $AgentConfig with set PY=..."
}

Write-Host "Using PY=$Py"

if (-not (Test-Path $AgentConfig)) {
    @(
        "@echo off",
        "set `"PY=$Py`""
    ) | Set-Content -Path $AgentConfig -Encoding ASCII
    Write-Host "Created $AgentConfig"
}

$siglipCfg = Join-Path $RepoRoot "scripts\siglip_server\config.cmd"
@(
    "@echo off",
    "set `"PY=$Py`"",
    "set SIGLIP_PORT=8437",
    "set SIGLIP_DEVICE=cuda:0",
    "set SIGLIP_LAZY_LOAD=1",
    "set SIGLIP_DTYPE=float16",
    "set HF_HOME=G:\hf_cache"
) | Set-Content -Path $siglipCfg -Encoding ASCII
Write-Host "Wrote $siglipCfg"

$nimaCfg = Join-Path $RepoRoot "scripts\nima_server\config.cmd"
@(
    "@echo off",
    "set `"PY=$Py`"",
    "set NIMA_DEVICE=cuda:0",
    "set NIMA_METRIC=nima",
    "set NIMA_PORT=8428",
    "set NIMA_LAZY_LOAD=1",
    "set NIMA_IDLE_UNLOAD_SEC=300"
) | Set-Content -Path $nimaCfg -Encoding ASCII
Write-Host "Wrote $nimaCfg"

Write-Host ""
Write-Host "==> Re-register GPU boot tasks (logon + delay)"
try {
    & (Join-Path $ScriptDir "install_service_tasks.ps1")
} catch {
    Write-Warning "Task registration skipped (access denied). config.cmd is ready — run start_siglip.bat manually or re-run install_service_tasks.ps1 as Administrator."
}

Write-Host ""
Write-Host "Test:"
Write-Host "  Start-ScheduledTask -TaskName Eungsang-SiglipServer"
Write-Host "  Start-ScheduledTask -TaskName Eungsang-NimaServer"
