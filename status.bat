@echo off
rem StarCraft II ultrawide patch - status (runs: status)
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sc2-ultrawide.ps1" status %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%