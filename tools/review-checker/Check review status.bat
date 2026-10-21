@echo off
title App Review checker
echo App Review checker: the real status of your app, straight from Apple.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-review.ps1"
echo.
echo Press any key to close this window.
pause >nul
