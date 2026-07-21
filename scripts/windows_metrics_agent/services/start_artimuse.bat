@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\..\.."
set "RUN_BAT=%REPO_ROOT%\scripts\artimuse_server\run_server.bat"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\artimuse.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if not exist "%RUN_BAT%" (
    echo [%date% %time%] missing %RUN_BAT% >> "%LOG_FILE%"
    exit /b 1
)

start "ArtiMuse" /MIN cmd /c ""%RUN_BAT%" >> "%LOG_FILE%" 2>&1"
exit /b 0
