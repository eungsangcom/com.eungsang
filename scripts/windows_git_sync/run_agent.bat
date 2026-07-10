@echo off
setlocal EnableExtensions
:: Windows git auto-sync agent - Task Scheduler / manual

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
set "AGENT_PY=%REPO_ROOT%\windows_git_sync_agent.py"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\agent.log"

if exist "%SCRIPT_DIR%config.cmd" (
    call "%SCRIPT_DIR%config.cmd"
    if errorlevel 1 (
        echo [ERROR] config.cmd failed. See README.md
        exit /b 1
    )
)

if not exist "%AGENT_PY%" (
    echo [ERROR] windows_git_sync_agent.py not found: %AGENT_PY%
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

%PY% -c "import fastapi, uvicorn" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Installing dependencies...
    %PY% -m pip install -r "%SCRIPT_DIR%requirements.txt"
    if errorlevel 1 exit /b 1
)

if not defined WINDOWS_GIT_SYNC_REPO set "WINDOWS_GIT_SYNC_REPO=%REPO_ROOT%"
if not defined WINDOWS_GIT_SYNC_BRANCH set "WINDOWS_GIT_SYNC_BRANCH=main"
if not defined WINDOWS_GIT_SYNC_POLL_SECONDS set "WINDOWS_GIT_SYNC_POLL_SECONDS=30"
if not defined WINDOWS_GIT_SYNC_PORT set "WINDOWS_GIT_SYNC_PORT=8426"
if not defined WINDOWS_GIT_SYNC_LOG_DIR set "WINDOWS_GIT_SYNC_LOG_DIR=%LOG_DIR%"

cd /d "%REPO_ROOT%"
echo [%date% %time%] Starting git sync agent on port %WINDOWS_GIT_SYNC_PORT% >> "%LOG_FILE%"
%PY% "%AGENT_PY%" >> "%LOG_FILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
echo [%date% %time%] Agent exited with code %EXIT_CODE% >> "%LOG_FILE%"
exit /b %EXIT_CODE%
