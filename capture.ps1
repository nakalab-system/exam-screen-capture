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
    
    $saveDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"
    $studentId = if (Test-Path "$saveDir\student_id.txt") { (Get-Content "$saveDir\student_id.txt").Trim() } else { "Unknown" }

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
            $totalW = $maxX - $minX
            $totalH = $maxY - $minY
            $boundsSize = New-Object System.Drawing.Size($totalW, $totalH)

            $bmp = New-Object System.Drawing.Bitmap($totalW, $totalH)
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            $graphics.CopyFromScreen($minX, $minY, 0, 0, $boundsSize)
            
            $count = @(Get-ChildItem -Path $saveDir -Filter "*.jpg" -ErrorAction SilentlyContinue).Count + 1
            $bmp.Save("$saveDir\${studentId}_$($count.ToString("D2"))_$(Get-Date -Format 'HHmmss').jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
            
            $label.Text = "[$studentId] 監視中: $($count)枚 ($(Get-Date -Format 'HH:mm'))"
            
            $graphics.Dispose(); $bmp.Dispose()
        } catch {}
        
        $randomInterval = Get-Random -Minimum 30 -Maximum 91
        for ($i = 0; $i -lt $randomInterval; $i++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 1000 }
    }
} catch { (Get-Date).ToString() + " Fatal: $_" | Out-File "$([Environment]::GetFolderPath('Desktop'))\debug.log" -Append }