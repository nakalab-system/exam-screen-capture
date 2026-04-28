$saveDir = "$env:APPDATA\Microsoft\CaptureSystem"

Write-Host "=========================================="
Write-Host " キャプチャ停止と証拠データ作成 (USB提出用) "
Write-Host "=========================================="
Write-Host ""

# 1. 撮影プロセスを停止（ファイルのロックを解除）
$p = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'capture\.ps1' }
if ($p) {
    $p | Invoke-CimMethod -MethodName Terminate | Out-Null
    Start-Sleep -Seconds 2
}

# 2. 削除ロック設定を解除
if (Test-Path $saveDir) {
    icacls $saveDir /remove:d "$($env:USERNAME)" | Out-Null
}

# 3. ZIPファイルの作成（デスクトップへ出力）
if (Test-Path "$saveDir\student_id.txt") {
    $studentId = (Get-Content "$saveDir\student_id.txt").Trim()
    $zipPath = "$([Environment]::GetFolderPath('Desktop'))\${studentId}_evidence.zip"
    
    Write-Host "データを圧縮しています... " -ForegroundColor Cyan
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path "$saveDir\*" -DestinationPath $zipPath -Force

    # 画面にUSB提出の案内を大きく表示
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host " 処理完了：デスクトップに ZIP を作成しました！ " -ForegroundColor Green
    Write-Host " -> ${studentId}_evidence.zip " -ForegroundColor Yellow
    Write-Host " このファイルをTAのUSBメモリに提出してください。 " -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Green
} else {
    Write-Host "[エラー] 学籍番号データが見つかりません。" -ForegroundColor Red
}

# 4. 元データのクリーンアップ（証拠のZIP化が終わったので隠しフォルダを消去）
if (Test-Path $saveDir) {
    Remove-Item $saveDir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""
Write-Host "一時データを安全に削除しました。"