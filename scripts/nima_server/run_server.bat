@echo off
setlocal EnableExtensions
REM NIMA 사진 심사 HTTP 서버 실행 — 작업 스케줄러·수동 기동 공용

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
set "SERVER_PY=%SCRIPT_DIR%nima_server.py"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\server.log"

if exist "%SCRIPT_DIR%config.cmd" call "%SCRIPT_DIR%config.cmd"

if not exist "%SERVER_PY%" (
    echo [ERROR] nima_server.py not found: %SERVER_PY%
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

%PY% -c "import fastapi, uvicorn, torch, PIL, pyiqa" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Installing server dependencies...
    %PY% -m pip install -r "%SCRIPT_DIR%requirements.txt"
    if errorlevel 1 exit /b 1
    echo [%date% %time%] NOTE: install torch CUDA manually if needed.
)

if not defined NIMA_PORT set "NIMA_PORT=8428"

cd /d "%REPO_ROOT%"
echo [%date% %time%] Starting NIMA server on port %NIMA_PORT% >> "%LOG_FILE%"
%PY% "%SERVER_PY%" >> "%LOG_FILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
echo [%date% %time%] Server exited with code %EXIT_CODE% >> "%LOG_FILE%"
exit /b %EXIT_CODE%
