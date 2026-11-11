@echo off
rem StarCraft II ultrawide patch - install (runs: apply)
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sc2-ultrawide.ps1" apply %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%