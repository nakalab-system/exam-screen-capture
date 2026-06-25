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
    # TA専用ロック画面の表示関数（ハッシュ照合版）
    # ==========================================
    function Show-LockScreen {
        # TA解除用パスワードのSHA-256ハッシュ値
        $TARGET_HASH = "08499276bc68ad602e1a3fa407135e69bf8fa9586144e5d8a9e7019f7f4a211e" 

        $form = New-Object System.Windows.Forms.Form
        $form.Size = New-Object System.Drawing.Size(900, 500)
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
        $lblMsg.Text = "ただちに試験監督（TA）を呼んでください。`nこの画面はTAがパスワードを入力するまで閉じられません。"
        $lblMsg.Font = New-Object System.Drawing.Font("Meiryo UI", 16, [System.Drawing.FontStyle]::Bold)
        $lblMsg.ForeColor = [System.Drawing.Color]::White
        $lblMsg.AutoSize = $true
        $lblMsg.Location = New-Object System.Drawing.Point(55, 140)
        $form.Controls.Add($lblMsg)

        $lblTA = New-Object System.Windows.Forms.Label
        $lblTA.Text = "【TA向け解除手順】`n1. タスクバーのアイコンからPCのWi-Fiを「オフ」にしてください。`n2. 以下のパスワードを入力して解除してください。"
        $lblTA.Font = New-Object System.Drawing.Font("Meiryo UI", 14)
        $lblTA.ForeColor = [System.Drawing.Color]::LightGray
        $lblTA.AutoSize = $true
        $lblTA.Location = New-Object System.Drawing.Point(55, 250)
        $form.Controls.Add($lblTA)

        $txtPass = New-Object System.Windows.Forms.TextBox
        $txtPass.PasswordChar = '*'
        $txtPass.Font = New-Object System.Drawing.Font("Meiryo UI", 20)
        $txtPass.Width = 250
        $txtPass.Location = New-Object System.Drawing.Point(60, 350)
        $form.Controls.Add($txtPass)

        $btnUnlock = New-Object System.Windows.Forms.Button
        $btnUnlock.Text = "解除する"
        $btnUnlock.Font = New-Object System.Drawing.Font("Meiryo UI", 16, [System.Drawing.FontStyle]::Bold)
        $btnUnlock.Size = New-Object System.Drawing.Size(150, 45)
        $btnUnlock.Location = New-Object System.Drawing.Point(330, 349)
        $btnUnlock.BackColor = [System.Drawing.Color]::White
        $form.Controls.Add($btnUnlock)

        $script:isLocked = $true

        $btnUnlock.Add_Click({
            # 入力されたパスワードをSHA-256でハッシュ化して比較
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($txtPass.Text)
            $hashBytes = $sha.ComputeHash($bytes)
            $inputHash = [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()

            if ($inputHash -eq $TARGET_HASH) {
                $script:isLocked = $false
                $form.Close()
            } else {
                [System.Windows.Forms.MessageBox]::Show("パスワードが違います。", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                $txtPass.Text = ""
            }
        })

        $form.Add_FormClosing({
            if ($script:isLocked) { $_.Cancel = $true }
        })

        [void]$form.ShowDialog()
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

    $form = New-Object System.Windows.Forms.Form
    $form.Size = New-Object System.Drawing.Size(280, 22)
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.TopMost = $true
    $form.ShowInTaskbar = $false
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $form.Location = New-Object System.Drawing.Point(([int]([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width/2)-140), 0)
    $form.BackColor = [System.Drawing.Color]::Black
    
    $label = New-Object System.Windows.Forms.Label
    $label.ForeColor = [System.Drawing.Color]::Lime
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.Font = New-Object System.Drawing.Font("Meiryo UI", 9, [System.Drawing.FontStyle]::Bold)
    $label.Text = "[$studentId] 監視準備中"
    $form.Controls.Add($label)

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
    
    while($true){ 
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
            
            $label.Text = "[$studentId] 監視中: $($count)枚 ($(Get-Date -Format 'HH:mm'))"
            $graphics.Dispose(); $bmp.Dispose()

            # --- Pingによるインターネット通信監視 ---
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send("8.8.8.8", 1000)
                
                if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $logTime = Get-Date -Format 'HH:mm:ss'
                    $logMsg = "[$logTime] インターネット接続を検知しました。"
                    $logMsg | Out-File "$saveDir\network_warning.log" -Append -Encoding UTF8
                    
                    Show-LockScreen
                }
            } catch {}
            
        } catch {
            $errMsg = "Capture Error at $(Get-Date): $_"
            $errMsg | Out-File "$([Environment]::GetFolderPath('Desktop'))\capture_error.log" -Append
        }
        $randomInterval = Get-Random -Minimum 30 -Maximum 91
        for ($i = 0; $i -lt $randomInterval; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 1000 }
    }
} catch { (Get-Date).ToString() + " Fatal: $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\debug.log" -Append }