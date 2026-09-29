@echo off
setlocal enabledelayedexpansion

REM Always work from the repo root (one level up from this file), so it
REM doesn't matter whether you double-clicked this from inside functions\
REM or ran it from somewhere else.
cd /d "%~dp0.."

echo ============================================
echo  Dungeon Descent - Hunting Grounds Narrator
echo  Firebase Functions Setup and Deploy
echo ============================================
echo.

REM --- Check Node.js is installed ---
where node >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Node.js is not installed or not on PATH.
    echo Download and install it from https://nodejs.org first, then run this again.
    pause
    exit /b 1
)

REM --- Check/install firebase-tools ---
where firebase >nul 2>nul
if errorlevel 1 (
    echo Firebase CLI not found. Installing it globally...
    call npm install -g firebase-tools
    if errorlevel 1 (
        echo [ERROR] Failed to install firebase-tools. Try running this file as Administrator.
        pause
        exit /b 1
    )
) else (
    echo Firebase CLI found.
)

echo.
echo Logging into Firebase - a browser window will open...
call firebase login
if errorlevel 1 (
    echo [ERROR] Firebase login failed.
    pause
    exit /b 1
)

REM --- Install function dependencies ---
echo.
echo Installing function dependencies...
call npm install --prefix functions
if errorlevel 1 (
    echo [ERROR] npm install failed inside the functions folder.
    pause
    exit /b 1
)

REM --- AWS secrets ---
echo.
set /p SETKEYS="Set/update your AWS Polly keys now? (y/n): "
if /i "%SETKEYS%"=="y" (
    echo.
    echo You'll be asked to paste each value below - Firebase hides the input,
    echo and it goes straight to Google Secret Manager. Nothing is saved to this
    echo file or shown anywhere else.
    echo.
    echo --- AWS Access Key ID ---
    call firebase functions:secrets:set AWS_ACCESS_KEY_ID
    if errorlevel 1 (
        echo [ERROR] Failed to set AWS_ACCESS_KEY_ID.
        pause
        exit /b 1
    )
    echo.
    echo --- AWS Secret Access Key ---
    call firebase functions:secrets:set AWS_SECRET_ACCESS_KEY
    if errorlevel 1 (
        echo [ERROR] Failed to set AWS_SECRET_ACCESS_KEY.
        pause
        exit /b 1
    )
) else (
    echo Skipping - assuming the secrets are already set from a previous run.
)

REM --- Deploy ---
echo.
echo Deploying the narrateHuntLine function...
call firebase deploy --only functions
if errorlevel 1 (
    echo [ERROR] Deploy failed - scroll up for the reason.
    pause
    exit /b 1
)

echo.
echo ============================================
echo  Done. The narrator is now live on Polly.
echo ============================================
pause
