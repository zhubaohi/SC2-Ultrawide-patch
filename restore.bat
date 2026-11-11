@echo off
rem StarCraft II ultrawide patch - restore (runs: revert)
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sc2-ultrawide.ps1" revert %*
set RC=%ERRORLEVEL%
echo.
pause
exit /b %RC%