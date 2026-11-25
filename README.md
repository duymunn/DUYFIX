# DUYFIX v1.4

Windows activation diagnostics, optional PITVN endpoint connectivity test and CID-request test. **No Windows activation changes** in this version. Intended for appropriately licensed Windows machines.

## How to run (CMD)

Recommended no-file command, tested by the user on Windows 10 only for earlier versions; v1.3 requires a real Windows test:

```cmd
powershell.exe -NoProfile -Command "$ErrorActionPreference='Stop';$u='https://raw.githubusercontent.com/duymunn/DUYFIX/d2a02f8fe9be8271dc16d5eb88dce36fa18d960c/DuyFix.ps1';$s=(Invoke-WebRequest -UseBasicParsing -Uri $u -TimeoutSec 30).Content;if(-not $s.StartsWith('# DUYFIX-PS1: 1.3')){throw 'Unexpected version'};& ([scriptblock]::Create($s)) -Mode '--dry-run'"
```

Switch `--dry-run` to `--self-test` or `--api-test` as needed.

Alternative using the short CMD launcher in GitHub (creates one downloaded CMD file; the child PowerShell script runs from memory):

```cmd
curl.exe -fsSL "https://raw.githubusercontent.com/duymunn/DUYFIX/main/DuyFix.cmd?v=1.4" -o "%TEMP%\DuyFix.cmd" && (call "%TEMP%\DuyFix.cmd" --dry-run & del /f /q "%TEMP%\DuyFix.cmd" >nul 2>&1)
```

If CMD is forcibly closed during the latter command, the downloaded CMD file may remain. The first, fileless command avoids this cleanup dependency. Neither method can promise to erase Windows histories, OS logging or traces from network devices.

## Modes

- `--self-test`: Check that code starts; no licensing query or PITVN request.
- `--dry-run`: Read local Windows licensing and service status; no changes.
- `--api-test`: Run read-only diagnostics and send an unauthenticated HEAD request; an HTTP 404 or 405 is **not** proof that POST GetCID works.
- `--cid-test`: Only for eligible, unactivated installations. Asks for approval, IID submission and a hidden API key, then validates the returned CID in memory. Does not apply CID or activate Windows. An API request may consume provider credits.

## Security notes

The PowerShell URL references a fixed Git commit. Never publish a real PITVN API Key in this repository. Anyone with control of the target PC may still inspect data in a running process; this is not secure API-key storage. Review code before running. No test against PITVN's authenticated POST endpoint was carried out during the v1.3 update.


## Short CMD command (v1.4, read-only default)

The shortest practical command with the existing public GitHub repository is:

```cmd
powershell -nop -c "iex (irm https://raw.githubusercontent.com/duymunn/DUYFIX/main/DuyFix.ps1)"
```

This executes whatever is currently on the `main` branch. Review the script before use; it is not pinned to a revision. No DUYFIX file is written to disk by this command. For a fixed revision use the commit-pinned URL in the longer command above. By default, the script runs `--dry-run`.

C008 commonly relates to activation limit/key-use issues, particularly Retail. C020 specifically means a MAK exceeded its activation limit. Classification should read both the observed error code and license channel rather than infer one from the other. An already licensed PC is never flagged from its channel alone. These are diagnostic outputs, not instructions to bypass license limits.
