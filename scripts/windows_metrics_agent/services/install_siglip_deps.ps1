#Requires -Version 5.1
<#
.SYNOPSIS
  SigLIP HTTP 서버 의존성 1회 설치 (conda GPU artimuse 환경 권장).

.USAGE
  cd G:\project\com.eungsang\scripts\windows_metrics_agent
  .\services\install_siglip_deps.ps1

  PowerShell에서 PY 지정:
  $env:PY = "C:\ProgramData\anaconda3\envs\artimuse\python.exe"
  .\services\install_siglip_deps.ps1
#>
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentDir = Join-Path $ScriptDir ".."
$SiglipDir = Join-Path (Split-Path $AgentDir -Parent) "siglip_server"
$ConfigCmd = Join-Path $AgentDir "config.cmd"
$SiglipConfig = Join-Path $SiglipDir "config.cmd"

function Read-PyFromConfigCmd {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    foreach ($line in (cmd /c "`"$Path`" && set PY")) {
        if ($line -match "^PY=(.+)$") { return $matches[1].Trim().Trim('"') }
    }
    return $null
}

function Resolve-CondaPython {
    $conda = Get-Command conda -ErrorAction SilentlyContinue
    if ($conda) {
        $base = & conda info --base 2>$null
        if ($base -and (Test-Path $base)) {
            $artimuse = Join-Path $base "envs\artimuse\python.exe"
            if (Test-Path $artimuse) { return $artimuse }
            $rootPy = Join-Path $base "python.exe"
            if (Test-Path $rootPy) { return $rootPy }
        }
    }
    return $null
}

$python = $null
if ($env:PY -and (Test-Path $env:PY)) {
    $python = $env:PY
}
if (-not $python) {
    $python = Read-PyFromConfigCmd -Path $ConfigCmd
}
if (-not $python) {
    $python = Read-PyFromConfigCmd -Path $SiglipConfig
}
if (-not $python) {
    $active = Get-Command python -ErrorAction SilentlyContinue
    if ($active -and $active.Source -notmatch "WindowsApps|pythoncore") {
        $python = $active.Source
    }
}
if (-not $python) {
    $python = Resolve-CondaPython
}
if (-not $python) {
    $candidates = @(
        "$env:ProgramData\anaconda3\envs\artimuse\python.exe",
        "$env:ProgramData\Miniconda3\envs\artimuse\python.exe",
        "$env:USERPROFILE\anaconda3\envs\artimuse\python.exe",
        "$env:ProgramData\anaconda3\python.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $python = $candidate
            break
        }
    }
}

if (-not $python) {
    Write-Host "Python not found. Run these and share output:" -ForegroundColor Yellow
    Write-Host "  conda info --base"
    Write-Host "  Get-Command python"
    throw "Set PY in config.cmd or `$env:PY before running."
}

if ($python -match "WindowsApps|pythoncore") {
    throw "Refusing Microsoft Store Python: $python`nUse conda: conda activate base"
}

Write-Host "Using: $python" -ForegroundColor Green
Write-Host "==> pip install SigLIP server requirements"
& $python -m pip install -r (Join-Path $SiglipDir "requirements.txt")
Write-Host "==> verify imports (torch may take ~30s on first load)"
& $python -c "import fastapi, uvicorn, torch, PIL, transformers; print('ok', torch.__version__, 'cuda=', torch.cuda.is_available())"
Write-Host ""
Write-Host "Done. Test manually:"
Write-Host "  cd $SiglipDir"
Write-Host "  .\run_server.bat"
