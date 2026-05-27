Write-Host "=========================================="
Write-Host " 画面キャプチャ システム起動 "
Write-Host "=========================================="

$baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"
$desktopPath = [Environment]::GetFolderPath('Desktop')
$downloadsPath = "$([Environment]::GetFolderPath('UserProfile'))\Downloads"

$isResume = $false
$studentId = ""
$date = ""

# ==========================================
# 1. 【強制終了対策】隠しフォルダ残骸からの再開
# ==========================================
if (Test-Path $baseDir) {
    $oldSubDir = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 1
    
    if ($oldSubDir -and $oldSubDir.Name -match "^([0-9]{8})_([0-9]{8})$") {
        $studentId = $matches[1]
        $date = $matches[2]
        $isResume = $true
        
        Write-Host ""
        Write-Host "[検知] 前回の未提出データ（強制終了等）が見つかりました。" -ForegroundColor Yellow
        Write-Host "       学籍番号 [$studentId] のキャプチャを続きから再開します。" -ForegroundColor Green
    } else {
        Remove-Item $baseDir -Recurse -Force -ErrorAction SilentlyContinue > $null 2>&1
    }
}

# ==========================================
# 2. 【誤Submit対策】提出済みZIPからの復元・再開
# ==========================================
if (-not $isResume) {
    $potentialDirs = @()
    if (Test-Path $desktopPath) {
        $potentialDirs += @(Get-ChildItem -Path $desktopPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^([0-9]{8})_([0-9]{8})$" })
    }
    if (Test-Path $downloadsPath) {
        $potentialDirs += @(Get-ChildItem -Path $downloadsPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^([0-9]{8})_([0-9]{8})$" })
    }
    
    foreach ($dir in $potentialDirs) {
        $sid = $dir.Name.Split('_')[0]
        $zips = @(Get-ChildItem -Path $dir.FullName -Filter "${sid}_*.zip" -Force -ErrorAction SilentlyContinue)
        if ($zips) {
            $latestZip = $zips | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $studentId = $sid
            $date = $dir.Name.Split('_')[1]
            $isResume = $true
            
            Write-Host ""
            Write-Host "[検知] 誤って終了された画像ZIPを見つけました。" -ForegroundColor Yellow
            Write-Host "       学籍番号 [$studentId] のデータを復元し、途中から再開します..." -ForegroundColor Green
            Write-Host "       ZIPを解凍しています (少々お待ちください) ..." -ForegroundColor Cyan
            
            # 隠しフォルダの再構築
            if (-not (Test-Path $baseDir)) { [void](New-Item -ItemType Directory -Force -Path $baseDir) }
            $saveDir = "$baseDir\${studentId}_${date}"
            if (-not (Test-Path $saveDir)) { [void](New-Item -ItemType Directory -Force -Path $saveDir) }
            
            # ZIPの解凍
            $tempExtract = "$env:TEMP\ExtractStage_${studentId}"
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
            [void](New-Item -ItemType Directory -Force -Path $tempExtract)
            
            Expand-Archive -Path $latestZip.FullName -DestinationPath $tempExtract -Force
            
            # 画像を隠しフォルダに戻し、解凍ゴミを消す
            Copy-Item -Path "$tempExtract\*" -Destination $saveDir -Recurse -Force
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            
            # 再度Submitした際に「ZIPの中にZIPが入る」のを防ぐため、解凍し終わった古いZIPは削除する
            Remove-Item $latestZip.FullName -Force -ErrorAction SilentlyContinue
            
            [void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)
            break
        }
    }
}

# ==========================================
# 3. 新規スタート時の処理
# ==========================================
if (-not $isResume) {
    if (-not (Test-Path $baseDir)) {
        [void](New-Item -ItemType Directory -Force -Path $baseDir)
    }
    
    while ($studentId -notmatch "^[0-9]{8}$") {
        $studentId = Read-Host "学籍番号を入力してください（半角数字8桁）"
        if ($studentId -notmatch "^[0-9]{8}$") {
            Write-Host "エラー：学籍番号は「半角数字8桁」で入力してください。" -ForegroundColor Red
        }
    }
    
    $date = Get-Date -Format "yyyyMMdd"
    $saveDir = "$baseDir\${studentId}_${date}"
    [void](New-Item -ItemType Directory -Force -Path $saveDir)
    [void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)
}

[void](attrib +h $baseDir)

# ==========================================
# 解答用フォルダの作成（OneDriveエラー回避付き）
# ==========================================
$answerDirDesktop = "$desktopPath\${studentId}_${date}"
$answerDirDownloads = "$downloadsPath\${studentId}_${date}"
$finalAnswerDir = ""

try {
    if (-not (Test-Path $answerDirDesktop)) {
        New-Item -ItemType Directory -Force -Path $answerDirDesktop -ErrorAction Stop | Out-Null
    }
    $finalAnswerDir = $answerDirDesktop
} catch {
    if (-not (Test-Path $answerDirDownloads)) {
        New-Item -ItemType Directory -Force -Path $answerDirDownloads -ErrorAction Stop | Out-Null
    }
    $finalAnswerDir = $answerDirDownloads
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
if ($isResume) {
    Write-Host " 以下の解答用フォルダを継続して使用します。" -ForegroundColor Cyan
} else {
    Write-Host " 以下の場所に解答用フォルダを準備しました。" -ForegroundColor Cyan
}
Write-Host " -> $finalAnswerDir " -ForegroundColor Yellow
Write-Host " 試験のソースコード(.cpp等)は、必ずこの中に保存してください。" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$capturePath = "$PSScriptRoot\capture.ps1"
[void](Start-Process "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$capturePath`"" -WindowStyle Hidden)

if ($isResume) {
    Write-Host "監視を再開しました。ウィンドウを閉じます..." -ForegroundColor Green
} else {
    Write-Host "監視を開始しました。ウィンドウを閉じます..." -ForegroundColor Green
}
Start-Sleep -Seconds 5

exit