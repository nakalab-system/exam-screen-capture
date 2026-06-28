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
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
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
        $lockForm.Size = New-Object System.Drawing.Size(980, 600)
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
        $lblTitle.MaximumSize = New-Object System.Drawing.Size(880, 0)
        $lblTitle.Location = New-Object System.Drawing.Point(45, 40)
        $lockForm.Controls.Add($lblTitle)

        $lblMsgStudent = New-Object System.Windows.Forms.Label
        $lblMsgStudent.Text = "ただちにTA（試験監督）を呼んでください．`r`n※TAが到着するまで，PCには一切触れないでください．"
        $lblMsgStudent.Font = New-Object System.Drawing.Font("Meiryo UI", 18, [System.Drawing.FontStyle]::Bold)
        $lblMsgStudent.ForeColor = [System.Drawing.Color]::White
        $lblMsgStudent.AutoSize = $true
        $lblMsgStudent.MaximumSize = New-Object System.Drawing.Size(880, 0)
        $lblMsgStudent.Location = New-Object System.Drawing.Point(50, 140)
        $lockForm.Controls.Add($lblMsgStudent)

        $lblMsgTa = New-Object System.Windows.Forms.Label
        $lblMsgTa.Text = "【TA用操作ガイド】`r`n・「背景を透かす」を長押しすると，背後の画面状況（不正の有無など）を確認できます．`r`n・Wi-Fi切断後にPIN解除をしてください．"
        $lblMsgTa.Font = New-Object System.Drawing.Font("Meiryo UI", 12, [System.Drawing.FontStyle]::Regular)
        $lblMsgTa.ForeColor = [System.Drawing.Color]::LightYellow
        $lblMsgTa.AutoSize = $true
        $lblMsgTa.MaximumSize = New-Object System.Drawing.Size(880, 0)
        $lblMsgTa.Location = New-Object System.Drawing.Point(50, 240)
        $lockForm.Controls.Add($lblMsgTa)

        $lblStatus = New-Object System.Windows.Forms.Label
        $lblStatus.Text = "状態: TA用USB待機中"
        $lblStatus.Font = New-Object System.Drawing.Font("Meiryo UI", 12, [System.Drawing.FontStyle]::Regular)
        $lblStatus.ForeColor = [System.Drawing.Color]::LightGray
        $lblStatus.AutoSize = $true
        $lblStatus.MaximumSize = New-Object System.Drawing.Size(880, 0)
        $lblStatus.Location = New-Object System.Drawing.Point(50, 360)
        $lockForm.Controls.Add($lblStatus)

        $lblPin = New-Object System.Windows.Forms.Label
        $lblPin.Text = "PIN :"
        $lblPin.Font = New-Object System.Drawing.Font("Meiryo UI", 16, [System.Drawing.FontStyle]::Bold)
        $lblPin.ForeColor = [System.Drawing.Color]::White
        $lblPin.AutoSize = $true
        $lblPin.Location = New-Object System.Drawing.Point(50, 440)
        $lockForm.Controls.Add($lblPin)

        $tbPin = New-Object System.Windows.Forms.TextBox
        $tbPin.Font = New-Object System.Drawing.Font("Meiryo UI", 16, [System.Drawing.FontStyle]::Regular)
        $tbPin.Size = New-Object System.Drawing.Size(250, 35)
        $tbPin.Location = New-Object System.Drawing.Point(180, 437)
        $tbPin.UseSystemPasswordChar = $true
        $lockForm.Controls.Add($tbPin)

        $btnSubmit = New-Object System.Windows.Forms.Button
        $btnSubmit.Text = "TA解除を実行"
        $btnSubmit.Font = New-Object System.Drawing.Font("Meiryo UI", 14, [System.Drawing.FontStyle]::Bold)
        $btnSubmit.Size = New-Object System.Drawing.Size(200, 40)
        $btnSubmit.Location = New-Object System.Drawing.Point(450, 435)
        $btnSubmit.BackColor = [System.Drawing.Color]::White
        $btnSubmit.ForeColor = [System.Drawing.Color]::Black
        $lockForm.Controls.Add($btnSubmit)

        $btnPeek = New-Object System.Windows.Forms.Button
        $btnPeek.Text = "背景透過"
        $btnPeek.Font = New-Object System.Drawing.Font("Meiryo UI", 12, [System.Drawing.FontStyle]::Bold)
        $btnPeek.Size = New-Object System.Drawing.Size(240, 40)
        $btnPeek.Location = New-Object System.Drawing.Point(670, 435)
        $btnPeek.BackColor = [System.Drawing.Color]::Gray
        $btnPeek.ForeColor = [System.Drawing.Color]::White
        $lockForm.Controls.Add($btnPeek)

        $btnPeek.Add_MouseDown({ $lockForm.Opacity = 0.1 })
        $btnPeek.Add_MouseUp({ $lockForm.Opacity = 1.0 })
        $btnPeek.Add_MouseLeave({ $lockForm.Opacity = 1.0 }) 

        $lockForm.AcceptButton = $btnSubmit

        $script:isLocked = $true
        $script:unlockBusy = $false

        $btnSubmit.Add_Click({
            if ($script:unlockBusy) { return }
            
            if ($REQUIRE_PIN -and [string]::IsNullOrWhiteSpace($tbPin.Text)) {
                $lblStatus.Text = "状態: PINを入力してください"
                return
            }

            $script:unlockBusy = $true
            $btnSubmit.Enabled = $false 
            $tbPin.Enabled = $false
            
            try {
                $lblStatus.Text = "状態: 検証中..."
                $lblStatus.ForeColor = [System.Drawing.Color]::Yellow
                [System.Windows.Forms.Application]::DoEvents()

                if (Test-TaUsbUnlock -Pin $tbPin.Text) {
                    $lblStatus.Text = "状態: 解除成功"
                    $lblStatus.ForeColor = [System.Drawing.Color]::LimeGreen
                    $script:isLocked = $false
                    Start-Sleep -Milliseconds 500
                    $lockForm.Close()
                } else {
                    $lblStatus.Text = "状態: 解除失敗（USBが挿入されていないか，PINが間違っています）"
                    $lblStatus.ForeColor = [System.Drawing.Color]::LightPink
                    $tbPin.Text = "" 
                }
            } finally {
                $script:unlockBusy = $false
                $btnSubmit.Enabled = $true
                $tbPin.Enabled = $true
                $tbPin.Focus()
            }
        })

        $lockForm.Add_FormClosing({
            if ($script:isLocked) { $_.Cancel = $true }
        })

        $lockForm.Add_Shown({
            $lockForm.Activate()
            [Win32]::SetForegroundWindow($lockForm.Handle)
            $tbPin.Select()
            $tbPin.Focus()
        })

        [void]$lockForm.ShowDialog()
    }

    # ==========================================
    # ディレクトリ・学籍番号等の初期化 (フォルダ名・ZIP名による完全一致ロジック)
    # ==========================================
    $script:baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"
    
    # 完全に「今日の日付（YYYYMMDD）」の文字列のみを使用する（過去の許容を一切廃止）
    $todayStr = Get-Date -Format "yyyyMMdd"
    $targetFolder = $null
    $foundStudentId = "Unknown"

    $allFolders = @(Get-ChildItem -Path $script:baseDir -Directory -Force -ErrorAction SilentlyContinue)

    foreach ($f in $allFolders) {
        # 1. フォルダ名が「学籍番号_今日の日付(8桁)」に完全に一致するか？
        if ($f.Name -match "^([A-Za-z0-9]+)_($todayStr)$") {
            $sid = $matches[1]

            # 2. そのフォルダ内に「学籍番号_今日の日付_時刻(6桁).zip」が存在するか？
            $zips = @(Get-ChildItem -Path $f.FullName -Filter "${sid}_${todayStr}_*.zip" -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -match "^${sid}_${todayStr}_[0-9]{6}\.zip$" })

            # フォルダ名もZIP名も完全に今日の日付を満たす場合のみ、「本日の正規フォルダ」とする
            if ($zips.Count -gt 0) {
                $targetFolder = $f
                $foundStudentId = $sid
                break
            }
        }
    }

    # 保存先と学籍番号の決定
    if ($targetFolder) {
        $script:saveDir = $targetFolder.FullName
        $script:studentId = $foundStudentId
    } else {
        # 該当しない場合（テスト開始前など）はベースディレクトリを利用し、学籍番号はUnknownとする
        $script:saveDir = $script:baseDir
        $script:studentId = "Unknown"
    }

    # 枚数カウント：学籍番号に合致する画像のみをカウントし、過去のUnknownデータなどを誤検知させない
    [int]$script:captureCount = @(Get-ChildItem -Path $script:saveDir -Filter "${script:studentId}_*.jpg" -File -ErrorAction SilentlyContinue).Count


    # ==========================================
    # バーの横幅計算・UI初期化
    # ==========================================
    $textFont = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
    $dummyText = "  [$($script:studentId)] 試験中: 999枚 (23:59)  " 
    $textSize = [System.Windows.Forms.TextRenderer]::MeasureText($dummyText, $textFont)
    $formWidth = $textSize.Width + 30

    $initialText = "[{0}] 試験中: {1}枚 ({2})" -f $script:studentId, $script:captureCount, (Get-Date -Format 'HH:mm')

    $script:barForm = New-Object System.Windows.Forms.Form
    $script:barForm.Size = New-Object System.Drawing.Size($formWidth, 22)
    $script:barForm.FormBorderStyle = "None"
    $script:barForm.TopMost = $true
    $script:barForm.ShowInTaskbar = $false
    $script:barForm.StartPosition = "Manual"
    $script:barForm.Location = New-Object System.Drawing.Point(([int]([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width / 2) - [int]($formWidth / 2)), 0)
    $script:barForm.BackColor = [System.Drawing.Color]::Black

    $script:label = New-Object System.Windows.Forms.Label
    $script:label.ForeColor = [System.Drawing.Color]::Yellow
    $script:label.Dock = "Fill"
    $script:label.TextAlign = "MiddleCenter"
    $script:label.Font = $textFont
    $script:label.Text = $initialText
    $script:barForm.Controls.Add($script:label)

    $script:barForm.Add_FormClosing({ $_.Cancel = $true })
    $script:barForm.Show()

    $style = [Win32]::GetWindowLong($script:barForm.Handle, [Win32]::GWL_EXSTYLE)
    [void][Win32]::SetWindowLong($script:barForm.Handle, [Win32]::GWL_EXSTYLE, $style -bor [Win32]::WS_EX_LAYERED -bor [Win32]::WS_EX_TRANSPARENT)
    [void][Win32]::SetLayeredWindowAttributes($script:barForm.Handle, 0, 150, [Win32]::LWA_ALPHA)

    # ホバー時の半透明化タイマー
    $hoverTimer = New-Object System.Windows.Forms.Timer
    $hoverTimer.Interval = 100 
    $hoverTimer.Add_Tick({
        [void][Win32]::SetWindowPos($script:barForm.Handle, -1, 0, 0, 0, 0, 19)
        $pt = [System.Windows.Forms.Cursor]::Position
        $isHover = ($pt.X -ge $script:barForm.Left -and $pt.X -le ($script:barForm.Left + $script:barForm.Width) -and $pt.Y -ge $script:barForm.Top -and $pt.Y -le ($script:barForm.Top + $script:barForm.Height))
        if ($isHover) {
            [void][Win32]::SetLayeredWindowAttributes($script:barForm.Handle, 0, 10, [Win32]::LWA_ALPHA)
        } else {
            [void][Win32]::SetLayeredWindowAttributes($script:barForm.Handle, 0, 150, [Win32]::LWA_ALPHA)
        }
    })
    $hoverTimer.Start()

    # ==========================================
    # 画面キャプチャ専用タイマー
    # ==========================================
    $script:nextCaptureTime = Get-Date
    $captureTimer = New-Object System.Windows.Forms.Timer
    $captureTimer.Interval = 1000 # 1秒ごとに実行
    $captureTimer.Add_Tick({
        $now = Get-Date
        
        $script:label.Text = "[{0}] 試験中: {1}枚 ({2})" -f $script:studentId, $script:captureCount, $now.ToString('HH:mm')

        # キャプチャ予定時刻を過ぎていたら撮影開始
        if ($now -ge $script:nextCaptureTime) {
            try {
                $minX = 0; $minY = 0; $maxX = 0; $maxY = 0
                foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
                    if ($screen.Bounds.X -lt $minX) { $minX = $screen.Bounds.X }
                    if ($screen.Bounds.Y -lt $minY) { $minY = $screen.Bounds.Y }
                    if (($screen.Bounds.X + $screen.Bounds.Width) -gt $maxX) { $maxX = ($screen.Bounds.X + $screen.Bounds.Width) }
                    if (($screen.Bounds.Y + $screen.Bounds.Height) -gt $maxY) { $maxY = ($screen.Bounds.Y + $screen.Bounds.Height) }
                }
                $totalW = $maxX - $minX; $totalH = $maxY - $minY
                
                if ($totalW -eq 0 -or $totalH -eq 0) {
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    $totalW = $bounds.Width; $totalH = $bounds.Height
                    $minX = $bounds.X; $minY = $bounds.Y
                }
                
                $boundsSize = New-Object System.Drawing.Size($totalW, $totalH)
                $bmp = New-Object System.Drawing.Bitmap($totalW, $totalH)
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.CopyFromScreen($minX, $minY, 0, 0, $boundsSize)

                # 枚数カウントアップと保存
                $script:captureCount++
                $timestamp = $now.ToString('HHmmss')
                $countStr = "{0:D3}" -f $script:captureCount
                $fileName = "{0}_{1}_{2}.jpg" -f $script:studentId, $countStr, $timestamp
                $filePath = Join-Path $script:saveDir $fileName
                $bmp.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Jpeg)

                # 撮影直後にもう一度ラベル更新
                $script:label.Text = "[{0}] 試験中: {1}枚 ({2})" -f $script:studentId, $script:captureCount, $now.ToString('HH:mm')

                $g.Dispose(); $bmp.Dispose()
            } catch {
                "Capture Error at $($now.ToString()): $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\capture_error.log" -Append -Encoding UTF8
            }

            # 次回の撮影時間をランダム設定
            $script:nextCaptureTime = $now.AddSeconds((Get-Random -Minimum 1 -Maximum 60))
        }
    })
    $captureTimer.Start()

    # ==========================================
    # メインループ (ネットワーク監視専用)
    # ==========================================
    $nextPingTime = Get-Date

    while ($true) {
        $now = Get-Date
        if ($now -ge $nextPingTime) {
            try {
                if (Test-InternetConnectivity) {
                    "[$(Get-Date -Format 'HH:mm:ss')] インターネット接続を検知" | Out-File "$script:saveDir\network_warning.log" -Append -Encoding UTF8
                    Show-LockScreen
                }
            } catch {}
            
            $nextPingTime = (Get-Date).AddSeconds((Get-Random -Minimum 1 -Maximum 11))
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 500
    }

} catch {
    (Get-Date).ToString() + " Fatal: $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\debug.log" -Append -Encoding UTF8
}