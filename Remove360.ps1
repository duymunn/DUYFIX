# DUYFIX-REMOVE360 1.6
# Removes only detected Qihoo/360 products. No automatic reboot.
# Silent uninstall when supported; otherwise starts registered vendor uninstaller.
$ErrorActionPreference = 'Stop'

function Test-Administrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Enter-Elevated360 {
    Write-Host '[INFO] Yêu cầu quyền Administrator qua UAC.'
    $code = '$ErrorActionPreference="Stop";$u="https://raw.githubusercontent.com/duymunn/DUYFIX/main/Remove360.ps1";$s=(Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 30).Content;if(-not $s.StartsWith("# DUYFIX-REMOVE360 1.6")){throw "Sai phiên bản Remove360"};& ([scriptblock]::Create($s))'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    try {
        Start-Process -FilePath "$PSHOME\powershell.exe" -Verb RunAs -ArgumentList "-NoExit -NoProfile -EncodedCommand $encoded" -Wait
    } catch {
        Write-Host ('[ERROR] Không được cấp quyền Administrator: ' + $_.Exception.Message)
    }
}

function Get-360Programs {
    $locations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $results = @()
    foreach ($location in $locations) {
        foreach ($entry in @(Get-ItemProperty -Path $location -ErrorAction SilentlyContinue)) {
            $name = [string]$entry.DisplayName
            $publisher = [string]$entry.Publisher
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $vendor = $publisher -match '(?i)(Qihoo|Qihu|360 Security Center|360\.cn|360 Total Security|360安全中心|奇虎|北京奇虎)'
            $product = $name -match '(?i)^(360\s*(Total Security|Security|Safe|Browser|Chrome|Zip|Driver|Game|Wallpaper|Desktop|Software|Internet Protection)|360安全|360杀毒|360极速|360压缩|360驱动|360软件|360壁纸|360桌面|360游戏|奇虎360|Qihoo 360)'
            if (-not ($vendor -or $product)) { continue }
            $results += [pscustomobject]@{
                Name = $name
                Publisher = $publisher
                Uninstall = [string]$entry.UninstallString
                Quiet = [string]$entry.QuietUninstallString
                Install = [string]$entry.InstallLocation
                RegPath = [string]$entry.PSPath
                Key = [string]$entry.PSChildName
            }
        }
    }
    return @($results | Sort-Object RegPath -Unique)
}

function Get-Known360Roots {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $pf64 = [Environment]::GetFolderPath('ProgramFiles')
    $paths = @(
        (Join-Path $pf86 '360'),
        (Join-Path $pf64 '360'),
        (Join-Path $env:ProgramData '360Safe'),
        (Join-Path $env:ProgramData '360'),
        (Join-Path $env:APPDATA '360Safe'),
        (Join-Path $env:APPDATA '360se6'),
        (Join-Path $env:APPDATA '360browser'),
        (Join-Path $env:APPDATA '360GameAssistant'),
        (Join-Path $env:APPDATA '360huabao'),
        (Join-Path $env:LOCALAPPDATA '360Safe'),
        (Join-Path $env:LOCALAPPDATA '360Chrome'),
        (Join-Path $env:LOCALAPPDATA '360ChromeX')
    )
    # Also include the same precisely named vendor-owned folders in other local user profiles.
    foreach ($profile in @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { -not $_.Special -and $_.LocalPath })) {
        $home = $profile.LocalPath
        foreach ($relative in @(
            'AppData\Roaming\360Safe','AppData\Roaming\360se6','AppData\Roaming\360browser',
            'AppData\Roaming\360GameAssistant','AppData\Roaming\360huabao',
            'AppData\Local\360Safe','AppData\Local\360Chrome','AppData\Local\360ChromeX'
        )) { $paths += (Join-Path $home $relative) }
    }
    return @($paths | Where-Object { $_ -and $_.Length -gt 12 } | Select-Object -Unique)
}

