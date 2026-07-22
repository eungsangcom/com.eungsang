@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\..\.."
set "NIMA_DIR=%REPO_ROOT%\scripts\nima_server"
set "RUN_BAT=%NIMA_DIR%\run_server.bat"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\nima.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if not exist "%RUN_BAT%" (
    echo [%date% %time%] missing %RUN_BAT% >> "%LOG_FILE%"
    exit /b 1
)

if not exist "%NIMA_DIR%\config.cmd" (
    echo [%date% %time%] missing %NIMA_DIR%\config.cmd — run bootstrap_gpu_config.ps1 >> "%LOG_FILE%"
    exit /b 1
)

echo [%date% %time%] Starting NIMA >> "%LOG_FILE%"
start "NIMA" /MIN cmd /c ""%RUN_BAT%" >> "%LOG_FILE%" 2>&1"
exit /b 0
