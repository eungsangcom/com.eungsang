@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\..\.."
if not defined KURE_EMBED_PORT set "KURE_EMBED_PORT=8420"
where python >nul 2>&1
if errorlevel 1 (
  echo python not found in PATH
  exit /b 1
)
start "KureEmbed" /MIN python "%REPO_ROOT%\windows_kure_embed_server.py"
exit /b 0
