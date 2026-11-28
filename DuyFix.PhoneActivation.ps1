# DUYFIX-PHONE: 1.7
# Windows / Office Retail phone activation with an existing licensed key.
# No product-key installation, removal, KMS changes or license bypass.
param(
    [ValidateSet('Windows','Office')]
    [string]$Product = 'Windows'
)

$ErrorActionPreference = 'Stop'
$ApiUrl = 'https://tritran.pitvncommunity.com/api/cid'
$WindowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'

function Test-Admin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Cscript {
    param([string]$Path, [string[]]$Arguments)
    $out = (& "$env:windir\System32\cscript.exe" //nologo $Path @Arguments 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw ('Windows Script Host error (exit ' + $LASTEXITCODE + '): ' + $out.Trim())
    }
    return $out
}

function Convert-ValidIid([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    if ($Value -notmatch '^[0-9 \-]+$') { return $null }
    $digits = $Value -replace '[ \-]', ''
    if ($digits.Length -lt 45 -or $digits.Length -gt 90) { return $null }
    return $digits
}

function Get-IidFromText([string]$Text) {
    $ids = @(
        foreach ($line in ($Text -split '\r?\n')) {
            $m = [regex]::Match($line, '^[ \t]*Installation[ \t]+ID[ \t]*:[ \t]*([0-9][0-9 \-]*)[ \t]*$', 'IgnoreCase')
            if ($m.Success) {
                $candidate = Convert-ValidIid $m.Groups[1].Value
                if ($candidate) { $candidate }
            }
        }
    ) | Select-Object -Unique
    if (@($ids).Count -ne 1) {
        throw 'Không đọc được duy nhất một Installation ID. Vui lòng kiểm tra kích hoạt thủ công.'
    }
    return [string]$ids[0]
}

function Get-ConfirmationId([string]$Iid) {
    Write-Host ''
    Write-Host '1. Lay CID qua PITVN API'
    Write-Host '2. Nhap CID da duoc cap hop le'
    Write-Host '0. Quay lai'
    $choice = Read-Host 'Chon'
    if ($choice -eq '0') { throw 'Da huy yeu cau.' }

    if ($choice -eq '1') {
        if ((Read-Host 'Gui IID may nay den PITVN? Nhap YES') -cne 'YES') {
            throw 'Da huy gui IID.'
        }
        $secret = Read-Host 'PITVN API Key (an)' -AsSecureString
        if ($secret.Length -lt 8) { throw 'API Key khong hop le.' }
        $cred = New-Object System.Management.Automation.PSCredential('pitvn', $secret)
        $token = $null
        try {
            $token = $cred.GetNetworkCredential().Password
            $body = @{ iid = $Iid } | ConvertTo-Json -Compress
            try {
                $reply = Invoke-RestMethod -Uri $ApiUrl -Method Post -ContentType 'application/json' -Body $body -Headers @{ Authorization = ('Bearer ' + $token) } -MaximumRedirection 0 -TimeoutSec 45 -ErrorAction Stop
            } catch {
                $response = $_.Exception.Response
                if ($null -ne $response) {
                    $status = [int]$response.StatusCode
                    throw ('PITVN API trả về HTTP ' + $status + '. Kiểm tra API Key, quyền truy cập hoặc hạn mức.')
                }
                throw 'Khong the goi PITVN API (mang, TLS hoac timeout).'
            }
            if ($null -eq $reply -or $null -eq $reply.cid) { throw 'PITVN khong tra ve truong cid.' }
            $rawCid = [string]$reply.cid
        } finally {
            $token = $null
            $cred = $null
            $secret = $null
        }
    } elseif ($choice -eq '2') {
        $rawCid = Read-Host 'Nhap Confirmation ID'
    } else {
        throw 'Lua chon khong hop le.'
    }

    if ($rawCid -notmatch '^[0-9 \-]+$') {
        throw 'Confirmation ID khong phai chuoi so hop le.'
    }
    $cid = $rawCid -replace '[ \-]', ''
    if ($cid.Length -notin @(48,54)) {
        throw 'Confirmation ID phai co 48 hoac 54 chu so.'
    }
    return $cid
}

function Confirm-Activation {
    if ((Read-Host 'Nap CID cho giay phep hien tai? Nhap APPLY') -cne 'APPLY') {
        throw 'Da huy nap CID. Khong thay doi giay phep.'
    }
}

function Activate-WindowsRetail {
    Write-Host '=== WINDOWS RETAIL - PHONE ACTIVATION ==='
    $products = @(
        Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
        Where-Object { $_.ApplicationID -eq $WindowsAppId -and $_.PartialProductKey -and $_.Name -like 'Windows*' -and -not $_.LicenseIsAddon }
    )
    if (@($products | Where-Object { $_.LicenseStatus -eq 1 }).Count -gt 0) {
        Write-Host '[SKIP] Windows da kich hoat. Khong thay doi.'
        return
    }

    $pending = @($products | Where-Object { $_.LicenseStatus -ne 1 -and $_.Description -match '(?i)RETAIL' -and $_.Description -notmatch '(?i)VOLUME|MAK|KMS' })
    if ($pending.Count -eq 0) {
        Write-Host 'No Windows Retail product key is installed.'
        $secureKey = Read-Host 'Enter your Retail product key (hidden; Enter to cancel)' -AsSecureString
        if ($secureKey.Length -eq 0) { return }
        $keyCredential = New-Object System.Management.Automation.PSCredential('product', $secureKey)
        $productKey = $keyCredential.GetNetworkCredential().Password.Trim().ToUpperInvariant()
        if ($productKey -notmatch '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}
    $activationId = [string]$target.ID
    Write-Host ('Windows: ' + $target.Name)
    Write-Host ('Retail key last 5: ' + $target.PartialProductKey)
    $iid = Convert-ValidIid ([string]$target.OfflineInstallationId)
    if (-not $iid) {
        $iidText = Invoke-Cscript -Path "$env:windir\System32\slmgr.vbs" -Arguments @('/dti', $activationId)
        $iid = Get-IidFromText $iidText
    }
    Write-Host '[OK] Da lay IID.'
    $cid = Get-ConfirmationId $iid
    Confirm-Activation
    [void](Invoke-Cscript -Path "$env:windir\System32\slmgr.vbs" -Arguments @('/atp', $cid, $activationId))

    $licensed = @(Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
        Where-Object { $_.ApplicationID -eq $WindowsAppId -and $_.ID -eq $activationId -and $_.LicenseStatus -eq 1 })
    if ($licensed.Count -eq 0) {
        throw 'Windows chua bao LicenseStatus=1. Can kiem tra Activation Settings.'
    }
    Write-Host '[SUCCESS] Windows da kich hoat.'
}

function Get-OfficeScripts {
    $roots = @($env:ProgramFiles, [Environment]::GetFolderPath('ProgramFilesX86'))
    $suffixes = @(
        'Microsoft Office\root\Office16\OSPP.VBS',
        'Microsoft Office\Office16\OSPP.VBS',
        'Microsoft Office\Office15\OSPP.VBS',
        'Microsoft Office\Office14\OSPP.VBS'
    )
    $found = @(
        foreach ($root in $roots) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            foreach ($suffix in $suffixes) {
                $path = Join-Path $root $suffix
                if (Test-Path -LiteralPath $path -PathType Leaf) { $path }
            }
        }
    )
    return @($found | Select-Object -Unique)
}

function Get-OfficeRecords([string]$Ospp) {
    $text = Invoke-Cscript -Path $Ospp -Arguments @('/dstatus')
    $sections = [regex]::Split($text, '(?im)(?=^[ \t]*SKU ID:)')
    foreach ($section in $sections) {
        $skuMatch = [regex]::Match($section, '(?im)^[ \t]*SKU ID:[ \t]*([0-9a-f-]{36})[ \t]*$', 'IgnoreCase')
        if (-not $skuMatch.Success) { continue }
        $descMatch = [regex]::Match($section, '(?im)^[ \t]*LICENSE DESCRIPTION:[ \t]*(.+)$', 'IgnoreCase')
        $nameMatch = [regex]::Match($section, '(?im)^[ \t]*LICENSE NAME:[ \t]*(.+)$', 'IgnoreCase')
        $statusMatch = [regex]::Match($section, '(?im)^[ \t]*LICENSE STATUS:[ \t]*(.+)$', 'IgnoreCase')
        [pscustomobject]@{
            Sku = $skuMatch.Groups[1].Value
            Description = $descMatch.Groups[1].Value.Trim()
            Name = $nameMatch.Groups[1].Value.Trim()
            Status = $statusMatch.Groups[1].Value.Trim()
            Ospp = $Ospp
        }
    }
}

function Activate-OfficeRetail {
    Write-Host '=== OFFICE RETAIL - PHONE ACTIVATION ==='
    $scripts = @(Get-OfficeScripts)
    if ($scripts.Count -eq 0) {
        throw 'Khong co ospp.vbs. Microsoft 365 Apps dang thue bao khong ho tro.'
    }
    $records = @(
        foreach ($script in $scripts) { Get-OfficeRecords $script }
    )
    $retail = @($records | Where-Object {
        $_.Description -match '(?i)RETAIL' -and $_.Description -notmatch '(?i)VOLUME|MAK|KMS'
    } | Sort-Object Sku, Ospp -Unique)
    if ($retail.Count -eq 0) { throw 'Khong co Office Retail su dung ospp.vbs.' }

    $pending = @($retail | Where-Object { $_.Status -notmatch '(?i)---LICENSED---' })
    if ($pending.Count -eq 0) {
        Write-Host '[SKIP] Office Retail da kich hoat.'
        return
    }
    if ($pending.Count -gt 1) {
        Write-Host 'Cac giay phep Office Retail chua kich hoat:'
        for ($i = 0; $i -lt $pending.Count; $i++) {
            Write-Host ('{0}. {1}' -f ($i + 1), $pending[$i].Name)
        }
        $selection = 0
        $answer = Read-Host 'Chon so giay phep (0: huy)'
        if (-not [int]::TryParse($answer, [ref]$selection) -or $selection -lt 1 -or $selection -gt $pending.Count) {
            throw 'Da huy. Khong thay doi giay phep Office.'
        }
        $target = $pending[$selection - 1]
    } else {
        $target = $pending[0]
    }

    Write-Host ('Office: ' + $target.Name)
    $iidText = Invoke-Cscript -Path $target.Ospp -Arguments @('/dinstid')
    $iid = Get-IidFromText $iidText
    Write-Host '[OK] Da lay IID.'
    $cid = Get-ConfirmationId $iid
    Confirm-Activation
    [void](Invoke-Cscript -Path $target.Ospp -Arguments @(('/actcid:' + $cid)))
    $statusNow = @(Get-OfficeRecords $target.Ospp | Where-Object { $_.Sku -eq $target.Sku -and $_.Status -match '(?i)---LICENSED---' })
    if ($statusNow.Count -eq 0) {
        throw 'Office chua bao trang thai LICENSED. Kiem tra Activation trong Office.'
    }
    Write-Host '[SUCCESS] Office da kich hoat.'
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Test-Admin)) { throw 'Hay mo CMD bang Run as administrator.' }
    if ($Product -eq 'Windows') { Activate-WindowsRetail }
    else { Activate-OfficeRetail }
} catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message)
}
) {
            Write-Host 'Product key format: XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
            return
        }
        if ((Read-Host 'Install this key into Windows? Type INSTALL') -cne 'INSTALL') { return }
        $lastFive = $productKey.Substring(24,5)
        $slmgr = "$env:windir\System32\slmgr.vbs"
        try {
            $result = Invoke-Cscript -Path $slmgr -Arguments @('/ipk', $productKey)
            Write-Host (($result -replace [regex]::Escape($productKey), '[KEY REDACTED]').Trim())
        } finally {
            $productKey = $null
            $keyCredential = $null
            $secureKey = $null
        }
        $products = @(
            Get-CimInstance SoftwareLicensingProduct |
            Where-Object { $_.ApplicationID -eq $WindowsAppId -and $_.PartialProductKey -and $_.Name -like 'Windows*' -and -not $_.LicenseIsAddon }
        )
        if (@($products | Where-Object LicenseStatus -eq 1).Count -gt 0) {
            Write-Host 'Windows reports LicenseStatus=1.'
            return
        }
        $pending = @($products | Where-Object {
            $_.LicenseStatus -ne 1 -and $_.Description -match '(?i)RETAIL' -and
            $_.Description -notmatch '(?i)VOLUME|MAK|KMS'
        })
        $matching = @($pending | Where-Object { $_.PartialProductKey -eq $lastFive })
        if ($matching.Count -eq 1) { $pending = $matching }
    }
    if ($pending.Count -ne 1) {
        Write-Host (Invoke-Cscript -Path "$env:windir\System32\slmgr.vbs" -Arguments @('/dli'))
        return
    }

    $target = $pending[0]
    $activationId = [string]$target.ID
    Write-Host ('Windows: ' + $target.Name)
    Write-Host ('Retail key last 5: ' + $target.PartialProductKey)
    $iid = Convert-ValidIid ([string]$target.OfflineInstallationId)
    if (-not $iid) {
        $iidText = Invoke-Cscript -Path "$env:windir\System32\slmgr.vbs" -Arguments @('/dti', $activationId)
        $iid = Get-IidFromText $iidText
    }
    Write-Host '[OK] Da lay IID.'
    $cid = Get-ConfirmationId $iid
    Confirm-Activation
    [void](Invoke-Cscript -Path "$env:windir\System32\slmgr.vbs" -Arguments @('/atp', $cid, $activationId))

    $licensed = @(Get-CimInstance -ClassName SoftwareLicensingProduct -ErrorAction Stop |
        Where-Object { $_.ApplicationID -eq $WindowsAppId -and $_.ID -eq $activationId -and $_.LicenseStatus -eq 1 })
    if ($licensed.Count -eq 0) {
        throw 'Windows chua bao LicenseStatus=1. Can kiem tra Activation Settings.'
    }
    Write-Host '[SUCCESS] Windows da kich hoat.'
}

