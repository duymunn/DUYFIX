@echo off
setlocal EnableExtensions DisableDelayedExpansion
title DUYFIX v1.2

set "MODE=%~1"
if not defined MODE set "MODE=--dry-run"
if /I "%MODE%"=="--dry-run" goto MODE_OK
if /I "%MODE%"=="--api-test" goto MODE_OK
if /I "%MODE%"=="--cid-test" goto MODE_OK
echo [ERROR] Usage: DuyFix.cmd --dry-run ^| --api-test ^| --cid-test
exit /b 2

:MODE_OK
set "DUYFIX_PS1=%TEMP%\DuyFix-v1.2-%RANDOM%%RANDOM%.ps1"
set "PS_URL=https://raw.githubusercontent.com/duymunn/DUYFIX/main/DuyFix.ps1?v=1.2.1"

curl.exe -fLsS --connect-timeout 10 --max-time 30 "%PS_URL%" -o "%DUYFIX_PS1%"
if errorlevel 1 goto DOWNLOAD_ERROR

findstr /B /C:"# DUYFIX-PS1: 1.2" "%DUYFIX_PS1%" >nul
if errorlevel 1 goto VERSION_ERROR

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DUYFIX_PS1%" -Mode "%MODE%"
set "RC=%ERRORLEVEL%"
del /f /q "%DUYFIX_PS1%" >nul 2>&1
exit /b %RC%

:DOWNLOAD_ERROR
echo [ERROR] Cannot download DuyFix.ps1 from GitHub.
if exist "%DUYFIX_PS1%" del /f /q "%DUYFIX_PS1%" >nul 2>&1
exit /b 11

:VERSION_ERROR
echo [ERROR] Unexpected or missing DuyFix.ps1 version. Nothing was executed.
del /f /q "%DUYFIX_PS1%" >nul 2>&1
exit /b 12
