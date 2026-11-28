# DUYFIX-PS1: 1.7
# Windows activation diagnostic and voluntary PITVN API connectivity/CID test.
# All modes are non-mutating: no /ipk, /upk, /cpky, /ato, /atp or service changes.
param(
    [ValidateSet('--menu','--dry-run','--api-test','--cid-test','--self-test')]
    [string]$Mode = '--menu'
)

$ErrorActionPreference = 'Stop'
$WindowsApplicationId = '55c92734-d682-4d71-983e-d6ec3f16059f'
$CidApi = 'https://tritran.pitvncommunity.com/api/cid'

function Show-ErrorCode([object]$Value) {
    if ($null -eq $Value) { return 'N/A' }
    return ('0x{0:X8}' -f ([uint32]$Value))
}

function Get-WindowsProducts {
    $all = @(Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop)
    return @($all | Where-Object {
        $_.ApplicationID -eq $WindowsApplicationId -and
        $_.PartialProductKey -and
        -not $_.LicenseIsAddon -and
        $_.Name -like 'Windows*'
    })
}

function Show-Diagnostics([object[]]$Products) {
    if ($Products.Count -eq 0) {
        Write-Host '[WARN] No Windows product key found.'
        return
    }

    # When a Windows license is already active, do not display unrelated
    # non-activated product records as if they were current errors.
    $active = @($Products | Where-Object { $_.LicenseStatus -eq 1 })
    $display = if ($active.Count -gt 0) { @($active[0]) } else { $Products }

    foreach ($p in $display) {
        $channel = if ($p.Description -match 'VOLUME_MAK') { 'MAK' }
                   elseif ($p.Description -match 'VOLUME_KMS') { 'KMS' }
                   elseif ($p.Description -match 'RETAIL') { 'Retail' }
                   elseif ($p.Description -match 'OEM') { 'OEM' }
                   else { 'Other/Unknown' }

        Write-Host ('Edition: ' + $p.Name)
        Write-Host ('Channel: ' + $channel)
        Write-Host ('Key last 5: ' + $p.PartialProductKey)

        if ($p.LicenseStatus -eq 1) {
            Write-Host 'Status: Activated'
            continue
        }

        Write-Host 'Status: Not activated'
        $reason = Show-ErrorCode $p.LicenseStatusReason
        # This CIM field is a reported reason, not necessarily the most recent activation failure.
        if ($reason -ne 'N/A' -and $reason -ne '0x00000000') {
            Write-Host ('Reported reason: ' + $reason)
        }
        if ($reason -eq '0xC004C020') {
            Write-Host '[C020] MAK activation limit exceeded; verify the volume license entitlement.'
            if ($channel -ne 'MAK') {
                Write-Host '[CHECK] Channel and reason differ; confirm the current activation error.'
            }
        } elseif ($reason -eq '0xC004C008') {
            if ($channel -eq 'Retail') {
                Write-Host '[C008] Retail key use/activation limit issue.'
            } else {
                Write-Host '[C008] Key use/activation limit issue (not Retail-specific).'
            }
        } elseif ($reason -eq '0xC004F074') {
            Write-Host '[KMS] KMS activation service unavailable.'
        } elseif ($reason -eq '0xC004F050') {
            Write-Host '[KEY] Product key may be invalid.'
        } elseif ($reason -eq '0xC004C003') {
            Write-Host '[KEY] Activation server rejected the product key.'
        } elseif ($reason -eq '0xC004F212') {
            Write-Host '[KEY] Product key may not match Windows edition.'
        } else {
            Write-Host '[INFO] Check Windows Activation settings for the current error.'
        }
    }
}

