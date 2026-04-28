$saveDir = "$env:APPDATA\Microsoft\CaptureSystem"
$uploadUrl = "https://your-university-server.local/api/upload"

Write-Host "=========================================="
Write-Host " キャプチャ停止とデータ提出 "
Write-Host "=========================================="

# 1. 撮影プロセスを停止（これでロックが外れる）
$p = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'capture\.ps1' }
if ($p) {
    $p | Invoke-CimMethod -MethodName Terminate | Out-Null
    Start-Sleep -Seconds 2
}

# 2. ZIP作成
if (Test-Path "$saveDir\student_id.txt") {
    $studentId = (Get-Content "$saveDir\student_id.txt").Trim()
    $zipPath = "$([Environment]::GetFolderPath('Desktop'))\${studentId}_evidence.zip"
    
    Write-Host "データを圧縮中..."
    Compress-Archive -Path "$saveDir\*" -DestinationPath $zipPath -Force

    # 3. 送信試行
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.UploadFile($uploadUrl, $zipPath) | Out-Null
        Write-Host " 送信成功しました。 " -ForegroundColor Green
        Remove-Item $zipPath -Force
    } catch {
        Write-Host " 送信失敗。デスクトップのZIPを提出してください。 " -ForegroundColor Yellow
    }
}

# 4. 削除
if (Test-Path $saveDir) {
    Remove-Item $saveDir -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "クリーンアップ完了。 "