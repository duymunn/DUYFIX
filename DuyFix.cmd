
@echo off
setlocal EnableExtensions
title DUYFIX v1.1 - DRY RUN

if /I not "%~1"=="--dry-run" (
    echo [STOP] Only Dry Run is supported.
    exit /b 2
)

echo ==========================================
echo       DUYFIX v1.1 - DIAGNOSTIC
echo ==========================================
echo [MODE] DRY RUN - READ ONLY
echo.

powershell.exe -NoProfile -NonInteractive -Command ^
 "$ErrorActionPreference='Stop';" ^
 "try {" ^
 "$app='55c92734-d682-4d71-983e-d6ec3f16059f';" ^
 "$os=Get-CimInstance Win32_OperatingSystem;" ^
 "Write-Host ('Windows: '+$os.Caption);" ^
 "$p=@(Get-CimInstance SoftwareLicensingProduct | Where-Object {$_.ApplicationID -eq $app -and $_.PartialProductKey -and -not $_.LicenseIsAddon});" ^
 "$active=@($p | Where-Object {$_.LicenseStatus -eq 1});" ^
 "if($active.Count -gt 0){Write-Host '[OK] Windows is activated'}else{Write-Host '[WARN] Windows is not activated'};" ^
 "if($p.Count -eq 0){Write-Host '[WARN] No installed Windows product key found'};" ^
 "foreach($x in $p){" ^
 "Write-Host '------------------------------------------';" ^
 "Write-Host ('Edition: '+$x.Name);" ^
 "Write-Host ('Channel: '+$x.Description);" ^
 "Write-Host ('Key last 5: '+$x.PartialProductKey);" ^
 "Write-Host ('License status: '+$x.LicenseStatus);" ^
 "$r='0x{0:X8}' -f ([uint32]$x.LicenseStatusReason);" ^
 "Write-Host ('Reason code: '+$r);" ^
 "if($x.LicenseStatus -eq 1){Write-Host '[SKIP] Already activated - no action'}" ^
 "elseif($r -eq '0xC004C008'){Write-Host '[C008] Check product key activation limit and license entitlement'}" ^
 "elseif($r -eq '0xC004F074'){Write-Host '[KMS] KMS activation service unavailable'}" ^
 "elseif($r -eq '0xC004F050'){Write-Host '[KEY] Product key may be invalid'}" ^
 "elseif($r -eq '0xC004C003'){Write-Host '[KEY] Activation server rejected the key'}" ^
 "elseif($r -eq '0xC004F212'){Write-Host '[KEY] Product key does not match Windows edition'}" ^
 "elseif($r -eq '0x803F7001'){Write-Host '[KEY] No valid digital license found'}" ^
 "else{Write-Host '[INFO] Review Windows Activation settings'};" ^
 "};" ^
 "Write-Host '------------------------------------------';" ^
 "Write-Host '[INFO] Licensing-related services:';" ^
 "foreach($n in @('sppsvc','Winmgmt','LicenseManager','wuauserv')){" ^
 "$v=Get-Service -Name $n -ErrorAction SilentlyContinue;" ^
 "if($v){Write-Host ('Service '+$n+': '+$v.Status)}else{Write-Host ('Service '+$n+': not found')}" ^
 "};" ^
 "exit 0" ^
 "} catch {Write-Host ('[ERROR] '+$_.Exception.Message);exit 3}"

set "RESULT=%errorlevel%"

if "%RESULT%"=="0" (
    echo.
    echo [INFO] Official license expiration check:
    cscript.exe //nologo "%windir%\System32\slmgr.vbs" /xpr
) else (
    echo [WARN] Diagnostic query failed.
)

echo.
echo [DONE] DRY RUN - NO SYSTEM CHANGES.
echo [DONE] No PITVN API calls.
exit /b %RESULT%