function Test-PitvnConnectivity {
    # A HEAD request does not submit an IID or an API key.
    # An HTTP 401/403/405 is evidence of HTTPS reachability, NOT valid credentials.
    try {
        $response = Invoke-WebRequest -Uri $CidApi -Method Head -UseBasicParsing -MaximumRedirection 0 -TimeoutSec 15 -ErrorAction Stop
        $status = [int]$response.StatusCode
    } catch {
        $httpResponse = $_.Exception.Response
        if ($null -eq $httpResponse) {
            throw 'Cannot reach PITVN over HTTPS (DNS, TLS, firewall or network failure).'
        }
        $status = [int]$httpResponse.StatusCode
    }

    Write-Host ('[INFO] PITVN endpoint HTTP status: ' + $status)
    if ($status -in @(200,204,400,401,403,405)) {
        Write-Host '[OK] HTTPS endpoint answered. API credentials and POST behavior NOT verified.'
    } elseif ($status -eq 404) {
        Write-Host '[WARN] HTTP 404 on HEAD request.'
        Write-Host '[OK] HTTPS server responded.'
        Write-Host '[INFO] POST API availability is not verified.'
    } elseif ($status -eq 429) {
        throw 'API endpoint responded with rate limiting (HTTP 429).'
    } else {
        throw ('Unexpected API endpoint HTTP status: ' + $status)
    }
}

function Test-CidRequest([object[]]$Products) {
    if (@($Products | Where-Object { $_.LicenseStatus -eq 1 }).Count -gt 0) {
        Write-Host '[SKIP] Windows already activated. No IID sent; no API key requested.'
        return
    }

    $candidates = @($Products | Where-Object { $_.LicenseStatus -ne 1 })
    if ($candidates.Count -ne 1) {
        throw 'Cannot safely select one unactivated Windows license. Inspect the license manually.'
    }

    # This documented read-only CIM property avoids parsing localized slmgr output.
    $iid = ([string]$candidates[0].OfflineInstallationId) -replace '\D', ''
    if ($iid.Length -lt 45 -or $iid.Length -gt 90) {
        throw 'No plausible OfflineInstallationId available. Check slmgr /dti manually.'
    }

    Write-Host '[INFO] An Installation ID is available.'
    Write-Host '[INFO] The IID is device-specific and will be sent to PITVN only if approved.'
    Write-Host '[INFO] This request may count toward your PITVN quota.'
    $approval = Read-Host 'Confirm licensed use and IID submission: type YES'
    if ($approval -cne 'YES') {
        Write-Host '[CANCEL] No API request made.'
        return
    }

    $secret = Read-Host 'Enter PITVN API Key (hidden)' -AsSecureString
    if ($secret.Length -lt 8) {
        throw 'No valid-looking API key was entered.'
    }
    $credential = New-Object System.Management.Automation.PSCredential('pitvn', $secret)
    $apiKey = $null
    try {
        $apiKey = $credential.GetNetworkCredential().Password
        $json = @{ iid = $iid } | ConvertTo-Json -Compress
        try {
            $reply = Invoke-RestMethod -Uri $CidApi -Method Post -ContentType 'application/json' `
                -Headers @{ Authorization = ('Bearer ' + $apiKey) } -Body $json `
                -MaximumRedirection 0 -TimeoutSec 30 -ErrorAction Stop
        } catch {
            $httpResponse = $_.Exception.Response
            if ($null -ne $httpResponse) {
                $status = [int]$httpResponse.StatusCode
                switch ($status) {
                    401 { throw 'PITVN HTTP 401: API key was not accepted.' }
                    403 { throw 'PITVN HTTP 403: access denied.' }
                    429 { throw 'PITVN HTTP 429: request limit reached.' }
                    default { throw ('PITVN returned HTTP ' + $status + '.') }
                }
            }
            throw 'PITVN API request failed due to network, TLS or timeout.'
        }
    } finally {
        $apiKey = $null
        $credential = $null
        $secret = $null
    }

    $cid = ([string]$reply.cid) -replace '\D', ''
    if ($cid.Length -notin @(48,54)) {
        throw 'PITVN response did not contain a recognizable 48/54-digit CID.'
    }
    Write-Host ('[OK] PITVN returned a CID (' + $cid.Length + ' digits).')
    Write-Host '[DONE] CID checked in memory only; not printed, saved or applied.'
}


