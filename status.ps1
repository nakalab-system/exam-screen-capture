Write-Host "=========================================="
Write-Host " 動作ステータス確認 "
Write-Host "=========================================="
Write-Host ""

# 【修正ポイント】正しい保存先を参照するように変更
$saveDir = "$env:APPDATA\Microsoft\CaptureSystem"

$p = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'capture\.ps1' }
if ($p) {
    Write-Host "[実行中] ツールは正常に稼働しています！ " -ForegroundColor Green
    # 隠しフォルダの中の画像を探す
    $f = Get-ChildItem "$saveDir\*.jpg" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) {
        Write-Host ("   -> 最新の保存時刻: " + $f.LastWriteTime.ToString("HH:mm:ss")) -ForegroundColor Cyan
    } else {
        Write-Host "   -> (まだ画像は保存されていません) " -ForegroundColor Yellow
    }
} else {
    Write-Host "[停止中] ツールは動いていません。 " -ForegroundColor Red
}