# 保存先をユーザーフォルダ内の隠し場所に変更
$saveDir = "$env:APPDATA\Microsoft\CaptureSystem"
if (-not (Test-Path $saveDir)) {
    New-Item -ItemType Directory -Force -Path $saveDir | Out-Null
}

Write-Host "=========================================="
Write-Host " 画面キャプチャ システム起動 "
Write-Host "=========================================="

$studentId = Read-Host "学籍番号を入力してください "
if ([string]::IsNullOrWhiteSpace($studentId)) { exit }

# 学籍番号を保存
Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8

# フォルダ自体に隠し属性をつける（ユーザー権限で可能）
attrib +h $saveDir

Write-Host "準備が完了しました。数秒後にこの画面は閉じます。 " -ForegroundColor Green
Start-Sleep -Seconds 3

# 撮影用スクリプトを隠しウィンドウで起動
Start-Process powershell -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"capture.ps1`""