function Get-OfficeScripts {
    $roots = @($env:ProgramFiles, [Environment]::GetFolderPath('ProgramFilesX86'))
    $suffixes = @(
        'Microsoft Office\root\Office16\OSPP.VBS',
        'Microsoft Office\Office16\OSPP.VBS',
        'Microsoft Office\Office15\OSPP.VBS',
        'Microsoft Office\Office14\OSPP.VBS'
    )
    $found = @(
        foreach ($root in $roots) {
            if ([string]::IsNullOrWhiteSpace($root)) { continue }
            foreach ($suffix in $suffixes) {
                $path = Join-Path $root $suffix
                if (Test-Path -LiteralPath $path -PathType Leaf) { $path }
            }
        }
    )
    return @($found | Select-Object -Unique)
}

function Get-OfficeRecords([string]$Ospp) {
    $text = Invoke-Cscript -Path $Ospp -Arguments @('/dstatus')
    $sections = [regex]::Split($text, '(?im)(?=^[ \t]*SKU ID:)')
    foreach ($section in $sections) {
        $skuMatch = [regex]::Match($section, '(?im)^[ \t]*SKU ID:[ \t]*([0-9a-f-]{36})[ \t]*$', 'IgnoreCase')
        if (-not $skuMatch.Success) { continue }
        $descMatch = [regex]::Match($section, '(?im)^[ \t]*LICENSE DESCRIPTION:[ \t]*(.+)$', 'IgnoreCase')
        $nameMatch = [regex]::Match($section, '(?im)^[ \t]*LICENSE NAME:[ \t]*(.+)$', 'IgnoreCase')
        $statusMatch = [regex]::Match($section, '(?im)^[ \t]*LICENSE STATUS:[ \t]*(.+)$', 'IgnoreCase')
        [pscustomobject]@{
            Sku = $skuMatch.Groups[1].Value
            Description = $descMatch.Groups[1].Value.Trim()
            Name = $nameMatch.Groups[1].Value.Trim()
            Status = $statusMatch.Groups[1].Value.Trim()
            Ospp = $Ospp
        }
    }
}

