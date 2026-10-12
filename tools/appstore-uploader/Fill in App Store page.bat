@echo off
title Dungeon Descent uploader
echo Dungeon Descent: filling in the App Store page.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload.ps1"
echo.
echo Press any key to close this window.
pause >nul
