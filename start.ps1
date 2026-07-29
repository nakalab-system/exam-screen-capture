Write-Host "=========================================="
Write-Host " 画面キャプチャ システム起動 "
Write-Host "=========================================="

$baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"

$isResume = $false
$studentId = ""
$todayStr = Get-Date -Format "yyyyMMdd"
$date = ""

function Test-InternetConnectivity {
    if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        return $false
    }

    $okGw  = $false
    $okDns = $false

    try {
        $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
               Sort-Object RouteMetric | Select-Object -First 1).NextHop
        if ($gw) {
            $ping  = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($gw, 1000)
            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $okGw = $true
            }
        }
    } catch {}

    try {
        $profile = Get-NetConnectionProfile -ErrorAction Stop |
                   Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' }
        if ($profile) { $okDns = $true }
    } catch {}

    return ($okGw -or $okDns)
}

function Test-IsOneDrivePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ($env:OneDrive -and $Path.StartsWith($env:OneDrive, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($env:OneDriveCommercial -and $Path.StartsWith($env:OneDriveCommercial, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    if ($Path -match '\\OneDrive(\s*-\s*[^\\]+)?\\') { return $true }
    return $false
}

function Get-CandidateAnswerRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    $shellDesktop = [Environment]::GetFolderPath('Desktop')
    if (-not (Test-IsOneDrivePath $shellDesktop)) { $roots.Add($shellDesktop) }

    $trueDesktop = Join-Path $env:USERPROFILE 'Desktop'
    if (-not (Test-IsOneDrivePath $trueDesktop)) { $roots.Add($trueDesktop) }

    $downloads = Join-Path $env:USERPROFILE 'Downloads'
    if (-not (Test-IsOneDrivePath $downloads)) { $roots.Add($downloads) }

    $roots.Add("C:\ExamSystem")

    $seen = @{}
    $result = @()
    foreach ($r in $roots) {
        if (-not $seen.ContainsKey($r)) { $seen[$r] = $true; $result += $r }
    }
    return $result
}

function Invoke-WithTimeout {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [int]$TimeoutMs = 3000
    )
    try {
        $ps = [PowerShell]::Create()
        [void]$ps.AddScript($ScriptBlock)
        foreach ($a in $ArgumentList) { [void]$ps.AddArgument($a) }
        $handle = $ps.BeginInvoke()
        if ($handle.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $result = $ps.EndInvoke($handle)
            $ps.Dispose()
            return [pscustomobject]@{ Success = $true; TimedOut = $false; Result = $result }
        } else {
            return [pscustomobject]@{ Success = $false; TimedOut = $true; Result = $null }
        }
    } catch {
        return [pscustomobject]@{ Success = $false; TimedOut = $false; Result = $null }
    }
}

function Find-ResumeZipInRoot {
    param([string]$Root, [string]$TodayStr, [int]$TimeoutMs = 2500)
    $r = Invoke-WithTimeout -TimeoutMs $TimeoutMs -ScriptBlock {
        param($root, $today)
        if (-not (Test-Path $root)) { return $null }
        $dirs = Get-ChildItem -Path $root -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^([0-9]{8})_($today)$" }
        foreach ($dir in $dirs) {
            $sid = $dir.Name.Split('_')[0]
            $zips = @(Get-ChildItem -Path $dir.FullName -Filter "${sid}_${today}_*.zip" -Force -ErrorAction SilentlyContinue)
            if ($zips) {
                $latest = $zips | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                return [pscustomobject]@{ StudentId = $sid; ZipPath = $latest.FullName }
            }
        }
        return $null
    } -ArgumentList $Root, $TodayStr

    if ($r.Success -and $r.Result) { return $r.Result }
    return $null
}

function Test-PathWritable {
    param([string]$RootPath, [int]$TimeoutMs = 3000)
    $r = Invoke-WithTimeout -TimeoutMs $TimeoutMs -ScriptBlock {
        param($root)
        $probe = Join-Path $root (".wtest_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $probe -ErrorAction Stop | Out-Null
        Remove-Item -Path $probe -Force -Recurse -ErrorAction SilentlyContinue
        return $true
    } -ArgumentList $RootPath
    return ($r.Success -and $r.Result -eq $true)
}

$candidateRoots = Get-CandidateAnswerRoots
$pendingRestoreZip = $null

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
        Where-Object { $_.Name -match "^([0-9]{8})_($todayStr)$" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($oldSubDir) {
        [void]($oldSubDir.Name -match "^([0-9]{8})_($todayStr)$")
        $studentId = $matches[1]; $date = $matches[2]; $isResume = $true
        Write-Host "[検知] 本日の未提出データが見つかりました．キャプチャを再開します．" -ForegroundColor Green
    } else {
        Remove-Item $baseDir -Recurse -Force -ErrorAction SilentlyContinue > $null 2>&1
    }
}

if (-not $isResume) {
    $zipSearchTimeoutSec = [Math]::Round(($candidateRoots.Count * 2.5), 1)
    Write-Host "[処理中] 誤提出データがないか確認しています...（最大${zipSearchTimeoutSec}秒）" -ForegroundColor Cyan
    foreach ($root in $candidateRoots) {
        $found = Find-ResumeZipInRoot -Root $root -TodayStr $todayStr -TimeoutMs 2500
        if ($found) {
            $studentId = $found.StudentId
            $date = $todayStr
            $isResume = $true
            $pendingRestoreZip = $found.ZipPath
            Write-Host "[検知] 本日の誤って終了された画像ZIPを検出しました．監視開始後に復元します．" -ForegroundColor Green
            break
        }
    }
    if (-not $isResume) {
        Write-Host "[確認] 誤提出データは見つかりませんでした．通常どおり開始します．" -ForegroundColor Cyan
    }
}

if (-not $isResume) {
    if (-not (Test-Path $baseDir)) { [void](New-Item -ItemType Directory -Force -Path $baseDir) }
    while ($studentId -notmatch "^[0-9]{8}$") {
        $studentId = Read-Host "学籍番号を入力してください（半角数字8桁）"
        if ($studentId -notmatch "^[0-9]{8}$") { Write-Host "エラー：学籍番号は「半角数字8桁」で入力してください．" -ForegroundColor Red }
    }
    $date = $todayStr
}

if (-not (Test-Path $baseDir)) { [void](New-Item -ItemType Directory -Force -Path $baseDir) }
$saveDir = "$baseDir\${studentId}_${date}"
if (-not (Test-Path $saveDir)) { [void](New-Item -ItemType Directory -Force -Path $saveDir) }
[void](Set-Content -Path "$saveDir\student_id.txt" -Value $studentId -Encoding UTF8)

$originCapturePath = "$PSScriptRoot\capture.ps1"
$secureCapturePath = "$baseDir\system_core.ps1"
$launchTarget = $originCapturePath

Write-Host "[処理中] キャプチャプログラムを準備しています...（最大3秒）" -ForegroundColor Cyan
$copyResult = Invoke-WithTimeout -TimeoutMs 3000 -ScriptBlock {
    param($src, $dst)
    if (Test-Path $src) { Copy-Item -Path $src -Destination $dst -Force -ErrorAction Stop }
    return $true
} -ArgumentList $originCapturePath, $secureCapturePath

if ($copyResult.Success -and $copyResult.Result -and (Test-Path $secureCapturePath)) {
    $launchTarget = $secureCapturePath
    Write-Host "[OK] 準備が完了しました．" -ForegroundColor Green
} else {
    Write-Host "[注意] 準備がタイムアウトしたため、元のプログラムからそのまま起動します．" -ForegroundColor Yellow
}

[void](Start-Process "$PSHOME\powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launchTarget`"" -WindowStyle Hidden)
Write-Host "`nキャプチャを開始しました．" -ForegroundColor Green

try {
    [void](attrib +h $baseDir)
} catch {}

if ($pendingRestoreZip) {
    Write-Host "[処理中] 誤提出ZIPからの画像復元を試みています...（最大20秒）" -ForegroundColor Cyan
    $tempExtract = "$env:TEMP\ExtractStage_${studentId}"
    if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue }
    [void](New-Item -ItemType Directory -Force -Path $tempExtract)

    $restoreResult = Invoke-WithTimeout -TimeoutMs 20000 -ScriptBlock {
        param($zipPath, $extractDir, $dest)
        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
        Copy-Item -Path "$extractDir\*" -Destination $dest -Recurse -Force
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
        return $true
    } -ArgumentList $pendingRestoreZip, $tempExtract, $saveDir

    if ($restoreResult.Success -and $restoreResult.Result) {
        Write-Host "[復元] 画像の復元が完了しました．" -ForegroundColor Green
    } else {
        Write-Host "[警告] ZIPからの復元がタイムアウトまたは失敗しました．過去の画像は復元されていませんが，キャプチャは新規データとして続行しています．TAに状況を報告してください．" -ForegroundColor Yellow
    }
}

$finalAnswerDir = ""
$answerSearchTimeoutSec = [Math]::Round(($candidateRoots.Count * 3), 1)
Write-Host "[処理中] 回答用フォルダを準備しています...（最大${answerSearchTimeoutSec}秒）" -ForegroundColor Cyan
foreach ($root in $candidateRoots) {
    $candidate = "$root\${studentId}_${date}"
    if (Test-PathWritable -RootPath $root -TimeoutMs 3000) {
        try {
            if (-not (Test-Path $candidate)) { New-Item -ItemType Directory -Force -Path $candidate -ErrorAction Stop | Out-Null }
            $finalAnswerDir = $candidate
            break
        } catch {
            continue
        }
    }
}

Write-Host "`n==========================================" -ForegroundColor Cyan
if ($finalAnswerDir) {
    Write-Host " 回答用フォルダを準備しました．" -ForegroundColor Cyan
    Write-Host " -> $finalAnswerDir " -ForegroundColor Yellow
    Write-Host " ※ 提出時にもこのフォルダにZIPが作成されます．場所を必ず覚えておいてください．" -ForegroundColor Yellow
} else {
    Write-Host " 【警告】回答用フォルダの自動作成に失敗しました．" -ForegroundColor Red
    Write-Host " キャプチャ自体は正常に動作していますので，このまま試験を続けてください．" -ForegroundColor Yellow
    Write-Host " 提出時にも自動配置に失敗する可能性があります．TAに申し出てください．" -ForegroundColor Yellow
}
Write-Host "==========================================" -ForegroundColor Cyan

Write-Host "`nウィンドウを閉じます..." -ForegroundColor Green
Start-Sleep -Seconds 3
exit
