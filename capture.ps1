$ErrorActionPreference = 'Stop'
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

    # ==========================================
    # TA専用ロック画面（USB物理キー検知版）
    # ==========================================
    function Show-LockScreen {
        $KEY_FILENAME = "nklab_unlock.key"
        $form = New-Object System.Windows.Forms.Form
        $form.Size = New-Object System.Drawing.Size(900, 450)
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None 
        $form.TopMost = $true
        $form.BackColor = [System.Drawing.Color]::DarkRed
        $form.ShowInTaskbar = $false

        $lblTitle = New-Object System.Windows.Forms.Label
        $lblTitle.Text = "【警告】インターネット接続を検知しました"
        $lblTitle.Font = New-Object System.Drawing.Font("Meiryo UI", 28, [System.Drawing.FontStyle]::Bold)
        $lblTitle.ForeColor = [System.Drawing.Color]::Yellow
        $lblTitle.AutoSize = $true
        $lblTitle.Location = New-Object System.Drawing.Point(50, 50)
        $form.Controls.Add($lblTitle)

        $lblMsg = New-Object System.Windows.Forms.Label
        $lblMsg.Text = "ただちに試験監督（TA）を呼んでください．`nこの画面はTA専用の【解除用USBメモリ】を挿入するまで閉じられません．"
        $lblMsg.Font = New-Object System.Drawing.Font("Meiryo UI", 16, [System.Drawing.FontStyle]::Bold)
        $lblMsg.ForeColor = [System.Drawing.Color]::White
        $lblMsg.AutoSize = $true
        $lblMsg.Location = New-Object System.Drawing.Point(55, 140)
        $form.Controls.Add($lblMsg)

        $script:isLocked = $true
        $usbTimer = New-Object System.Windows.Forms.Timer
        $usbTimer.Interval = 1000
        $usbTimer.Add_Tick({
            try {
                $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady }
                foreach ($drive in $drives) {
                    $keyPath = Join-Path -Path $drive.RootDirectory.FullName -ChildPath $KEY_FILENAME
                    if (Test-Path $keyPath) {
                        $usbTimer.Stop()
                        $script:isLocked = $false
                        $form.Close()
                        break
                    }
                }
            } catch {}
        })
        $form.Add_FormClosing({ if ($script:isLocked) { $_.Cancel = $true } })
        $usbTimer.Start()
        [void]$form.ShowDialog()
        $usbTimer.Stop()
    }
    
    $baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"
    $subDir = Get-ChildItem -Path $baseDir -Directory -Force | Select-Object -First 1
    
    if ($subDir) {
        $saveDir = $subDir.FullName
        $studentId = $subDir.Name.Split('_')[0]
    } else {
        $saveDir = $baseDir
        $studentId = "Unknown"
    }
    
    # ==========================================
    # 文字サイズを自動計算してバーの幅を決定
    # ==========================================
    $textFont = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
    # 最も文字数が多くなる状態を想定して長さを測定する
    $dummyText = "  [$studentId] 監視中: 999枚 (23:59)  "
    $textSize = [System.Windows.Forms.TextRenderer]::MeasureText($dummyText, $textFont)
    # 余裕を持たせた横幅をピクセルで取得
    $formWidth = $textSize.Width + 10 

    $form = New-Object System.Windows.Forms.Form
    $form.Size = New-Object System.Drawing.Size($formWidth, 22)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    # 自動計算した横幅をもとに、画面の中央位置も完璧に合わせる
    $form.Location = New-Object System.Drawing.Point(([int]([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width/2) - [int]($formWidth/2)), 0)
    $form.BackColor = [System.Drawing.Color]::Black
    
    $label = New-Object System.Windows.Forms.Label
    $label.ForeColor = [System.Drawing.Color]::Yellow
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.Font = $textFont
    $label.Text = "[$studentId] キャプチャ準備中"
    $form.Controls.Add($label)
    $form.Add_FormClosing({
        $_.Cancel = $true
    })

    $form.Show()
    
    $style = [Win32]::GetWindowLong($form.Handle, [Win32]::GWL_EXSTYLE)
    [void][Win32]::SetWindowLong($form.Handle, [Win32]::GWL_EXSTYLE, $style -bor [Win32]::WS_EX_LAYERED -bor [Win32]::WS_EX_TRANSPARENT)
    [void][Win32]::SetLayeredWindowAttributes($form.Handle, 0, 150, [Win32]::LWA_ALPHA)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 100 
    $timer.Add_Tick({
        [void][Win32]::SetWindowPos($form.Handle, -1, 0, 0, 0, 0, 3)
        $pt = [System.Windows.Forms.Cursor]::Position
        $isHover = ($pt.X -ge $form.Left -and $pt.X -le ($form.Left + $form.Width) -and $pt.Y -ge $form.Top -and $pt.Y -le ($form.Top + $form.Height))
        if ($isHover) {
            [void][Win32]::SetLayeredWindowAttributes($form.Handle, 0, 10, [Win32]::LWA_ALPHA)
        } else {
            [void][Win32]::SetLayeredWindowAttributes($form.Handle, 0, 150, [Win32]::LWA_ALPHA)
        }
    })
    $timer.Start()
    
    # ==========================================
    # 独立デュアル監視アーキテクチャ
    # ==========================================
    $nextCaptureTime = Get-Date
    $nextPingTime = Get-Date

    while($true){ 
        $now = Get-Date

        # --- 1. 画面キャプチャ処理 ---
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
                if ($totalW -eq 0 -or $totalH -eq 0) {
                    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                    $totalW = $bounds.Width; $totalH = $bounds.Height
                    $minX = $bounds.X; $minY = $bounds.Y
                }
                $boundsSize = New-Object System.Drawing.Size($totalW, $totalH)
                $bmp = New-Object System.Drawing.Bitmap($totalW, $totalH)
                $graphics = [System.Drawing.Graphics]::FromImage($bmp)
                $graphics.CopyFromScreen($minX, $minY, 0, 0, $boundsSize)
                
                $count = @(Get-ChildItem -Path $saveDir -Filter "*.jpg" -ErrorAction SilentlyContinue).Count + 1
                $timestamp = Get-Date -Format 'HHmmss'
                $countStr = "{0:D2}" -f $count
                $fileName = "${studentId}_${countStr}_${timestamp}.jpg"
                $filePath = Join-Path -Path $saveDir -ChildPath $fileName
                $bmp.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                
                $label.Text = "[$studentId] 試験中: $($count)枚 ($(Get-Date -Format 'HH:mm'))"
                $graphics.Dispose(); $bmp.Dispose()
            } catch {
                $errMsg = "Capture Error at $(Get-Date): $_"
                $errMsg | Out-File "$([Environment]::GetFolderPath('Desktop'))\capture_error.log" -Append
            }
            $nextCaptureTime = (Get-Date).AddSeconds((Get-Random -Minimum 0 -Maximum 60))
        }

        # --- 2. Pingによるネット監視 ---
        if ($now -ge $nextPingTime) {
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send("8.8.8.8", 1000)
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $logTime = Get-Date -Format 'HH:mm:ss'
                    $logMsg = "[$logTime] インターネット接続を検知しました．"
                    $logMsg | Out-File "$saveDir\network_warning.log" -Append -Encoding UTF8
                    Show-LockScreen
                }
            } catch {}
            $nextPingTime = (Get-Date).AddSeconds(5)
        }
        
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 1000
    }
} catch { (Get-Date).ToString() + " Fatal: $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\debug.log" -Append }