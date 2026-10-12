@echo off
title Dungeon Descent achievements
echo Dungeon Descent: sending all achievements to App Review.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0submit-achievements.ps1"
echo.
echo Press any key to close this window.
pause >nul
