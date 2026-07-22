@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
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

call "%~dp0..\config.cmd" 2>nul
if exist "%SIGLIP_DIR%\config.cmd" call "%SIGLIP_DIR%\config.cmd"

if not defined SIGLIP_PORT set "SIGLIP_PORT=8437"

REM 이미 리스닝 중이면 재기동하지 않음 (로그 잠금·중복 프로세스 방지)
powershell -NoProfile -Command ^
  "if (Get-NetTCPConnection -LocalPort %SIGLIP_PORT% -State Listen -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }"
if not errorlevel 1 (
    echo [%date% %time%] SigLIP already listening on port %SIGLIP_PORT% >> "%LOG_FILE%"
    exit /b 0
)

call "%~dp0stop_siglip.bat"

echo [%date% %time%] Starting SigLIP >> "%LOG_FILE%"
start "SigLIP" /MIN cmd /c ""%RUN_BAT%" >> "%LOG_DIR%\siglip-run.log" 2>&1"
exit /b 0
