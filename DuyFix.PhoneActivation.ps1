
# DUYFIX-PHONE: 1.7
# File: DuyFix.PhoneActivation.ps1

param(
    [ValidateSet('Windows','Office')]
    [string]$Product = 'Windows'
)

$ErrorActionPreference = 'Stop'
$ApiUrl = 'https://tritran.pitvncommunity.com/api/cid'
$WindowsAppId = '55c92734-d682-4d71-983e-d6ec3f16059f'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Invoke-Cscript {
    param(
        [string]$Path,
        [string[]]$Arguments
    )

    $output = & "$env:windir\System32\cscript.exe" `
        //nologo $Path @Arguments 2>&1

    $text = $output | Out-String

    if ($LASTEXITCODE -ne 0) {
        throw "Windows Script Host error: $text"
    }

    return $text
}

function Get-Iid {
    param([string]$Text)

    $matches = [regex]::Matches(
        $Text,
        '(?im)^\s*Installation ID\s*:\s*([\d\s-]{40,110})'
    )

    $values = @(
        foreach ($match in $matches) {
            $match.Groups[1].Value -replace '\D', ''
        }
    ) | Select-Object -Unique

    if (@($values).Count -ne 1) {
        throw 'Khong xac dinh duoc duy nhat mot IID.'
    }

    $iid = [string]$values[0]

    if ($iid.Length -lt 45 -or $iid.Length -gt 90) {
        throw 'Installation ID khong hop le.'
    }

    return $iid
}

function Get-Cid {
    param([string]$Iid)

    Write-Host ''
    Write-Host '1. Tu dong lay CID qua PITVN'
    Write-Host '2. Nhap CID thu cong'
    Write-Host '0. Huy'
    $choice = Read-Host 'Chon'

    switch ($choice) {
        '1' {
            Write-Host '[INFO] IID se duoc gui den PITVN.'
            $confirm = Read-Host 'Dong y? Nhap YES'

            if ($confirm -cne 'YES') {
                throw 'Da huy yeu cau.'
            }

            $secure = Read-Host 'PITVN API Key' -AsSecureString

            if ($secure.Length -lt 8) {
                throw 'API Key khong hop le.'
            }

            $credential = [pscredential]::new('pitvn', $secure)
            $token = $credential.GetNetworkCredential().Password

            try {
                $body = @{ iid = $Iid } | ConvertTo-Json -Compress

                $response = Invoke-RestMethod `
                    -Uri $ApiUrl `
                    -Method Post `
                    -Headers @{ Authorization = "Bearer $token" } `
                    -ContentType 'application/json' `
                    -Body $body `
                    -TimeoutSec 45

                $cid = [string]$response.cid
            }
            finally {
                $token = $null
                $credential = $null
                $secure = $null
            }
        }

        '2' {
            $cid = Read-Host 'Nhap Confirmation ID'
        }

        default {
            throw 'Da huy kich hoat.'
        }
    }

    $cid = $cid -replace '\D', ''

    if ($cid.Length -notin @(48,54)) {
        throw 'CID khong dung dinh dang du kien.'
    }

    return $cid
}

function Activate-WindowsRetail {
    Write-Host '=== ACTIVE WINDOWS RETAIL ==='

    $products = @(
        Get-CimInstance SoftwareLicensingProduct |
        Where-Object {
            $_.ApplicationID -eq $WindowsAppId -and
            $_.PartialProductKey -and
            $_.Name -like 'Windows*'
        }
    )

    if (@($products | Where-Object LicenseStatus -eq 1).Count -gt 0) {
        Write-Host '[OK] Windows da kich hoat. Bo qua.'
        return
    }

    $retail = @(
        $products | Where-Object {
            $_.LicenseStatus -ne 1 -and
            $_.Description -match '(?i)RETAIL' -and
            $_.Description -notmatch '(?i)MAK|VOLUME'
        }
    )

    if ($retail.Count -ne 1) {
        throw 'Khong tim thay duy nhat mot giay phep Windows Retail chua kich hoat.'
    }

    Write-Host ('Key last 5: ' + $retail[0].PartialProductKey)

    $iid = ([string]$retail[0].OfflineInstallationId) -replace '\D', ''

    if ($iid.Length -lt 45 -or $iid.Length -gt 90) {
        $slmgr = "$env:windir\System32\slmgr.vbs"
        $result = Invoke-Cscript -Path $slmgr -Arguments @('/dti')
        $iid = Get-Iid -Text $result
    }

    Write-Host '[OK] Da lay Installation ID.'
    $cid = Get-Cid -Iid $iid

    $slmgr = "$env:windir\System32\slmgr.vbs"
    [void](Invoke-Cscript -Path $slmgr -Arguments @('/atp', $cid))

    $verified = @(
        Get-CimInstance SoftwareLicensingProduct |
        Where-Object {
            $_.ApplicationID -eq $WindowsAppId -and
            $_.ID -eq $retail[0].ID -and
            $_.LicenseStatus -eq 1
        }
    )

    if ($verified.Count -eq 1) {
        Write-Host '[SUCCESS] Windows da kich hoat.'
    }
    else {
        Write-Host '[FAILED] Chua xac minh duoc kich hoat Windows.'
    }
}

function Get-OfficeScripts {
    $roots = @(
        $env:ProgramFiles,
        [Environment]::GetFolderPath('ProgramFilesX86')
    )

    $suffixes = @(
        'Microsoft Office\root\Office16\OSPP.VBS',
        'Microsoft Office\Office16\OSPP.VBS',
        'Microsoft Office\Office15\OSPP.VBS',
        'Microsoft Office\Office14\OSPP.VBS'
    )

    foreach ($root in $roots) {
        if (-not $root) { continue }

        foreach ($suffix in $suffixes) {
            $path = Join-Path $root $suffix

            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $path
            }
        }
    }
}

function Get-OfficeRecords {
    param([string]$Ospp)

    $text = Invoke-Cscript -Path $Ospp -Arguments @('/dstatus')
    $sections = [regex]::Split($text, '(?im)(?=^\s*SKU ID:)')

    foreach ($section in $sections) {
        $sku = [regex]::Match(
            $section, '(?im)^\s*SKU ID:\s*([0-9a-f-]{36})'
        ).Groups[1].Value

        if (-not $sku) { continue }

        $description = [regex]::Match(
            $section, '(?im)^\s*LICENSE DESCRIPTION:\s*(.+)$'
        ).Groups[1].Value

        $status = [regex]::Match(
            $section, '(?im)^\s*LICENSE STATUS:\s*(.+)$'
        ).Groups[1].Value

        [pscustomobject]@{
            Sku = $sku
            Description = $description
            Status = $status
            Ospp = $Ospp
        }
    }
}

function Activate-OfficeRetail {
    Write-Host '=== ACTIVE OFFICE RETAIL ==='

    $scripts = @(Get-OfficeScripts | Select-Object -Unique)

    if ($scripts.Count -eq 0) {
        throw 'Khong tim thay ospp.vbs. Ban Office nay co the khong ho tro.'
    }

    $records = @(
        foreach ($script in $scripts) {
            Get-OfficeRecords -Ospp $script
        }
    )

    $retail = @(
        $records | Where-Object {
            $_.Description -match '(?i)RETAIL' -and
            $_.Description -notmatch '(?i)MAK|VOLUME'
        }
    )

    if ($retail.Count -eq 0) {
        throw 'Khong tim thay giay phep Office Retail qua OSPP.'
    }

    $pending = @(
        $retail | Where-Object {
            $_.Status -notmatch '(?i)---LICENSED---'
        }
    )

    if ($pending.Count -eq 0) {
        Write-Host '[OK] Office Retail da kich hoat.'
        return
    }

    if ($pending.Count -ne 1) {
        throw 'Co nhieu giay phep Office chua kich hoat. Can chon dung ban.'
    }

    $target = $pending[0]
    Write-Host ('Office: ' + $target.Description)

    $output = Invoke-Cscript `
        -Path $target.Ospp `
        -Arguments @('/dinstid')

    $iid = Get-Iid -Text $output
    Write-Host '[OK] Da lay Installation ID.'

    $cid = Get-Cid -Iid $iid

    [void](Invoke-Cscript `
        -Path $target.Ospp `
        -Arguments @("/actcid:$cid"))

    $after = @(Get-OfficeRecords -Ospp $target.Ospp)

    $activated = @(
        $after | Where-Object {
            $_.Sku -eq $target.Sku -and
            $_.Status -match '(?i)---LICENSED---'
        }
    )

    if ($activated.Count -eq 1) {
        Write-Host '[SUCCESS] Office da kich hoat.'
    }
    else {
        Write-Host '[FAILED] Chua xac minh duoc kich hoat Office.'
    }
}

try {
    if (-not (Test-Admin)) {
        throw 'Can mo CMD bang quyen Administrator.'
    }

    if ($Product -eq 'Windows') {
        Activate-WindowsRetail
    }
    else {
        Activate-OfficeRetail
    }
}
catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message)
}