# Read-only inventory. Never use Win32_Product, which can trigger MSI repair.
function Get-InstalledPrograms {
    $locations = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $items = @()
    foreach ($location in $locations) {
        $items += @(Get-ItemProperty -Path $location -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.DisplayName) } |
            ForEach-Object {
                [pscustomobject]@{
                    Name = [string]$_.DisplayName
                    Version = [string]$_.DisplayVersion
                    Publisher = [string]$_.Publisher
                    Id = [string]$_.PSChildName
                }
            })
    }
    return @($items | Sort-Object Name, Version, Publisher, Id -Unique)
}

function Select-Programs([string]$Category) {
    $all = @(Get-InstalledPrograms)
    switch ($Category) {
        'Office' {
            $found = @($all | Where-Object {
                $_.Publisher -match '(?i)Microsoft' -and
                $_.Name -match '(?i)^(Microsoft (365|Office|Visio|Project)|Office (2010|2013|2016|2019|2021|2024|LTSC))'
            })
        }
        'WPS' {
            $found = @($all | Where-Object {
                $_.Name -match '(?i)(WPS Office|Kingsoft Office)' -or
                ($_.Publisher -match '(?i)Kingsoft' -and $_.Name -match '(?i)WPS')
            })
        }
        '360' {
            $found = @($all | Where-Object {
                $_.Name -match '(?i)^(360 Total Security|360 Security|360 Safe|360 Browser|360 Driver|Qihoo 360)' -or
                ($_.Publisher -match '(?i)(Qihoo|360 Security)' -and $_.Name -match '(?i)^(360|Qihoo)')
            })
        }
        default { $found = @() }
    }
    return @($found)
}

function Wait-ForBack {
    [void](Read-Host 'Nhấn Enter để quay lại menu')
}

function Show-Programs([string]$Category) {
    $items = @(Select-Programs -Category $Category)
    if ($items.Count -eq 0) {
        Write-Host ('[INFO] Chưa phát hiện chương trình ' + $Category + ' trong danh sách gỡ cài đặt.')
        Write-Host '[INFO] Một số thành phần có thể không đăng ký tại đây.'
        return
    }
    for ($i = 0; $i -lt $items.Count; $i++) {
        Write-Host ("{0}. {1}  {2}" -f ($i + 1), $items[$i].Name, $items[$i].Version)
    }
    return $items
}

function Show-OfficeLicenses {
    $roots = @($env:ProgramFiles, [Environment]::GetFolderPath('ProgramFilesX86'))
    $paths = @()
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        foreach ($suffix in @('Microsoft Office\root\Office16\OSPP.VBS', 'Microsoft Office\Office16\OSPP.VBS', 'Microsoft Office\Office15\OSPP.VBS', 'Microsoft Office\Office14\OSPP.VBS')) {
            $path = Join-Path $root $suffix
            if (Test-Path -LiteralPath $path -PathType Leaf) { $paths += $path }
        }
    }
    $paths = @($paths | Select-Object -Unique)
    if ($paths.Count -eq 0) {
        Write-Host '[INFO] Không tìm thấy ospp.vbs. Một số bản Microsoft 365 không dùng công cụ này.'
        return
    }
    foreach ($path in $paths) {
        Write-Host ('[READ ONLY] ' + $path)
        & cscript.exe //nologo $path /dstatus
    }
}

