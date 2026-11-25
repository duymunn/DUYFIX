@echo off
setlocal EnableExtensions DisableDelayedExpansion
title DUYFIX v1.3 - FILELESS POWERSHELL

set "MODE=%~1"
if not defined MODE set "MODE=--dry-run"
if /I "%MODE%"=="--dry-run" goto MODE_OK
if /I "%MODE%"=="--api-test" goto MODE_OK
if /I "%MODE%"=="--cid-test" goto MODE_OK
if /I "%MODE%"=="--self-test" goto MODE_OK
echo [ERROR] Usage: DuyFix.cmd --dry-run ^| --api-test ^| --cid-test ^| --self-test
exit /b 2

:MODE_OK
rem Pin the script to an audited GitHub commit, rather than the moving main branch.
rem The PowerShell source is loaded into memory; no .ps1 file is created.
set "DUYFIX_MODE=%MODE%"
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop'; try { $u='https://raw.githubusercontent.com/duymunn/DUYFIX/7ed77ca6f60e78eeaa0ba84ffac3d45786c1e428/DuyFix.ps1'; $s=(Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 30).Content; if (-not $s.StartsWith('# DUYFIX-PS1: 1.3')) { throw 'Wrong DUYFIX PowerShell version' }; & ([scriptblock]::Create($s)) -Mode $env:DUYFIX_MODE } catch { Write-Host ('[ERROR] '+$_.Exception.Message); exit 13 }"
exit /b %ERRORLEVEL%
