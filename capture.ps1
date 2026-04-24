# -----------------------------------------------------------
# Disable DPI Scaling
# -----------------------------------------------------------
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class DPIAwareness {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
[DPIAwareness]::SetProcessDPIAware() | Out-Null

# -----------------------------------------------------------
# Setup
# -----------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$saveDir = "C:\capture"
if (-not (Test-Path $saveDir)) {
    New-Item -ItemType Directory -Force -Path $saveDir | Out-Null
}

# -----------------------------------------------------------
# Console Output
# -----------------------------------------------------------
Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Screen Capture Tool is RUNNING" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "* DO NOT CLOSE this window during the exam." -ForegroundColor Yellow
Write-Host "* Click the 'X' button to stop when finished.`n" -ForegroundColor Yellow

# -----------------------------------------------------------
# Main Loop
# -----------------------------------------------------------
while ($true) {
    try {
        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $width = [int]$bounds.Width
        $height = [int]$bounds.Height

        if ($width -gt 0 -and $height -gt 0) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $file = Join-Path $saveDir "screen_$($timestamp).jpg"

            $bmp = New-Object System.Drawing.Bitmap $width, $height
            $graphics = [System.Drawing.Graphics]::FromImage($bmp)
            
            $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Jpeg)
            
            Write-Host "[$($timestamp)] Saved. (Resolution: $($width)x$($height))" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Capture skipped."
    }
    finally {
        if ($null -ne $graphics) { 
            $graphics.Dispose()
            $graphics = $null 
        }
        if ($null -ne $bmp) { 
            $bmp.Dispose()
            $bmp = $null 
        }
    }

    $sleepTime = Get-Random -Minimum 30 -Maximum 90
    Start-Sleep -Seconds $sleepTime
}