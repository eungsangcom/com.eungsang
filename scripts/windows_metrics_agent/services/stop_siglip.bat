@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\..\.."
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\siglip.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo [%date% %time%] Stopping SigLIP >> "%LOG_FILE%"
call "%REPO_ROOT%\scripts\siglip_server\stop_server.bat"
exit /b 0
