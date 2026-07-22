$ErrorActionPreference = "Continue"
$siglip = "G:\project\com.eungsang\scripts\siglip_server"
$TaskName = "Eungsang-SiglipServer"

Write-Host "==> config.cmd"
if (Test-Path "$siglip\config.cmd") {
    Get-Content "$siglip\config.cmd"
} else {
    Write-Host "missing config.cmd — writing"
}

# Ensure CUDA device + working PY (prefer artimuse env which had CUDA torch)
$pyCandidates = @(
    "C:\ProgramData\anaconda3\envs\artimuse\python.exe",
    "C:\ProgramData\anaconda3\envs\pytorch_env\python.exe",
    "C:\ProgramData\anaconda3\python.exe"
)
$py = $null
foreach ($c in $pyCandidates) {
    if (Test-Path $c) {
        $check = & $c -c "import torch; print(torch.cuda.is_available())" 2>$null
        Write-Host "check $c -> $check"
        if ("$check" -match "True") { $py = $c; break }
    }
}
if (-not $py) { $py = $pyCandidates[0] }
Write-Host "PY=$py"

@(
    "@echo off",
    "set `"PY=$py`"",
    "set `"SIGLIP_PORT=8427`"",
    "set `"SIGLIP_MODEL_ID=google/siglip-so400m-patch14-384`"",
    "set `"SIGLIP_DEVICE=cuda:0`"",
    "set `"SIGLIP_LAZY_LOAD=1`"",
    "set `"SIGLIP_DTYPE=float16`"",
    "set `"HF_HOME=G:\hf_cache`""
) | Set-Content -Path "$siglip\config.cmd" -Encoding ASCII

Write-Host "==> stop 8427"
Get-NetTCPConnection -LocalPort 8427 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "kill $($_.OwningProcess)"
    Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# Register/update scheduled task (same pattern as NIMA) so it survives SSH
$RunBat = Join-Path $siglip "run_server.bat"
$Action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$RunBat`"" -WorkingDirectory $siglip
$TriggerObj = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit ([TimeSpan]::Zero)
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $TriggerObj `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Eungsang SigLIP embedding/scoring server (port 8427, CUDA)" | Out-Null
Write-Host "Registered $TaskName"

Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName $TaskName

for ($i = 1; $i -le 40; $i++) {
    Start-Sleep -Seconds 3
    try {
        $c = (Invoke-WebRequest -Uri "http://127.0.0.1:8427/health" -UseBasicParsing -TimeoutSec 5).Content
        Write-Host "HEALTH $c"
        if ($c -match '"device"\s*:\s*"cuda') {
            Write-Host "OK cuda"
            exit 0
        }
        if ($c -match '"device"\s*:\s*"cpu"') {
            Write-Host "WARN still cpu — check log"
            Get-Content "$siglip\logs\server.log" -Tail 40
            exit 3
        }
        exit 0
    } catch {
        Write-Host "wait $i"
        if ($i -in 10, 20, 30) {
            Get-Content "$siglip\logs\server.log" -Tail 30 -ErrorAction SilentlyContinue
        }
    }
}
Write-Host "FAILED"
Get-Content "$siglip\logs\server.log" -Tail 50 -ErrorAction SilentlyContinue
exit 2
