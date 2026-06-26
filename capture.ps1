$ErrorActionPreference = 'Stop'

# DPI対応
$pinvoke = @"
using System;
using System.Runtime.InteropServices;
public class DpiAware {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
Add-Type -TypeDefinition $pinvoke
[DpiAware]::SetProcessDPIAware()

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    # Win32 helper
    $win32 = @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    public const int WS_EX_LAYERED = 0x80000;
    public const int WS_EX_TRANSPARENT = 0x20;
    public const int GWL_EXSTYLE = -20;
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);
    [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd, uint crKey, byte bAlpha, uint dwFlags);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    public const int LWA_ALPHA = 0x2;
}
"@
    Add-Type -TypeDefinition $win32

    # =========================================================
    # 設定
    # =========================================================
    $KEY_FILENAME = "TA_unlock.key"
    $PFX_FILENAME = "ta_unlock.pfx"

    # make_ta_usb.ps1 で最後に出た拇印
    $ALLOWED_CERT_THUMBPRINT = "78B8D5AB594E14DEA918FB22BC126953D26407AC"

    # PIN要求（推奨）
    $REQUIRE_PIN = $true

    # ロック連打防止
    $lockCooldownSeconds = 30

    # =========================================================
    # 接続判定
    # =========================================================
    function Test-InternetConnectivity {
        param([int]$TimeoutMs = 1000)

        $okPing = $false
        $okDns  = $false
        $okHttp = $false

        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send("8.8.8.8", $TimeoutMs)
            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $okPing = $true }
        } catch {}

        try {
            $null = [System.Net.Dns]::GetHostAddresses("www.google.com")
            $okDns = $true
        } catch {}

        try {
            $resp = Invoke-WebRequest -Uri "http://clients3.google.com/generate_204" -Method Get -TimeoutSec 3 -UseBasicParsing
            if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) { $okHttp = $true }
        } catch {}

        $score = 0
        if ($okPing) { $score++ }
        if ($okDns)  { $score++ }
        if ($okHttp) { $score++ }

        return ($score -ge 2)
    }

    # =========================================================
    # TA USB解除（Thumbprint照合）
    # =========================================================
    function Normalize-Thumbprint {
        param([string]$s)
        if ([string]::IsNullOrWhiteSpace($s)) { return "" }
        return (($s -replace "[^0-9A-Fa-f]", "").ToUpper())
    }

    function Read-PinMasked {
        param([string]$Prompt = "TA PINを入力してください")
        try {
            $sec = Read-Host $Prompt -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        } catch {
            return ""
        }
    }

    function Test-TaUsbUnlock {
        try {
            $target = Normalize-Thumbprint $ALLOWED_CERT_THUMBPRINT
            if ([string]::IsNullOrWhiteSpace($target)) { return $false }

            $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady }

            foreach ($d in $drives) {
                $root = $d.RootDirectory.FullName
                $keyPath = Join-Path -Path $root -ChildPath $KEY_FILENAME
                $pfxPath = Join-Path -Path $root -ChildPath $PFX_FILENAME

                # 両方必要
                if (-not (Test-Path $keyPath)) { continue }
                if (-not (Test-Path $pfxPath)) { continue }

                $pin = ""
                if ($REQUIRE_PIN) {
                    $pin = Read-PinMasked -Prompt "TA PIN（解除用USB）"
                    if ([string]::IsNullOrWhiteSpace($pin)) { continue }
                }

                try {
                    # PS5.1でも使える形
                    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
                    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, $pin, $flags)

                    $tp = Normalize-Thumbprint $cert.Thumbprint
                    if ($tp -eq $target) {
                        return $true
                    }
                } catch {
                    continue
                }
            }
        } catch {}
        return $false
    }

    # =========================================================
    # ロック画面
    # =========================================================
    function Show-LockScreen {
        $lockForm = New-Object System.Windows.Forms.Form
        $lockForm.Size = New-Object System.Drawing.Size(980, 500)
        $lockForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $lockForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $lockForm.TopMost = $true
        $lockForm.BackColor = [System.Drawing.Color]::DarkRed
        $lockForm.ShowInTaskbar = $false

        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = "【警告】インターネット接続を検知しました"
        $lblTitle.Font = New-Object System.Drawing.Font("Meiryo UI", 28, [System.Drawing.FontStyle]::Bold)
        $lblTitle.ForeColor = [System.Drawing.Color]::Yellow
        $lblTitle.AutoSize = $true
        $lblTitle.Location = New-Object System.Drawing.Point(45, 45)
        $lockForm.Controls.Add($lblTitle)

        $lblMsg = New-Object System.Windows.Forms.Label
        $lblMsg.Text = "ただちに試験監督（TA）を呼んでください。`nこの画面はTA専用USBでのみ解除されます。"
        $lblMsg.Font = New-Object System.Drawing.Font("Meiryo UI", 16, [System.Drawing.FontStyle]::Bold)
        $lblMsg.ForeColor = [System.Drawing.Color]::White
        $lblMsg.AutoSize = $true
        $lblMsg.Location = New-Object System.Drawing.Point(50, 140)
        $lockForm.Controls.Add($lblMsg)

        $lblHint = New-Object System.Windows.Forms.Label
        $lblHint.Text = "TA操作: TA_unlock.key + ta_unlock.pfx を含むUSBを挿入し、PINを入力してください。"
        $lblHint.Font = New-Object System.Drawing.Font("Meiryo UI", 12, [System.Drawing.FontStyle]::Regular)
        $lblHint.ForeColor = [System.Drawing.Color]::Gainsboro
        $lblHint.AutoSize = $true
        $lblHint.Location = New-Object System.Drawing.Point(50, 235)
        $lockForm.Controls.Add($lblHint)

        $script:isLocked = $true

        $usbTimer = New-Object System.Windows.Forms.Timer
        $usbTimer.Interval = 1000
        $usbTimer.Add_Tick({
            try {
                if (Test-TaUsbUnlock) {
                    $usbTimer.Stop()
                    $script:isLocked = $false
                    $lockForm.Close()
                }
            } catch {}
        })

        $lockForm.Add_FormClosing({
            if ($script:isLocked) { $_.Cancel = $true }
        })

        $usbTimer.Start()
        [void]$lockForm.ShowDialog()
        $usbTimer.Stop()
    }

    # =========================================================
    # 保存先検出（厳密）
    # =========================================================
    $baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"

    $subDir = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^([0-9]{8})_([0-9]{8})$" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($subDir) {
        $saveDir = $subDir.FullName
        [void]($subDir.Name -match "^([0-9]{8})_([0-9]{8})$")
        $studentId = $matches[1]
    } else {
        $saveDir = $baseDir
        $studentId = "Unknown"
    }

    # =========================================================
    # 上部監視バー
    # =========================================================
    $textFont = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
    $dummyText = "  [$studentId] 監視中: 999枚 (23:59)  "
    $textSize = [System.Windows.Forms.TextRenderer]::MeasureText($dummyText, $textFont)
    $formWidth = $textSize.Width + 10

    $barForm = New-Object System.Windows.Forms.Form
    $barForm.Size = New-Object System.Drawing.Size($formWidth, 22)
    $barForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $barForm.TopMost = $true
    $barForm.ShowInTaskbar = $false
    $barForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $barForm.Location = New-Object System.Drawing.Point(
        ([int]([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / 2) - [int]($formWidth / 2)),
        0
    )
    $barForm.BackColor = [System.Drawing.Color]::Black

    $label = New-Object System.Windows.Forms.Label
    $label.ForeColor = [System.Drawing.Color]::Yellow
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.Font = $textFont
    $label.Text = "[$studentId] キャプチャ準備中"
    $barForm.Controls.Add($label)

    $barForm.Add_FormClosing({ $_.Cancel = $true })
    $barForm.Show()

    $style = [Win32]::GetWindowLong($barForm.Handle, [Win32]::GWL_EXSTYLE)
    [void][Win32]::SetWindowLong($barForm.Handle, [Win32]::GWL_EXSTYLE, $style -bor [Win32]::WS_EX_LAYERED -bor [Win32]::WS_EX_TRANSPARENT)
    [void][Win32]::SetLayeredWindowAttributes($barForm.Handle, 0, 150, [Win32]::LWA_ALPHA)

    $barTimer = New-Object System.Windows.Forms.Timer
    $barTimer.Interval = 100
    $barTimer.Add_Tick({
        [void][Win32]::SetWindowPos($barForm.Handle, -1, 0, 0, 0, 0, 3)

        $pt = [System.Windows.Forms.Cursor]::Position
        $isHover = (
            $pt.X -ge $barForm.Left -and
            $pt.X -le ($barForm.Left + $barForm.Width) -and
            $pt.Y -ge $barForm.Top -and
            $pt.Y -le ($barForm.Top + $barForm.Height)
        )

        if ($isHover) {
            [void][Win32]::SetLayeredWindowAttributes($barForm.Handle, 0, 10, [Win32]::LWA_ALPHA)
        } else {
            [void][Win32]::SetLayeredWindowAttributes($barForm.Handle, 0, 150, [Win32]::LWA_ALPHA)
        }
    })
    $barTimer.Start()

    # =========================================================
    # メインループ
    # =========================================================
    $nextCaptureTime = Get-Date
    $nextPingTime = Get-Date
    $lastLockTriggeredAt = [datetime]::MinValue

    while ($true) {
        $now = Get-Date

        # 1) キャプチャ
        if ($now -ge $nextCaptureTime) {
            try {
                $minX = 0; $minY = 0; $maxX = 0; $maxY = 0
                foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
                    if ($screen.Bounds.X -lt $minX) { $minX = $screen.Bounds.X }
                    if ($screen.Bounds.Y -lt $minY) { $minY = $screen.Bounds.Y }
                    if (($screen.Bounds.X + $screen.Bounds.Width) -gt $maxX) { $maxX = ($screen.Bounds.X + $screen.Bounds.Width) }
                    if (($screen.Bounds.Y + $screen.Bounds.Height) -gt $maxY) { $maxY = ($screen.Bounds.Y + $screen.Bounds.Height) }
                }

                $totalW = $maxX - $minX
                $totalH = $maxY - $minY

                if ($totalW -eq 0 -or $totalH -eq 0) {
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    $totalW = $bounds.Width
                    $totalH = $bounds.Height
                    $minX = $bounds.X
                    $minY = $bounds.Y
                }

                $boundsSize = New-Object System.Drawing.Size($totalW, $totalH)
                $bmp = New-Object System.Drawing.Bitmap($totalW, $totalH)
                $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                $graphics.CopyFromScreen($minX, $minY, 0, 0, $boundsSize)

                $count = @(Get-ChildItem -Path $saveDir -Filter "*.jpg" -ErrorAction SilentlyContinue).Count + 1
                $timestamp = Get-Date -Format 'HHmmss'
                $countStr = "{0:D3}" -f $count
                $fileName = "${studentId}_${countStr}_${timestamp}.jpg"
                $filePath = Join-Path -Path $saveDir -ChildPath $fileName

                $bmp.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Jpeg)

                $label.Text = "[$studentId] 試験中: $count枚 ($(Get-Date -Format 'HH:mm'))"

                $graphics.Dispose()
                $bmp.Dispose()
            } catch {
                $errMsg = "Capture Error at $(Get-Date): $_"
                $errMsg | Out-File "$([Environment]::GetFolderPath('Desktop'))\capture_error.log" -Append -Encoding UTF8
            }

            # 0〜59秒ランダム
            $nextCaptureTime = (Get-Date).AddSeconds((Get-Random -Minimum 0 -Maximum 60))
        }

        # 2) ネット監視（1〜10秒ランダム）
        if ($now -ge $nextPingTime) {
            try {
                $inCooldown = (($now - $lastLockTriggeredAt).TotalSeconds -lt $lockCooldownSeconds)

                if (-not $inCooldown) {
                    if (Test-InternetConnectivity) {
                        $logTime = Get-Date -Format 'HH:mm:ss'
                        $logMsg = "[$logTime] インターネット接続を検知しました。(Ping/DNS/HTTP 複合判定)"
                        $logMsg | Out-File "$saveDir\network_warning.log" -Append -Encoding UTF8

                        $lastLockTriggeredAt = Get-Date
                        Show-LockScreen
                    }
                }
            } catch {}

            $nextPingTime = (Get-Date).AddSeconds((Get-Random -Minimum 1 -Maximum 11)) # 1〜10秒
        }

        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 1000
    }

} catch {
    (Get-Date).ToString() + " Fatal: $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\debug.log" -Append -Encoding UTF8
}