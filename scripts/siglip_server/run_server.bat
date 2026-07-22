@echo off
setlocal EnableExtensions
REM SigLIP 임베딩 HTTP 서버 — 작업 스케줄러·수동 기동 공용

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
set "SERVER_PY=%SCRIPT_DIR%siglip_server.py"
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\server.log"
set "RUN_LOG=%LOG_DIR%\run.log"

if exist "%SCRIPT_DIR%config.cmd" call "%SCRIPT_DIR%config.cmd"

if not exist "%SERVER_PY%" (
    echo [ERROR] siglip_server.py not found: %SERVER_PY%
    exit /b 1
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

call "%SCRIPT_DIR%stop_server.bat"

if not defined PY (
    where python >nul 2>&1
    if errorlevel 1 (
        where py >nul 2>&1
        if errorlevel 1 (
            echo [ERROR] python not found. Set PY= in config.cmd
            exit /b 1
        )
        set "PY=py -3"
    ) else (
        set "PY=python"
    )
)

echo [%date% %time%] run_server.bat invoked PY=%PY% SIGLIP_PORT=%SIGLIP_PORT% >> "%RUN_LOG%"

"%PY%" -c "import fastapi, uvicorn, torch, transformers, PIL" >nul 2>&1
if errorlevel 1 (
    echo [%date% %time%] Installing server dependencies... >> "%RUN_LOG%"
    "%PY%" -m pip install -r "%SCRIPT_DIR%requirements.txt" >> "%RUN_LOG%" 2>&1
    if errorlevel 1 exit /b 1
)

if not defined SIGLIP_PORT set "SIGLIP_PORT=8437"
if not defined SIGLIP_MODEL_ID set "SIGLIP_MODEL_ID=google/siglip-so400m-patch14-384"

cd /d "%REPO_ROOT%"
echo [%date% %time%] Starting SigLIP server on port %SIGLIP_PORT% model=%SIGLIP_MODEL_ID% > "%LOG_FILE%"
"%PY%" -u "%SERVER_PY%" >> "%LOG_FILE%" 2>&1
set "EXIT_CODE=%ERRORLEVEL%"
echo [%date% %time%] Server exited with code %EXIT_CODE% >> "%RUN_LOG%"
exit /b %EXIT_CODE%
