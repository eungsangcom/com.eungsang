@echo off
setlocal EnableExtensions
REM SigLIP 리스너(8427/8437) + siglip_server.py / run_server.bat 프로세스 종료

powershell -NoProfile -Command ^
  "$ports = 8427,8437; foreach ($port in $ports) { Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue } }; Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and ($_.CommandLine -match 'siglip_server\.py|run_server\.bat') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"

timeout /t 2 /nobreak >nul 2>&1
exit /b 0
