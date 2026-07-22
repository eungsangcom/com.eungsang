@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "AGENT_DIR=%SCRIPT_DIR%.."
set "REPO_ROOT=%SCRIPT_DIR%..\..\.."
set "SIGLIP_DIR=%REPO_ROOT%\scripts\siglip_server"
set "RUN_BAT=%SIGLIP_DIR%\run_server.bat"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\siglip.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if not exist "%RUN_BAT%" (
    echo [%date% %time%] missing %RUN_BAT% >> "%LOG_FILE%"
    exit /b 1
)

if not exist "%SIGLIP_DIR%\config.cmd" (
    echo [%date% %time%] missing config.cmd — run bootstrap_gpu_config.ps1 >> "%LOG_FILE%"
    if exist "%SCRIPT_DIR%bootstrap_gpu_config.ps1" (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%bootstrap_gpu_config.ps1" >> "%LOG_FILE%" 2>&1
    )
    if not exist "%SIGLIP_DIR%\config.cmd" exit /b 1
)

echo [%date% %time%] Starting SigLIP >> "%LOG_FILE%"
REM run_server.bat 가 server.log 에 기록 — siglip.log 와 이중 append 하지 않음 (파일 잠금 방지)
start "SigLIP" /MIN cmd /c ""%RUN_BAT%""
exit /b 0
