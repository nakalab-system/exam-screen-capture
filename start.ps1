Write-Host "=========================================="
Write-Host " 画面キャプチャ システム起動 "
Write-Host "=========================================="

$baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"
$desktopPath = [Environment]::GetFolderPath('Desktop')
$downloadsPath = "$([Environment]::GetFolderPath('UserProfile'))\Downloads"

$isResume = $false
$studentId = ""
$date = ""

function Test-InternetConnectivity {
    param([int]$timeoutMs = 1000)

    $okPing = $false
    $okDns = $false
    $okHttp = $false

    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send("8.8.8.8", $timeoutMs)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { $okPing = $true }
    } catch {}

    try {
        $null = [System.Net.Dns]::GetHostAddresses("www.google.com")
        $okDns = $true
    } catch {}

    try {
        $resp = Invoke-WebRequest -Uri "http://clients3.google.com/generate_204" -Method Get -TimeoutSec 3 -UseBasicParsing
        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) { $okHttp = $true }
    } catch {}

    $score = 0
    if ($okPing) { $score++ }
    if ($okDns)  { $score++ }
    if ($okHttp) { $score++ }

    return ($score -ge 2)
}

Write-Host "`n[準備] ネットワーク接続状態を確認しています..." -ForegroundColor Cyan
while ($true) {
    $isConnected = $false
    try { $isConnected = Test-InternetConnectivity } catch { $isConnected = $false }

    if ($isConnected) {
        Write-Host "`n==========================================" -ForegroundColor Red
        Write-Host " 【警告】インターネット接続が検出されました！" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host " 試験を開始するためには，PCを完全にオフラインにする必要があります．" -ForegroundColor Yellow
        Write-Host " PCの Wi-Fi を「オフ（切断）」にしてください．" -ForegroundColor White
        Write-Host " ------------------------------------------" -ForegroundColor DarkGray
        Write-Host " Wi-Fiを切断したら，Enterキーを押して再確認してください．" -ForegroundColor Cyan
        Read-Host
    } else {
        Write-Host " -> [OK] オフライン環境を確認しました．`n" -ForegroundColor Green
        break
    }
}

if (Test-Path $baseDir) {
    $oldSubDir = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^([0-9]{8})_([0-9]{8})$" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($oldSubDir) {
        [void]($oldSubDir.Name -match "^([0-9]{8})_([0-9]{8})$")
        $studentId = $matches[1]; $date = $matches[2]; $isResume = $true
        Write-Host "[検知] 前回の未提出データが見つかりました．キャプチャを再開します．" -ForegroundColor Green
    } else {
        Remove-Item $baseDir -Recurse -Force -ErrorAction SilentlyContinue > $null 2>&1
    }
}

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
            $studentId = $sid; $date = $dir.Name.Split('_')[1]; $isResume = $true
            
            Write-Host "[検知] 誤って終了された画像ZIPからデータを復元し，再開します．" -ForegroundColor Green
            
            if (-not (Test-Path $baseDir)) { [void](New-Item -ItemType Directory -Force -Path $baseDir) }
            $saveDir = "$baseDir\${studentId}_${date}"
            if (-not (Test-Path $saveDir)) { [void](New-Item -ItemType Directory -Force -Path $saveDir) }
            
            $tempExtract = "$env:TEMP\ExtractStage_${studentId}"
            if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
            [void](New-Item -ItemType Directory -Force -Path $tempExtract)
            
            Expand-Archive -Path $latestZip.FullName -DestinationPath $tempExtract -Force
            Copy-Item -Path "$tempExtract\*" -Destination $saveDir -Recurse -Force
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $latestZip.FullName -Force -ErrorAction SilentlyContinue
            
            [void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)
            break
        }
    }
}

if (-not $isResume) {
    if (-not (Test-Path $baseDir)) { [void](New-Item -ItemType Directory -Force -Path $baseDir) }
    while ($studentId -notmatch "^[0-9]{8}$") {
        $studentId = Read-Host "学籍番号を入力してください（半角数字8桁）"
        if ($studentId -notmatch "^[0-9]{8}$") { Write-Host "エラー：学籍番号は「半角数字8桁」で入力してください．" -ForegroundColor Red }
    }
    $date = Get-Date -Format "yyyyMMdd"
    $saveDir = "$baseDir\${studentId}_${date}"
    [void](New-Item -ItemType Directory -Force -Path $saveDir)
    [void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)
}

$originCapturePath = "$PSScriptRoot\capture.ps1"
$secureCapturePath = "$baseDir\system_core.ps1"
$fakeExePath = "$baseDir\WinSysMonitor.exe"

if (Test-Path $originCapturePath) { Copy-Item -Path $originCapturePath -Destination $secureCapturePath -Force }
if (-not (Test-Path $fakeExePath)) { Copy-Item "$PSHOME\powershell.exe" -Destination $fakeExePath -Force }

[void](attrib +h $baseDir)

$answerDirDesktop = "$desktopPath\${studentId}_${date}"
$answerDirDownloads = "$downloadsPath\${studentId}_${date}"
$finalAnswerDir = ""

try {
    if (-not (Test-Path $answerDirDesktop)) { New-Item -ItemType Directory -Force -Path $answerDirDesktop -ErrorAction Stop | Out-Null }
    $finalAnswerDir = $answerDirDesktop
} catch {
    if (-not (Test-Path $answerDirDownloads)) { New-Item -ItemType Directory -Force -Path $answerDirDownloads -ErrorAction Stop | Out-Null }
    $finalAnswerDir = $answerDirDownloads
}

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host " 回答用フォルダを準備しました．" -ForegroundColor Cyan
Write-Host " -> $finalAnswerDir " -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

[void](Start-Process $fakeExePath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$secureCapturePath`"" -WindowStyle Hidden)

Write-Host "`nキャプチャを開始しました．ウィンドウを閉じます..." -ForegroundColor Green
Start-Sleep -Seconds 3
exit