function Test-IsOwned360Path([string]$Path, [string[]]$Roots) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $normalized = $Path.Trim().Trim('"')
    foreach ($root in $Roots) {
        $candidate = $root.TrimEnd('\')
        if ($normalized.Equals($candidate, [StringComparison]::OrdinalIgnoreCase) -or
            $normalized.StartsWith($candidate + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Parse-Executable([string]$Command) {
    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $match = [regex]::Match($Command, '^\s*"(?<exe>[^"]+?\.exe)"\s*(?<args>.*)$', 'IgnoreCase')
    if (-not $match.Success) {
        $match = [regex]::Match($Command, '^\s*(?<exe>[A-Za-z]:\\.+?\.exe)\s*(?<args>.*)$', 'IgnoreCase')
    }
    if (-not $match.Success) { return $null }
    return @{ Exe=$match.Groups['exe'].Value; Args=$match.Groups['args'].Value }
}

function Start-360Uninstall([object]$Item, [string[]]$Roots) {
    Write-Host ('[UNINSTALL] ' + $Item.Name)
    $command = if ($Item.Quiet) { $Item.Quiet } else { $Item.Uninstall }
    $guid = [regex]::Match(($Item.Key + ' ' + $command), '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}').Value
    if ($guid -and ($command -match '(?i)msiexec' -or $Item.Key -eq $guid)) {
        $exe = Join-Path $env:windir 'System32\msiexec.exe'
        $args = '/x ' + $guid + ' /qn /norestart REBOOT=ReallySuppress'
        Write-Host '[INFO] MSI silent uninstall, không tự khởi động lại.'
    } else {
        $parsed = Parse-Executable $command
        if ($null -eq $parsed) {
            Write-Host '[WARN] Không có lệnh gỡ tin cậy; bỏ qua để tránh xóa sai.'
            return $false
        }
        $exe = [Environment]::ExpandEnvironmentVariables([string]$parsed.Exe)
        $args = [string]$parsed.Args
        $validSource = Test-IsOwned360Path -Path $exe -Roots $Roots
        if (-not $validSource -and $Item.Install) {
            # An explicitly registered vendor install directory can also be accepted,
            # but only when located under Program Files or the current user's AppData.
            $install = [Environment]::ExpandEnvironmentVariables([string]$Item.Install)
            $baseDirs = @([Environment]::GetFolderPath('ProgramFilesX86'), [Environment]::GetFolderPath('ProgramFiles'), $env:LOCALAPPDATA, $env:APPDATA)
            $baseOk = @($baseDirs | Where-Object {
                $install.StartsWith($_.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
            }).Count -gt 0
            $validSource = $baseOk -and $exe.StartsWith($install.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
        }
        if (-not $validSource -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) {
            Write-Host '[WARN] Không tìm thấy bộ gỡ đúng thư mục của 360; không chạy lệnh không rõ nguồn.'
            return $false
        }
        if (-not $Item.Quiet) {
            if ([IO.Path]::GetFileName($exe) -match '^unins\d*\.exe$') {
                $args = ($args + ' /VERYSILENT /SUPPRESSMSGBOXES /NORESTART').Trim()
                Write-Host '[INFO] Inno Setup: thử chế độ không tương tác.'
            } else {
                Write-Host '[WARN] Bản này không khai báo silent uninstall. Trình gỡ chính thức có thể yêu cầu xác nhận trong cửa sổ riêng.'
            }
        }
    }
    try {
        $params = @{ FilePath=$exe; PassThru=$true; ErrorAction='Stop' }
        if ($args) { $params.ArgumentList = $args }
        $proc = Start-Process @params
        if (-not $proc.WaitForExit(300000)) {
            Write-Host '[WARN] Bộ gỡ chưa hoàn thành sau 5 phút; không xóa cưỡng bức.'
            return $false
        }
        if ($proc.ExitCode -eq 3010) { $script:RestartRequested = $true }
        if ($proc.ExitCode -in @(0,3010,1605)) {
            Write-Host ('[OK] Bộ gỡ kết thúc với mã ' + $proc.ExitCode)
            return $true
        }
        Write-Host ('[WARN] Bộ gỡ trả mã ' + $proc.ExitCode)
        return $false
    } catch {
        Write-Host ('[ERROR] Không chạy được bộ gỡ: ' + $_.Exception.Message)
        return $false
    }
}

function Get-ServiceBinary([string]$Command) {
    if (-not $Command) { return '' }
    $m = [regex]::Match($Command, '^\s*"(?<path>[^"]+\.(?:exe|sys))"', 'IgnoreCase')
    if (-not $m.Success) {
        $m = [regex]::Match($Command, '^\s*(?<path>[A-Za-z]:\\.+?\.(?:exe|sys))(?=\s|$)', 'IgnoreCase')
    }
    return $m.Groups['path'].Value
}

function Remove-360Leftovers([string[]]$Roots) {
    Write-Host ''
    Write-Host '[CLEAN] Quét và dọn thành phần còn sót của 360.'

    # Remove only services/drivers whose executable points into a known 360 directory.
    $services = @()
    $services += @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)
    $services += @(Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue)
    foreach ($svc in @($services | Sort-Object Name -Unique)) {
        $binary = Get-ServiceBinary -Command ([string]$svc.PathName)
        if (-not (Test-IsOwned360Path -Path $binary -Roots $Roots)) { continue }
        Write-Host ('[SERVICE] ' + $svc.Name)
        & sc.exe stop $svc.Name *> $null
        & sc.exe delete $svc.Name *> $null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ('[WARN] Không thể xóa service/driver: ' + $svc.Name)
            $script:Unresolved++
        } else { $script:Cleaned++ }
    }

    # Stop lingering executables only if their binary really resides in a 360-owned directory.
    foreach ($proc in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        if ($proc.ProcessId -eq $PID) { continue }
        if (-not (Test-IsOwned360Path -Path ([string]$proc.ExecutablePath) -Roots $Roots)) { continue }
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            Write-Host ('[PROCESS] Đã dừng ' + $proc.Name)
            $script:Cleaned++
        } catch {
            Write-Host ('[WARN] Không dừng được ' + $proc.Name)
            $script:Unresolved++
        }
    }

    # Only scheduled tasks directly executing a binary under a 360-owned directory.
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($task in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
            $owned = $false
            foreach ($action in @($task.Actions)) {
                if (Test-IsOwned360Path -Path ([string]$action.Execute) -Roots $Roots) { $owned = $true }
            }
            if (-not $owned) { continue }
            try {
                Unregister-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Confirm:$false -ErrorAction Stop
                Write-Host ('[TASK] Đã xóa ' + $task.TaskName)
                $script:Cleaned++
            } catch {
                Write-Host ('[WARN] Không xóa được task ' + $task.TaskName)
                $script:Unresolved++
            }
        }
    }

    # Remove only exact vendor-specific registry branches. Do not wipe generic Run/Services keys.
    $regPaths = @(
        'HKCU:\Software\360Safe', 'HKCU:\Software\Qihoo',
        'HKCU:\Software\360 Security Center',
        'HKLM:\SOFTWARE\360Safe', 'HKLM:\SOFTWARE\Qihoo',
        'HKLM:\SOFTWARE\360 Security Center',
        'HKLM:\SOFTWARE\WOW6432Node\360Safe',
        'HKLM:\SOFTWARE\WOW6432Node\Qihoo'
    )
    foreach ($reg in $regPaths) {
        if (-not (Test-Path -LiteralPath $reg)) { continue }
        try {
            Remove-Item -LiteralPath $reg -Recurse -Force -ErrorAction Stop
            Write-Host ('[REG] Đã xóa ' + $reg)
            $script:Cleaned++
        } catch {
            Write-Host ('[WARN] Registry còn sót: ' + $reg)
            $script:Unresolved++
        }
    }

    # Remove exact vendor folders; do not follow reparse points.
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        try {
            $item = Get-Item -LiteralPath $root -Force -ErrorAction Stop
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                Write-Host ('[WARN] Bỏ qua thư mục liên kết: ' + $root)
                $script:Unresolved++
                continue
            }
            $links = @(Get-ChildItem -LiteralPath $root -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue)
            if ($links.Count -gt 0) {
                Write-Host ('[WARN] Thư mục chứa liên kết: ' + $root)
                $script:Unresolved++
                continue
            }
            Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
            Write-Host ('[FOLDER] Đã xóa ' + $root)
            $script:Cleaned++
        } catch {
            Write-Host ('[WARN] Thư mục còn sót: ' + $root)
            $script:Unresolved++
        }
    }
}

