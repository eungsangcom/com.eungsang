#Requires -Version 5.1
<#
.SYNOPSIS
  KURE 임베딩 서버 의존성 1회 설치 (conda GPU 환경 권장).

.USAGE
  cd G:\project\com.eungsang\scripts\windows_metrics_agent
  # (base) conda 활성화 상태에서 실행 가능
  .\services\install_kure_deps.ps1

  PowerShell에서 PY 지정:
  $env:PY = "C:\ProgramData\anaconda3\envs\artimuse\python.exe"
  .\services\install_kure_deps.ps1
#>
$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentDir = Join-Path $ScriptDir ".."
$ConfigCmd = Join-Path $AgentDir "config.cmd"

function Read-PyFromConfigCmd {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    cmd /c "`"$Path`" && set PY" | ForEach-Object {
        if ($_ -match "^PY=(.+)$") { return $matches[1].Trim() }
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
        "$env:USERPROFILE\miniconda3\envs\artimuse\python.exe",
        "$env:ProgramData\anaconda3\python.exe",
        "$env:ProgramData\Miniconda3\python.exe",
        "$env:USERPROFILE\anaconda3\python.exe",
        "$env:USERPROFILE\miniconda3\python.exe"
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
& $python -c "import sys; print(sys.executable); print(sys.version)"
& $python -m pip install --upgrade pip
& $python -m pip install fastapi "uvicorn[standard]" sentence-transformers
& $python -c "import sentence_transformers, torch; print('ok', torch.__version__, 'cuda=', torch.cuda.is_available())"

$configLine = "set `"PY=$python`""
Write-Host ""
Write-Host "Done. Save this line to config.cmd:" -ForegroundColor Green
Write-Host "  $configLine"
