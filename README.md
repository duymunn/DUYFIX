# DUYFIX v1.7 - Windows / Office Retail Phone Activation

## Start from CMD (Run as Administrator)

```cmd
powershell -nop -c "iex (irm https://raw.githubusercontent.com/duymunn/DUYFIX/main/DuyFix.ps1)"
```

Menu:
1. Active Windows (Retail - Phone)
2. Active Office (Retail - Phone)
3. Windows license cleanup preview (no removal)
4. Office license cleanup preview (no removal)
5. Office uninstall preview (no removal)
6. WPS removal **PAUSED** (does not execute)
7. 360 removal **PAUSED** (does not execute)
0. Exit

### Phone activation

Module: `DuyFix.PhoneActivation.ps1`, fetched from an immutable GitHub commit. Existing **Retail** product keys only. No key installation or key removal. Windows uses the installed licensing product's OfflineInstallationId (fallback: `slmgr.vbs /dti <ActivationID>`) and `slmgr.vbs /atp <CID> <ActivationID>`. Office checks suitable OSPP.VBS Retail records, uses `/dinstid` and `/actcid:<CID>`. Microsoft 365 subscriptions are not supported by this OSPP flow.

For both paths, the user chooses a CID from PITVN (after explicitly approving IID transfer) or enters a legitimately obtained CID. The user must type `APPLY` to install the CID. The program checks the corresponding license afterwards. An authenticated PITVN POST has **not** been tested on a real target PC.

Protect API keys: enter when prompted; never commit them to public GitHub. The tool cannot guarantee Microsoft will accept a CID, even when correctly formatted. Follow the applicable license terms and check official activation status.

### Testing and safety

**No live Windows/Office activation test has been performed for v1.7.** Review the module before using on customer devices, back up where appropriate, and test only on properly licensed, authorized systems. The script downloaded from the moving `main` branch should not be used in untrusted environments. Antivirus may block remote PowerShell execution.

---

# Archive: DUYFIX v1.6 (previous design; 360 now paused)

## Lệnh CMD (menu)

```cmd
powershell -nop -c "iex (irm https://raw.githubusercontent.com/duymunn/DUYFIX/main/DuyFix.ps1)"
```

Menu mục **7. Gỡ phần mềm 360** gọi module `Remove360.ps1` bản cố định. Chỉ cần chọn 7, module sẽ tự:

1. Yêu cầu UAC nếu chưa có quyền Administrator.
2. Tìm ứng dụng Qihoo/360 từ uninstall registry (HKLM/HKCU, 32/64-bit).
3. Chạy trình gỡ đã đăng ký; dùng chế độ im lặng nếu đăng ký hoặc là MSI/Inno với tham số có thể nhận diện.
4. Nếu phần mềm vẫn đăng ký, dừng dọn cưỡng bức và thông báo. Một số bản 360 có thể cần bấm xác nhận trong trình gỡ.
5. Khi ứng dụng đã gỡ, quét process/service/driver/task trỏ về thư mục 360 đã xác định; dọn đúng các thành phần đó, nhánh registry riêng của 360, thư mục 360 được chỉ định.
6. Kiểm tra lại và thông báo thành phần còn sót, yêu cầu người dùng **tự reboot nếu cần**.

**Không tự khởi động lại.** **Không dùng file EXE tham khảo**.

Quan trọng: Đây là code chưa được kiểm thử chạy trên Windows có 360. Không thể cam kết xóa sạch 100% với mọi bản 360, nhất là driver tự bảo vệ, uninstaller yêu cầu thao tác, bản portable/Store hoặc các thư mục ngoài phạm vi. Chế độ này có thao tác xóa thực sự và có thể xóa cấu hình/dữ liệu cá nhân của sản phẩm 360 (như profile trình duyệt). Hãy thử trên máy ảo/snapshot hoặc thiết bị được phép thao tác; sao lưu dữ liệu quan trọng trước.

Các mục 1–6 vẫn là phần kiểm tra và xem trước như v1.5, chưa tự kích hoạt hoặc thực hiện gỡ hàng loạt.

## Bảo mật

Không đưa PITVN API Key thật lên GitHub. Script từ nhánh `main` thay đổi theo commit; nên kiểm tra mã và dùng bản pin cố định trước khi triển khai rộng. Các lệnh tải chạy trực tiếp từ Internet có rủi ro chuỗi cung ứng.

---

# Lịch sử: DUYFIX v1.5 — Interactive menu

Chạy từ CMD (hoặc PowerShell) bằng một lệnh; mặc định mở menu 7 chức năng:

```cmd
powershell -nop -c "iex (irm https://raw.githubusercontent.com/duymunn/DUYFIX/main/DuyFix.ps1)"
```

Các chức năng trong bản 1.5:
1. Active Windows: chỉ chẩn đoán trạng thái/license và C020/C008; chưa kích hoạt
2. Active Office: liệt kê phần mềm Office, thử đọc license với OSPP.VBS nếu có; chưa kích hoạt
3. Xóa Windows key/crack: xem trước, không xóa
4. Xóa Office key/crack: xem trước, không xóa
5. Gỡ Office: liệt kê từ uninstall registry, chọn một hoặc ALL (xem trước), chưa gỡ
6. Gỡ WPS Office: phát hiện từ uninstall registry, chưa gỡ
7. Gỡ phần mềm 360: phát hiện từ uninstall registry, chưa gỡ

0. Thoát.

Đây là **bản menu/preview**, không thực hiện xóa key, file, task, service hoặc gỡ cài đặt. Hãy kiểm tra danh sách nhận diện trước khi thêm các thao tác xóa có xác nhận, sao lưu và biện pháp khôi phục. Bộ lọc danh sách phần mềm không bảo đảm phát hiện mọi loại cài đặt, đặc biệt ứng dụng Store, bản portable và thành phần lỗi.

Các chế độ riêng của script vẫn có: `--dry-run`, `--api-test`, `--cid-test`, `--self-test`. Không thử nghiệm CID thật hay kích hoạt Windows/Office ở bản menu này.

**Bảo mật:** Script tải và thực thi nội dung mới nhất trên `main`; kiểm tra nội dung mã nguồn trước khi chạy. Không được đưa API Key cá nhân lên repository. Dùng git commit cố định khi phát hành bản cho khách. Phần mềm có thể chạy trong RAM nhưng hệ thống vẫn có thể lưu nhật ký bảo mật.

---

# DUYFIX v1.5

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
