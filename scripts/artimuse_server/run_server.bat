@echo off
setlocal EnableExtensions
REM ArtiMuse 사진 심사 HTTP 서버 실행 — 작업 스케줄러·수동 기동 공용

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
set "SERVER_PY=%SCRIPT_DIR%artimuse_server.py"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\server.log"

if exist "%SCRIPT_DIR%config.cmd" call "%SCRIPT_DIR%config.cmd"

if not exist "%SERVER_PY%" (
    echo [ERROR] artimuse_server.py not found: %SERVER_PY%
    exit /b 1
)

if not defined ARTIMUSE_REPO (
    echo [ERROR] ARTIMUSE_REPO not set. Copy config.cmd.example to config.cmd and set ARTIMUSE_REPO=
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

%PY% -c "import fastapi, uvicorn, torch, transformers, PIL, anyio" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Installing server dependencies...
    %PY% -m pip install -r "%SCRIPT_DIR%requirements.txt"
    if errorlevel 1 exit /b 1
    echo [%date% %time%] NOTE: also install ArtiMuse repo requirements + torch CUDA manually.
)

if not defined ARTIMUSE_PORT set "ARTIMUSE_PORT=8426"

cd /d "%REPO_ROOT%"
echo [%date% %time%] Starting ArtiMuse server on port %ARTIMUSE_PORT% (repo=%ARTIMUSE_REPO%) >> "%LOG_FILE%"
%PY% "%SERVER_PY%" >> "%LOG_FILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
echo [%date% %time%] Server exited with code %EXIT_CODE% >> "%LOG_FILE%"
exit /b %EXIT_CODE%
