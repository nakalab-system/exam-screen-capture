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

    # =========================
    # 設定
    # =========================
    $KEY_FILENAME = "TA_unlock.key"
    $PFX_FILENAME = "ta_unlock.pfx"
    $ALLOWED_CERT_THUMBPRINT = "78B8D5AB594E14DEA918FB22BC126953D26407AC"
    $REQUIRE_PIN = $true
    $lockCooldownSeconds = 30

    function Normalize-Thumbprint {
        param([string]$s)
        if ([string]::IsNullOrWhiteSpace($s)) { return "" }
        return (($s -replace "[^0-9A-Fa-f]", "").ToUpper())
    }

    function Test-InternetConnectivity {
        param([int]$TimeoutMs = 1000)

        $okPing = $false; $okDns = $false; $okHttp = $false

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

    function Show-PinDialog {
        param([string]$Title = "TA PIN入力", [string]$Message = "TA PINを入力してください")

        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = $Title
        $dlg.Size = New-Object System.Drawing.Size(420, 180)
        $dlg.StartPosition = "CenterScreen"
        $dlg.FormBorderStyle = "FixedDialog"
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.TopMost = $true
        $dlg.ShowInTaskbar = $false

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $Message
        $lbl.AutoSize = $true
        $lbl.Location = New-Object System.Drawing.Point(20, 20)
        $dlg.Controls.Add($lbl)

        $tb = New-Object System.Windows.Forms.TextBox
        $tb.Location = New-Object System.Drawing.Point(20, 50)
        $tb.Size = New-Object System.Drawing.Size(360, 24)
        $tb.UseSystemPasswordChar = $true
        $dlg.Controls.Add($tb)

        $ok = New-Object System.Windows.Forms.Button
        $ok.Text = "OK"
        $ok.Location = New-Object System.Drawing.Point(220, 90)
        $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Controls.Add($ok)

        $cancel = New-Object System.Windows.Forms.Button
        $cancel.Text = "キャンセル"
        $cancel.Location = New-Object System.Drawing.Point(305, 90)
        $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $dlg.Controls.Add($cancel)

        $dlg.AcceptButton = $ok
        $dlg.CancelButton = $cancel

        $result = $dlg.ShowDialog()
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $tb.Text }
        return $null
    }

    function Test-TaUsbUnlock {
        param([string]$Pin)

        try {
            $target = Normalize-Thumbprint $ALLOWED_CERT_THUMBPRINT
            if ([string]::IsNullOrWhiteSpace($target)) { return $false }

            $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady }
            foreach ($d in $drives) {
                $root = $d.RootDirectory.FullName
                $keyPath = Join-Path $root $KEY_FILENAME
                $pfxPath = Join-Path $root $PFX_FILENAME

                if (-not (Test-Path $keyPath)) { continue }
                if (-not (Test-Path $pfxPath)) { continue }

                try {
                    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
                    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, $Pin, $flags)
                    $tp = Normalize-Thumbprint $cert.Thumbprint
                    if ($tp -eq $target) { return $true }
                } catch {
                    continue
                }
            }
        } catch {}
        return $false
    }

    function Show-LockScreen {
        $lockForm = New-Object System.Windows.Forms.Form
        $lockForm.Size = New-Object System.Drawing.Size(980, 560)
        $lockForm.StartPosition = "CenterScreen"
        $lockForm.FormBorderStyle = "None"
        $lockForm.TopMost = $true
        $lockForm.BackColor = [System.Drawing.Color]::DarkRed
        $lockForm.ShowInTaskbar = $false

        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = "【警告】インターネット接続を検知しました"
        $lblTitle.Font = New-Object System.Drawing.Font("Meiryo UI", 28, [System.Drawing.FontStyle]::Bold)
        $lblTitle.ForeColor = [System.Drawing.Color]::Yellow
        $lblTitle.AutoSize = $true
        $lblTitle.MaximumSize = New-Object System.Drawing.Size(880, 0)   # 自動改行
        $lblTitle.Location = New-Object System.Drawing.Point(45, 40)
        $lockForm.Controls.Add($lblTitle)

        $lblStatus = New-Object System.Windows.Forms.Label
        $lblStatus.Text = "状態: TA用USB待機中"
        $lblStatus.Font = New-Object System.Drawing.Font("Meiryo UI", 12, [System.Drawing.FontStyle]::Regular)
        $lblStatus.ForeColor = [System.Drawing.Color]::White
        $lblStatus.AutoSize = $true
        $lblStatus.MaximumSize = New-Object System.Drawing.Size(880, 0)  # 自動改行
        $lblStatus.Location = New-Object System.Drawing.Point(50, 230)
        $lockForm.Controls.Add($lblStatus)

        $btnUnlock = New-Object System.Windows.Forms.Button
        $btnUnlock.Text = "TA解除を実行"
        $btnUnlock.Font = New-Object System.Drawing.Font("Meiryo UI", 14, [System.Drawing.FontStyle]::Bold)
        $btnUnlock.Size = New-Object System.Drawing.Size(260, 55)
        $btnUnlock.Location = New-Object System.Drawing.Point(50, 290)
        $lockForm.Controls.Add($btnUnlock)

        $script:isLocked = $true
        $script:unlockBusy = $false

        $btnUnlock.Add_Click({
            if ($script:unlockBusy) { return }
            $script:unlockBusy = $true
            try {
                $pin = ""
                if ($REQUIRE_PIN) {
                    $pin = Show-PinDialog -Title "TA PIN入力" -Message "TA PINを入力してください"
                    if ($null -eq $pin) {
                        $lblStatus.Text = "状態: キャンセルされました"
                        return
                    }
                }

                $lblStatus.Text = "状態: 検証中..."
                [System.Windows.Forms.Application]::DoEvents()

                if (Test-TaUsbUnlock -Pin $pin) {
                    $lblStatus.Text = "状態: 解除成功"
                    $script:isLocked = $false
                    $lockForm.Close()
                } else {
                    $lblStatus.Text = "状態: 解除失敗（USB / PIN / 証明書を確認）"
                }
            } finally {
                $script:unlockBusy = $false
            }
        })

        $lockForm.Add_FormClosing({
            if ($script:isLocked) { $_.Cancel = $true }
        })

        [void]$lockForm.ShowDialog()
    }

    # ==========================================
    # 保存先の決定と当日データチェック
    # ==========================================
    $baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"
    $today = (Get-Date).Date

    # フォルダ名が規定フォーマットで、かつ作成日または更新日が「今日」のもののみ引き継ぐ
    $subDir = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { 
            $_.Name -match "^([0-9]{8})_([0-9]{8})$" -and
            ($_.CreationTime.Date -eq $today -or $_.LastWriteTime.Date -eq $today)
        } |
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

    # 初期枚数を算出（「今日」撮影された画像ファイルのみをカウント対象にする）
    $captureCount = @(Get-ChildItem -Path $saveDir -Filter "*.jpg" -ErrorAction SilentlyContinue |
        Where-Object { $_.CreationTime.Date -eq $today -or $_.LastWriteTime.Date -eq $today }).Count

    # ==========================================
    # 文字サイズを自動計算してバーの幅を決定
    # ==========================================
    $textFont = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
    $dummyText = "  [$studentId] 試験中: 999枚 (23:59)  "
    $textSize = [System.Windows.Forms.TextRenderer]::MeasureText($dummyText, $textFont)
    $formWidth = $textSize.Width + 10
    $initialText = "[$studentId] 試験中: $($captureCount)枚 ($(Get-Date -Format 'HH:mm'))"

    $barForm = New-Object System.Windows.Forms.Form
    $barForm.Size = New-Object System.Drawing.Size($formWidth, 22)
    $barForm.FormBorderStyle = "None"
    $barForm.TopMost = $true
    $barForm.ShowInTaskbar = $false
    $barForm.StartPosition = "Manual"
    $barForm.Location = New-Object System.Drawing.Point(([int]([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / 2) - [int]($formWidth / 2)), 0)
    $barForm.BackColor = [System.Drawing.Color]::Black

    $label = New-Object System.Windows.Forms.Label
    $label.ForeColor = [System.Drawing.Color]::Yellow
    $label.Dock = "Fill"
    $label.TextAlign = "MiddleCenter"
    $label.Font = $textFont
    $label.Text = $initialText
    $barForm.Controls.Add($label)

    $barForm.Add_FormClosing({ $_.Cancel = $true })
    $barForm.Show()

    $style = [Win32]::GetWindowLong($barForm.Handle, [Win32]::GWL_EXSTYLE)
    [void][Win32]::SetWindowLong($barForm.Handle, [Win32]::GWL_EXSTYLE, $style -bor [Win32]::WS_EX_LAYERED -bor [Win32]::WS_EX_TRANSPARENT)
    [void][Win32]::SetLayeredWindowAttributes($barForm.Handle, 0, 150, [Win32]::LWA_ALPHA)

    # ==========================================
    # ホバー時の半透明化タイマー
    # ==========================================
    $hoverTimer = New-Object System.Windows.Forms.Timer
    $hoverTimer.Interval = 100 
    $hoverTimer.Add_Tick({
        [void][Win32]::SetWindowPos($barForm.Handle, -1, 0, 0, 0, 0, 3) # 常に最前面を維持
        $pt = [System.Windows.Forms.Cursor]::Position
        $isHover = ($pt.X -ge $barForm.Left -and $pt.X -le ($barForm.Left + $barForm.Width) -and $pt.Y -ge $barForm.Top -and $pt.Y -le ($barForm.Top + $barForm.Height))
        if ($isHover) {
            [void][Win32]::SetLayeredWindowAttributes($barForm.Handle, 0, 10, [Win32]::LWA_ALPHA)
        } else {
            [void][Win32]::SetLayeredWindowAttributes($barForm.Handle, 0, 150, [Win32]::LWA_ALPHA)
        }
    })
    $hoverTimer.Start()

    # ==========================================
    # メイン監視ループ
    # ==========================================
    $nextCaptureTime = Get-Date
    $nextPingTime = Get-Date
    $lastLockTriggeredAt = [datetime]::MinValue

    while ($true) {
        $now = Get-Date

        # --- 1. 画面キャプチャ処理 (マルチモニター対応) ---
        if ($now -ge $nextCaptureTime) {
            try {
                $minX = 0; $minY = 0; $maxX = 0; $maxY = 0
                foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
                    if ($screen.Bounds.X -lt $minX) { $minX = $screen.Bounds.X }
                    if ($screen.Bounds.Y -lt $minY) { $minY = $screen.Bounds.Y }
                    if (($screen.Bounds.X + $screen.Bounds.Width) -gt $maxX) { $maxX = ($screen.Bounds.X + $screen.Bounds.Width) }
                    if (($screen.Bounds.Y + $screen.Bounds.Height) -gt $maxY) { $maxY = ($screen.Bounds.Y + $screen.Bounds.Height) }
                }
                $totalW = $maxX - $minX; $totalH = $maxY - $minY
                
                # 取得失敗時のフォールバック (プライマリ画面のみ)
                if ($totalW -eq 0 -or $totalH -eq 0) {
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    $totalW = $bounds.Width; $totalH = $bounds.Height
                    $minX = $bounds.X; $minY = $bounds.Y
                }
                
                $boundsSize = New-Object System.Drawing.Size($totalW, $totalH)
                $bmp = New-Object System.Drawing.Bitmap($totalW, $totalH)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.CopyFromScreen($minX, $minY, 0, 0, $boundsSize)

                $captureCount++
                $timestamp = Get-Date -Format 'HHmmss'
                $countStr = "{0:D3}" -f $captureCount
                $fileName = "${studentId}_${countStr}_${timestamp}.jpg"
                $filePath = Join-Path $saveDir $fileName
                $bmp.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                $label.Text = "[$studentId] 試験中: $($captureCount)枚 ($(Get-Date -Format 'HH:mm'))"

                $g.Dispose(); $bmp.Dispose()
            } catch {
                "Capture Error at $(Get-Date): $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\capture_error.log" -Append -Encoding UTF8
            }

            # ランダム間隔の撮影 (1～60秒)
            $nextCaptureTime = (Get-Date).AddSeconds((Get-Random -Minimum 1 -Maximum 60))
        }

        # --- 2. ネットワーク監視処理 ---
        if ($now -ge $nextPingTime) {
            try {
                $inCooldown = (($now - $lastLockTriggeredAt).TotalSeconds -lt $lockCooldownSeconds)
                if (-not $inCooldown) {
                    if (Test-InternetConnectivity) {
                        "[$(Get-Date -Format 'HH:mm:ss')] インターネット接続を検知" | Out-File "$saveDir\network_warning.log" -Append -Encoding UTF8
                        $lastLockTriggeredAt = Get-Date
                        Show-LockScreen
                    }
                }
            } catch {}
            
            # ランダム間隔の通信チェック (1～11秒)
            $nextPingTime = (Get-Date).AddSeconds((Get-Random -Minimum 1 -Maximum 11))
        }

        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 500
    }

} catch {
    (Get-Date).ToString() + " Fatal: $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\debug.log" -Append -Encoding UTF8
}