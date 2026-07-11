@echo off
setlocal
where ollama >nul 2>&1
if errorlevel 1 (
  echo ollama not found in PATH
  exit /b 1
)
start "Ollama" /MIN ollama serve
exit /b 0