function Invoke-PhoneActivation([string]$Product) {
    # Load the reviewed module at a fixed commit, then invoke with explicit product.
    $url = 'https://raw.githubusercontent.com/duymunn/DUYFIX/629454d67959aa4e2d52a8d6f0781cc3debaa97c/DuyFix.PhoneActivation.ps1'
    $source = (Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 30 -ErrorAction Stop).Content
    if (-not $source.StartsWith('# DUYFIX-PHONE: 1.7.2')) {
        throw 'Phien ban PhoneActivation khong dung; dung lai.'
    }
    & ([scriptblock]::Create($source)) -Product $Product
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Write-Host '=============================================='
        Write-Host '                DUYFIX v1.7'
        Write-Host '=============================================='
        Write-Host '1. Active Windows (Retail - Phone)'
        Write-Host '2. Active Office (Retail - Phone)'
        Write-Host '3. Xóa key Windows, dọn công cụ crack'
        Write-Host '4. Xóa key Office, dọn công cụ crack'
        Write-Host '5. Gỡ Office (chọn bản giữ / bản xóa)'
        Write-Host '6. Gỡ WPS Office [TAM DUNG]'
        Write-Host '7. Gỡ phần mềm 360 [TAM DUNG]'
        Write-Host '0. Thoát'
        Write-Host '=============================================='
        $choice = Read-Host 'Chọn chức năng'
        if ($choice -eq '0') { return }
        Clear-Host
        switch ($choice) {
            '1' { Invoke-PhoneActivation -Product 'Windows' }
            '2' { Invoke-PhoneActivation -Product 'Office' }
            '3' {
                Write-Host 'XÓA KEY WINDOWS / DỌN CRACK'
                Show-Diagnostics -Products @(Get-WindowsProducts)
                Write-Host ''
                Write-Host '[PREVIEW] Xóa key có thể khiến Windows mất kích hoạt.'
                Write-Host '[INFO] Chưa xóa key/tập tin nào. Không xóa hàng loạt task/service chưa xác minh.'
            }
            '4' {
                Write-Host 'XÓA KEY OFFICE / DỌN CRACK'
                Show-OfficeLicenses
                Write-Host '[INFO] Chưa xóa key/tập tin nào. Cần xác định chính xác giấy phép.'
            }
            '5' {
                Write-Host 'GỠ MICROSOFT OFFICE'
                $apps = @(Show-Programs -Category 'Office')
                if ($apps.Count -gt 0) {
                    Write-Host ''
                    Write-Host 'Chọn số bản muốn gỡ; ALL để chọn toàn bộ; 0 để giữ nguyên.'
                    $select = (Read-Host 'Lựa chọn').Trim()
                    if ($select -eq '0' -or $select -eq '') {
                        Write-Host '[KEEP] Giữ lại toàn bộ.'
                    } elseif ($select -ieq 'ALL') {
                        Write-Host '[PREVIEW] Đã chọn tất cả bản Office liệt kê.'
                    } else {
                        $idx = 0
                        if ([int]::TryParse($select, [ref]$idx) -and $idx -ge 1 -and $idx -le $apps.Count) {
                            Write-Host ('[PREVIEW] Đã chọn: ' + $apps[$idx - 1].Name)
                        } else {
                            Write-Host '[CANCEL] Lựa chọn không hợp lệ.'
                        }
                    }
                    Write-Host '[INFO] Chưa thực thi gỡ cài đặt. Đây là chế độ chọn trước.'
                }
            }
            '6' { Write-Host '[PAUSED] Chuc nang go WPS dang tam dung.' }
            '7' { Write-Host '[PAUSED] Chuc nang go 360 dang tam dung.' }
            default { Write-Host '[ERROR] Vui lòng chọn từ 0 đến 7.' }
        }
        Write-Host ''
        Wait-ForBack
    }
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Host '=========================================='
    Write-Host '       DUYFIX v1.7'
    Write-Host '=========================================='
    Write-Host ''

    if ($Mode -eq '--self-test') {
        Write-Host '[OK] Script parsed and started successfully.'
        Write-Host '[DONE] No Windows activation changes. No PITVN requests.'
        exit 0
    }

    if ($Mode -eq '--menu') {
        Show-MainMenu
        exit 0
    }

    $products = @(Get-WindowsProducts)
    Show-Diagnostics -Products $products
    Write-Host ''

    if ($Mode -eq '--dry-run') {
        Write-Host '[LICENSE EXPIRY]'
        & "$env:windir\System32\cscript.exe" //nologo "$env:windir\System32\slmgr.vbs" /xpr
        Write-Host '[DONE] DRY RUN - NO SYSTEM CHANGES, NO PITVN REQUESTS.'
    } elseif ($Mode -eq '--api-test') {
        Test-PitvnConnectivity
        Write-Host '[DONE] No IID or API key was sent. No system changes.'
    } elseif ($Mode -eq '--cid-test') {
        Test-CidRequest -Products $products
        Write-Host '[DONE] No Windows activation changes.'
    }
    exit 0
} catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message)
    Write-Host '[DONE] No Windows activation changes.'
    exit 3
}
