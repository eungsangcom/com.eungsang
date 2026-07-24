@echo off
setlocal EnableExtensions
set "SCRIPT_DIR=%~dp0"
set "AGENT_DIR=%SCRIPT_DIR%.."
set "REPO_ROOT=%SCRIPT_DIR%..\..\.."
set "LOG_DIR=%SCRIPT_DIR%logs"
set "LOG_FILE=%LOG_DIR%\kure_embed.log"
set "EMBED_PY=%REPO_ROOT%\windows_kure_embed_server.py"
set "CONFIG_CMD=%AGENT_DIR%\config.cmd"

if exist "%CONFIG_CMD%" (
    call "%CONFIG_CMD%"
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

if not defined PY (
    if exist "C:\ProgramData\anaconda3\envs\artimuse\python.exe" (
        set "PY=C:\ProgramData\anaconda3\envs\artimuse\python.exe"
    ) else if exist "C:\ProgramData\anaconda3\python.exe" (
        set "PY=C:\ProgramData\anaconda3\python.exe"
    ) else if exist "%ProgramData%\Miniconda3\envs\artimuse\python.exe" (
        set "PY=%ProgramData%\Miniconda3\envs\artimuse\python.exe"
    ) else if exist "%ProgramData%\Miniconda3\python.exe" (
        set "PY=%ProgramData%\Miniconda3\python.exe"
    )
)

if not defined PY (
    echo [%date% %time%] ERROR: %CONFIG_CMD% 에 PY=conda python 경로가 필요합니다. >> "%LOG_FILE%"
    echo 예: set "PY=C:\ProgramData\anaconda3\envs\artimuse\python.exe" >> "%LOG_FILE%"
    echo 1회 설치: services\install_kure_deps.ps1 >> "%LOG_FILE%"
    exit /b 1
)

if not exist "%CONFIG_CMD%" (
    >"%CONFIG_CMD%" echo @echo off
    >>"%CONFIG_CMD%" echo set "PY=%PY%"
    echo [%date% %time%] Created %CONFIG_CMD% with PY=%PY% >> "%LOG_FILE%"
)

if not exist "%EMBED_PY%" (
    echo [%date% %time%] missing %EMBED_PY% >> "%LOG_FILE%"
    exit /b 1
)

cd /d "%REPO_ROOT%"
echo [%date% %time%] Starting KURE embed with %PY% >> "%LOG_FILE%"

"%PY%" -c "import sentence_transformers, fastapi, uvicorn; print('deps ok')" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo [%date% %time%] sentence_transformers missing — pip install >> "%LOG_FILE%"
    "%PY%" -m pip install --upgrade pip >> "%LOG_FILE%" 2>&1
    "%PY%" -m pip install fastapi "uvicorn[standard]" sentence-transformers >> "%LOG_FILE%" 2>&1
    "%PY%" -c "import sentence_transformers, fastapi, uvicorn; print('deps ok')" >> "%LOG_FILE%" 2>&1
    if errorlevel 1 (
        echo [%date% %time%] ERROR: sentence_transformers install failed. Run install_kure_deps.ps1 >> "%LOG_FILE%"
        exit /b 1
    )
)

start "KureEmbed" /MIN cmd /c ""%PY%" "%EMBED_PY%" >> "%LOG_FILE%" 2>&1"
exit /b 0
