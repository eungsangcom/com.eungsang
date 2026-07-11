@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_kure_deps.ps1"
exit /b %ERRORLEVEL%
