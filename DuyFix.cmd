
@echo off
setlocal EnableExtensions
title DUYFIX v1.0 - DRY RUN

if /I not "%~1"=="--dry-run" (
    echo [STOP] This version supports Dry Run only.
    exit /b 2
)

echo =========================================
echo       DUYFIX - WINDOWS DIAGNOSTIC
echo =========================================
echo [MODE] DRY RUN - READ ONLY
echo.

powershell.exe -NoProfile -NonInteractive -Command ^
 "$ErrorActionPreference='Stop';" ^
 "$id='55c92734-d682-4d71-983e-d6ec3f16059f';" ^
 "$p=@(Get-CimInstance SoftwareLicensingProduct | Where-Object {$_.ApplicationID -eq $id -and $_.PartialProductKey});" ^
 "if(!$p.Count){Write-Host '[WARN] No installed Windows key found';exit 2};" ^
 "$active=@($p | Where-Object {$_.LicenseStatus -eq 1});" ^
 "foreach($x in $p){" ^
 "Write-Host ('Edition: '+$x.Name);" ^
 "Write-Host ('Key last 5: '+$x.PartialProductKey);" ^
 "$r='0x{0:X8}' -f ([uint32]$x.LicenseStatusReason);" ^
 "Write-Host ('License status: '+$x.LicenseStatus);" ^
 "Write-Host ('Reason code: '+$r);" ^
 "if($r -eq '0xC004C008'){Write-Host '[FLAG] C008 reported'}" ^
 "};" ^
 "if($active.Count){Write-Host '[OK] Windows is activated'}" ^
 "else{Write-Host '[INFO] Windows not activated - NO CHANGES'}"

set "RESULT=%errorlevel%"

if not "%RESULT%"=="0" (
    echo [WARN] License query could not finish normally.
)

echo.
echo [INFO] Official Windows license expiration check:
cscript.exe //nologo "%windir%\System32\slmgr.vbs" /xpr

echo.
echo [DONE] No changes made. No API requests.
exit /b %RESULT%
