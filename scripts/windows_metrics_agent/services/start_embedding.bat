@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "AGENT_DIR=%SCRIPT_DIR%.."
set "REPO_ROOT=%SCRIPT_DIR%..\..\.."
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\kure_embed.log"
set "EMBED_PY=%REPO_ROOT%\windows_kure_embed_server.py"

if exist "%AGENT_DIR%\config.cmd" (
    call "%AGENT_DIR%\config.cmd"
)

if not defined PY (
    where python >nul 2>&1
    if errorlevel 1 (
        echo [%date% %time%] python not found in PATH >> "%LOG_FILE%"
        exit /b 1
    )
    set "PY=python"
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%EMBED_PY%" (
    echo [%date% %time%] missing %EMBED_PY% >> "%LOG_FILE%"
    exit /b 1
)

cd /d "%REPO_ROOT%"
echo [%date% %time%] Starting KURE embed >> "%LOG_FILE%"

%PY% -c "import sentence_transformers, fastapi, uvicorn" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] Installing embedding dependencies... >> "%LOG_FILE%"
    %PY% -m pip install fastapi uvicorn sentence-transformers >> "%LOG_FILE%" 2>&1
    if errorlevel 1 exit /b 1
)

start "KureEmbed" /MIN cmd /c ""%PY%" "%EMBED_PY%" >> "%LOG_FILE%" 2>&1"
exit /b 0
