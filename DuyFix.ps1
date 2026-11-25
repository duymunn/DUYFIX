# DUYFIX-PS1: 1.4
# Windows activation diagnostic and voluntary PITVN API connectivity/CID test.
# All modes are non-mutating: no /ipk, /upk, /cpky, /ato, /atp or service changes.
param(
    [ValidateSet('--dry-run','--api-test','--cid-test','--self-test')]
    [string]$Mode = '--dry-run'
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
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-Host ('Windows: ' + $os.Caption)

    $active = @($Products | Where-Object { $_.LicenseStatus -eq 1 })
    if ($active.Count -gt 0) {
        Write-Host '[OK] Windows is activated.'
    } else {
        Write-Host '[WARN] Windows is not activated (or no installed key was detected).'
    }

    if ($Products.Count -eq 0) {
        Write-Host '[WARN] No installed Windows product key found.'
    }
    foreach ($p in $Products) {
        Write-Host '------------------------------------------'
        Write-Host ('Edition: ' + $p.Name)
        Write-Host ('Channel: ' + $p.Description)
        Write-Host ('Key last 5: ' + $p.PartialProductKey)
        Write-Host ('License status: ' + $p.LicenseStatus)
        $reason = Show-ErrorCode $p.LicenseStatusReason
        Write-Host ('Reason code: ' + $reason)
        $channel = if ($p.Description -match 'VOLUME_MAK') { 'MAK' }
                   elseif ($p.Description -match 'RETAIL') { 'Retail' }
                   elseif ($p.Description -match 'OEM') { 'OEM' }
                   elseif ($p.Description -match 'VOLUME_KMS') { 'KMS' }
                   else { 'Other/Unknown' }
        Write-Host ('Key channel group: ' + $channel)
        if ($p.LicenseStatus -eq 1) {
            Write-Host '[SKIP] Already activated - do not infer an activation error from the key type.'
        } elseif ($reason -eq '0xC004C020') {
            Write-Host '[C020] MAK activation count limit was exceeded.'
            if ($channel -ne 'MAK') { Write-Host '[CHECK] The reported key channel is not MAK; verify the actual activation error.' }
            Write-Host '[NEXT] Contact the volume licensing administrator or Microsoft for entitlement review.'
        } elseif ($reason -eq '0xC004C008') {
            if ($channel -eq 'Retail') {
                Write-Host '[RETAIL/C008] Retail key already in use or activation limit reached.'
            } else {
                Write-Host '[C008] Key use/activation limit issue. This error is not exclusive to Retail.'
            }
            Write-Host '[NEXT] Check the licensing terms and the Windows activation troubleshooter.'
        } elseif ($reason -eq '0xC004F074') {
            Write-Host '[KMS] Cannot contact KMS activation service.'
        } elseif ($reason -eq '0xC004F050') {
            Write-Host '[KEY] Product key may be invalid.'
        } elseif ($reason -eq '0xC004C003') {
            Write-Host '[KEY] Activation server rejected the product key.'
        } elseif ($reason -eq '0xC004F212') {
            Write-Host '[KEY] Product key may not match Windows edition.'
        } else {
            Write-Host '[INFO] Check Windows Activation settings for the latest error.'
        }
    }

    Write-Host '------------------------------------------'
    Write-Host '[INFO] Licensing-related services:'
    foreach ($name in @('sppsvc','Winmgmt','LicenseManager','wuauserv')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service) {
            Write-Host ('Service ' + $name + ': ' + $service.Status)
        } else {
            Write-Host ('Service ' + $name + ': not found')
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

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Host '=========================================='
    Write-Host '       DUYFIX v1.4 - DIAGNOSTIC'
    Write-Host '=========================================='
    Write-Host ('[MODE] ' + $Mode)
    Write-Host '[SAFETY] No Windows activation changes in this release.'
    Write-Host ''

    if ([string]::IsNullOrEmpty($PSCommandPath)) {
        Write-Host '[STORAGE] In-memory mode. DUYFIX does not create local .cmd/.ps1 files.'
    } else {
        Write-Host '[STORAGE] Launched from a local PowerShell file.'
    }

    if ($Mode -eq '--self-test') {
        Write-Host '[OK] Script parsed and started successfully.'
        Write-Host '[DONE] No Windows activation changes. No PITVN requests.'
        exit 0
    }

    $products = @(Get-WindowsProducts)
    Show-Diagnostics -Products $products
    Write-Host ''

    if ($Mode -eq '--dry-run') {
        Write-Host '[INFO] Official license expiration check:'
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
