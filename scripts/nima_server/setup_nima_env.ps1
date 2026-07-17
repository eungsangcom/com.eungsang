$ErrorActionPreference = "Continue"
$root = "G:\project\com.eungsang\scripts\nima_server"
$conda = "C:\ProgramData\anaconda3\Scripts\conda.exe"
$py = "C:\ProgramData\anaconda3\envs\nima\python.exe"

Write-Host "==> restore artimuse transformers if needed"
$artipy = "C:\ProgramData\anaconda3\envs\artimuse\python.exe"
& $artipy -c "import transformers; print(transformers.__version__)"
& $artipy -m pip install "transformers==4.37.2" "tokenizers==0.15.1" "huggingface-hub==0.36.2" "numpy==1.26.4" --quiet

Write-Host "==> ensure nima conda env"
if (-not (Test-Path $py)) {
    & $conda create -y -n nima python=3.10
}
# torch cuda — reuse same cu121 index if missing
$torchOk = $false
try {
    $out = & $py -c "import torch; print(torch.__version__, torch.cuda.is_available())" 2>&1
    Write-Host $out
    if ($LASTEXITCODE -eq 0) { $torchOk = $true }
} catch {
    $torchOk = $false
}
if (-not $torchOk) {
    Write-Host "installing torch cuda into nima env"
    & $py -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu121
    if ($LASTEXITCODE -ne 0) { throw "torch install failed" }
}
Write-Host "installing nima requirements"
& $py -m pip install -r "$root\requirements.txt"
if ($LASTEXITCODE -ne 0) { throw "requirements install failed" }

@(
    "@echo off",
    "set `"PY=$py`"",
    "set `"NIMA_DEVICE=cuda:0`"",
    "set `"NIMA_METRIC=nima`"",
    "set `"NIMA_PORT=8428`"",
    "set `"NIMA_LAZY_LOAD=1`"",
    "set `"NIMA_IDLE_UNLOAD_SEC=0`""
) | Set-Content -Path "$root\config.cmd" -Encoding ASCII

Write-Host "==> stop old listeners"
Get-NetTCPConnection -LocalPort 8428 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}

Write-Host "==> start nima"
New-Item -ItemType Directory -Force -Path "$root\logs" | Out-Null
Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$root\run_server.bat`"" -WorkingDirectory $root -WindowStyle Hidden

for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    try {
        $c = (Invoke-WebRequest -Uri "http://127.0.0.1:8428/health" -UseBasicParsing -TimeoutSec 3).Content
        Write-Host "HEALTH $c"
        Get-NetTCPConnection -LocalPort 8428 -State Listen | Format-Table LocalAddress,LocalPort,OwningProcess -AutoSize
        exit 0
    } catch {
        Write-Host "wait $i"
        if ($i -in 10,20,30) {
            if (Test-Path "$root\logs\server.log") { Get-Content "$root\logs\server.log" -Tail 30 }
        }
    }
}
Write-Host "FAILED"
if (Test-Path "$root\logs\server.log") { Get-Content "$root\logs\server.log" -Tail 60 }
exit 2