function Activate-OfficeRetail {
    Write-Host '=== OFFICE RETAIL - PHONE ACTIVATION ==='
    $scripts = @(Get-OfficeScripts)
    if ($scripts.Count -eq 0) {
        throw 'Khong co ospp.vbs. Microsoft 365 Apps dang thue bao khong ho tro.'
    }
    $records = @(
        foreach ($script in $scripts) { Get-OfficeRecords $script }
    )
    $retail = @($records | Where-Object {
        $_.Description -match '(?i)RETAIL' -and $_.Description -notmatch '(?i)VOLUME|MAK|KMS'
    } | Sort-Object Sku, Ospp -Unique)
    if ($retail.Count -eq 0) { throw 'Khong co Office Retail su dung ospp.vbs.' }

    $pending = @($retail | Where-Object { $_.Status -notmatch '(?i)---LICENSED---' })
    if ($pending.Count -eq 0) {
        Write-Host '[SKIP] Office Retail da kich hoat.'
        return
    }
    if ($pending.Count -gt 1) {
        Write-Host 'Cac giay phep Office Retail chua kich hoat:'
        for ($i = 0; $i -lt $pending.Count; $i++) {
            Write-Host ('{0}. {1}' -f ($i + 1), $pending[$i].Name)
        }
        $selection = 0
        $answer = Read-Host 'Chon so giay phep (0: huy)'
        if (-not [int]::TryParse($answer, [ref]$selection) -or $selection -lt 1 -or $selection -gt $pending.Count) {
            throw 'Da huy. Khong thay doi giay phep Office.'
        }
        $target = $pending[$selection - 1]
    } else {
        $target = $pending[0]
    }

    Write-Host ('Office: ' + $target.Name)
    $iidText = Invoke-Cscript -Path $target.Ospp -Arguments @('/dinstid')
    $iid = Get-IidFromText $iidText
    Write-Host '[OK] Da lay IID.'
    $cid = Get-ConfirmationId $iid
    Confirm-Activation
    [void](Invoke-Cscript -Path $target.Ospp -Arguments @(('/actcid:' + $cid)))
    $statusNow = @(Get-OfficeRecords $target.Ospp | Where-Object { $_.Sku -eq $target.Sku -and $_.Status -match '(?i)---LICENSED---' })
    if ($statusNow.Count -eq 0) {
        throw 'Office chua bao trang thai LICENSED. Kiem tra Activation trong Office.'
    }
    Write-Host '[SUCCESS] Office da kich hoat.'
}

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if (-not (Test-Admin)) { throw 'Hay mo CMD bang Run as administrator.' }
    if ($Product -eq 'Windows') { Activate-WindowsRetail }
    else { Activate-OfficeRetail }
} catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message)
}
