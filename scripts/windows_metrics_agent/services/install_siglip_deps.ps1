#Requires -Version 5.1
<#
.SYNOPSIS
  SigLIP HTTP 서버 의존성 1회 설치 (conda GPU artimuse 환경 권장).

.USAGE
  cd G:\project\com.eungsang\scripts\windows_metrics_agent
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

$python = Read-PyFromConfigCmd $ConfigCmd
if (-not $python) { $python = Read-PyFromConfigCmd $SiglipConfig }
if (-not $python) { $python = Resolve-CondaPython }
if (-not $python -or -not (Test-Path $python)) {
    throw "Python not found. Create config.cmd with set PY=... or activate conda (base/artimuse)."
}

Write-Host "Using PY=$python"
Write-Host "==> pip install SigLIP server requirements"
& $python -m pip install -r (Join-Path $SiglipDir "requirements.txt")
Write-Host "==> verify imports (torch may take ~30s on first load)"
& $python -c "import fastapi, uvicorn, torch, PIL, transformers; print('ok', torch.__version__, 'cuda=', torch.cuda.is_available())"
Write-Host ""
Write-Host "Done. Test manually:"
Write-Host "  cd $SiglipDir"
Write-Host "  .\run_server.bat"
