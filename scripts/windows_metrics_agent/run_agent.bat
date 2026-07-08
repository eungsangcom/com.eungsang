@echo off
setlocal EnableExtensions
:: Windows metrics agent — manual or Task Scheduler

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
set "AGENT_PY=%REPO_ROOT%\windows_metrics_agent.py"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\agent.log"

if exist "%SCRIPT_DIR%config.cmd" (
    call "%SCRIPT_DIR%config.cmd"
    if errorlevel 1 (
        echo [ERROR] config.cmd failed. Remove it or fix quoting — see README.md
        exit /b 1
    )
)

if not exist "%AGENT_PY%" (
    echo [ERROR] windows_metrics_agent.py not found: %AGENT_PY%
    exit /b 1
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if not defined PY (
    where python >nul 2>&1
    if errorlevel 1 (
        where py >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] python not found. Copy config.cmd.example to config.cmd and set PY=
            exit /b 1
        )
        set "PY=py -3"
    ) else (
        set "PY=python"
    )
)

%PY% -c "import fastapi, uvicorn, psutil" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Installing dependencies...
    %PY% -m pip install -r "%SCRIPT_DIR%requirements.txt"
    if errorlevel 1 exit /b 1
)

if not defined METRICS_AGENT_PORT set "METRICS_AGENT_PORT=8425"
if not defined METRICS_OLLAMA_PORT set "METRICS_OLLAMA_PORT=11434"
if not defined METRICS_EMBED_PORT set "METRICS_EMBED_PORT=8420"

cd /d "%REPO_ROOT%"
echo [%date% %time%] Starting metrics agent on port %METRICS_AGENT_PORT% >> "%LOG_FILE%"
%PY% "%AGENT_PY%" >> "%LOG_FILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
echo [%date% %time%] Agent exited with code %EXIT_CODE% >> "%LOG_FILE%"
exit /b %EXIT_CODE%