function Invoke-360Removal {
    if (-not (Test-Administrator)) {
        Enter-Elevated360
        return
    }
    Write-Host '=========================================='
    Write-Host '       DUYFIX - REMOVE 360 v1.6'
    Write-Host '=========================================='
    Write-Host '[INFO] Gỡ toàn bộ ứng dụng Qihoo/360 và dọn dữ liệu liên quan.'
    Write-Host '[INFO] Không tự khởi động lại Windows.'
    Write-Host '[WARN] Dữ liệu hồ sơ 360 Browser (bookmark/cài đặt) có thể bị xóa.'
    Write-Host ''

    $script:RestartRequested = $false
    $script:Cleaned = 0
    $script:Unresolved = 0
    $roots = @(Get-Known360Roots)
    $programs = @(Get-360Programs)
    if ($programs.Count -eq 0) {
        Write-Host '[INFO] Không có ứng dụng 360 đăng ký trong Apps & Features. Tiếp tục kiểm tra phần còn sót.'
    } else {
        Write-Host ('[FOUND] ' + $programs.Count + ' ứng dụng 360:')
        foreach ($program in $programs) { Write-Host (' - ' + $program.Name) }
        foreach ($program in $programs) { [void](Start-360Uninstall -Item $program -Roots $roots) }
    }

    # If the registered application is still present, keep its files and services intact.
    $remaining = @(Get-360Programs)
    if ($remaining.Count -gt 0) {
        Write-Host ''
        Write-Host ('[WARN] ' + $remaining.Count + ' sản phẩm vẫn còn đăng ký trong Windows.')
        foreach ($program in $remaining) { Write-Host ('[PENDING] ' + $program.Name) }
        Write-Host '[STOP] Không xóa thủ công file/driver khi bộ gỡ chưa hoàn tất.'
        Write-Host '[INFO] Một số bản 360 yêu cầu thao tác xác nhận trong trình gỡ chính thức.'
        Write-Host '[INFO] Nếu Windows yêu cầu restart, người dùng tự khởi động lại và chạy DUYFIX lần nữa.'
        return
    }

    Remove-360Leftovers -Roots $roots

    $folderRemain = @($roots | Where-Object { Test-Path -LiteralPath $_ })
    $after = @(Get-360Programs)
    Write-Host ''
    Write-Host '=============== KẾT QUẢ ==============='
    Write-Host ('Thành phần đã dọn: ' + $script:Cleaned)
    Write-Host ('Ứng dụng 360 còn đăng ký: ' + $after.Count)
    Write-Host ('Thư mục 360 còn sót: ' + $folderRemain.Count)
    if ($script:Unresolved -gt 0 -or $folderRemain.Count -gt 0 -or $after.Count -gt 0) {
        Write-Host '[WARN] Chưa gỡ sạch tất cả; cần kiểm tra các mục còn sót nêu trên.'
    } else {
        Write-Host '[OK] Đã xử lý các mục 360 nhận diện được trong phạm vi quét.'
    }
    if ($script:RestartRequested -or $script:Unresolved -gt 0) {
        Write-Host '[RESTART] Nếu cần, hãy TỰ khởi động lại Windows rồi kiểm tra lại. DUYFIX không tự reboot.'
    } else {
        Write-Host '[INFO] DUYFIX không tự khởi động lại.'
    }
}
Invoke-360Removal
