Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$saveDir = "C:\capture"
# フォルダが存在しない場合のみ作成
New-Item -ItemType Directory -Force -Path $saveDir | Out-Null

# 解像度を動的取得
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

while ($true) {
    # ファイル名（時刻付き）
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    # 拡張子を .png から .jpg に変更
    $file = "$saveDir\screen_$timestamp.jpg"

    # スクリーンキャプチャのオブジェクト作成
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    
    # 画面のキャプチャ（X, Y座標も動的に対応）
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

    # JPG形式で保存（容量削減）
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Jpeg)

    # 【重要】メモリ解放（無限ループでのメモリリークを防止）
    $graphics.Dispose()
    $bmp.Dispose()

    # ランダム待機（30〜90秒）
    $sleep = Get-Random -Minimum 30 -Maximum 90
    Start-Sleep -Seconds $sleep
}