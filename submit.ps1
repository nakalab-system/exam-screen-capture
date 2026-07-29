$baseDir = "$env:LOCALAPPDATA\Microsoft\CaptureSystem"

# 変更履歴
# 2026-07-29: OneDrive環境でハングしうる処理（解答フォルダ探索・ZIP移動）を
#             start.ps1と同じタイムアウト保護方式(Invoke-WithTimeout)に統一。
#             失敗・タイムアウト時はZIPをTEMPに残したまま明示的に警告し、
#             無言で失敗させないようにした。

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

function Test-PathQuick {
    param([string]$Path, [int]$TimeoutMs = 2000)
    $r = Invoke-WithTimeout -TimeoutMs $TimeoutMs -ScriptBlock { param($p) Test-Path $p } -ArgumentList $Path
    return ($r.Success -and $r.Result -eq $true)
}

$candidateRoots = Get-CandidateAnswerRoots
$desktopPath = [Environment]::GetFolderPath('Desktop')

Write-Host "=========================================="
Write-Host " 　　　提出準備　　　 "
Write-Host "=========================================="
Write-Host ""

$subDirCheck = Get-ChildItem -Path $baseDir -Directory -Force -ErrorAction SilentlyContinue | Select-Object -First 1
if ($subDirCheck) {
    $sessionStatePath = Join-Path $subDirCheck.FullName "session.dat"
    if (Test-Path $sessionStatePath) {
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host " [提出不可] インターネット接続の警告画面が表示中です．" -ForegroundColor Red
        Write-Host " TAによる解除が完了するまで提出処理は実行できません．" -ForegroundColor Red
        Write-Host " 画面の指示に従い，ただちにTAを呼んでください．" -ForegroundColor Red
        Write-Host "=================================================" -ForegroundColor Red
        exit 1
    }
}

$processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*system_core.ps1*' }
if ($processes) {
    foreach ($p in $processes) {
        $p | Invoke-CimMethod -MethodName Terminate | Out-Null
    }
    Start-Sleep -Seconds 2
}

$subDir = Get-ChildItem -Path $baseDir -Directory -Force | Select-Object -First 1

if ($subDir -and $subDir.Name -match "^([0-9]{8})_([0-9]{8})$") {
    $saveDir = $subDir.FullName
    $studentId = $matches[1]
    $savedDate = $matches[2]
    $datetime = Get-Date -Format "yyyyMMdd_HHmmss"

    $zipName = "${studentId}_${datetime}.zip"
    $tempZip = "$env:TEMP\$zipName"

    Write-Host "キャプチャ画像を圧縮しています... " -ForegroundColor Cyan

    Compress-Archive -Path "$saveDir\*" -DestinationPath $tempZip -Force

    # start.ps1が作成した解答フォルダを、同じ優先順位・タイムアウト保護で探索する
    $targetDir = ""
    $dirSearchTimeoutSec = [Math]::Round((($candidateRoots.Count + 1) * 2), 1)
    Write-Host "[処理中] 回答用フォルダを探しています...（最大${dirSearchTimeoutSec}秒）" -ForegroundColor Cyan
    foreach ($root in $candidateRoots) {
        $candidate = "$root\${studentId}_${savedDate}"
        if (Test-PathQuick -Path $candidate -TimeoutMs 2000) { $targetDir = $candidate; break }
    }
    if (-not $targetDir -and (Test-PathQuick -Path $desktopPath -TimeoutMs 2000)) {
        $targetDir = $desktopPath
        Write-Host "[警告] 解答用フォルダが見つからないため，デスクトップ直下に保存します．" -ForegroundColor Yellow
    }
    if ($targetDir) {
        Write-Host "[OK] 回答用フォルダが見つかりました．" -ForegroundColor Green
    }

    if ($targetDir) {
        $finalDest = "$targetDir\$zipName"
        Write-Host "[処理中] ZIPファイルを回答用フォルダへ移動しています...（最大15秒）" -ForegroundColor Cyan
        $moveResult = Invoke-WithTimeout -TimeoutMs 15000 -ScriptBlock {
            param($src, $dst)
            Move-Item -Path $src -Destination $dst -Force -ErrorAction Stop
            return $true
        } -ArgumentList $tempZip, $finalDest

        if ($moveResult.Success -and $moveResult.Result) {
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host " 処理完了：回答用フォルダ内にZIPファイルを格納しました！ " -ForegroundColor Green
            Write-Host " -> $finalDest " -ForegroundColor Yellow
            Write-Host " 提出するCPPファイルを回答用フォルダに入れ， " -ForegroundColor Yellow
            Write-Host " USBメモリでTAに提出してください． " -ForegroundColor Yellow
            Write-Host "==========================================" -ForegroundColor Green
        } else {
            Write-Host "==================================================" -ForegroundColor Red
            Write-Host " [警告] ZIPファイルの回答フォルダへの移動がタイムアウトまたは失敗しました．" -ForegroundColor Red
            Write-Host " ZIPファイルは下記の場所に残っています．手動で回答フォルダにコピーしてください．" -ForegroundColor Yellow
            Write-Host " -> $tempZip " -ForegroundColor Yellow
            Write-Host "==================================================" -ForegroundColor Red
        }
    } else {
        Write-Host "==================================================" -ForegroundColor Red
        Write-Host " [警告] 解答用フォルダが見つかりませんでした．" -ForegroundColor Red
        Write-Host " ZIPファイルは下記の場所に作成されています．手動で回答フォルダにコピーしてください．" -ForegroundColor Yellow
        Write-Host " -> $tempZip " -ForegroundColor Yellow
        Write-Host "==================================================" -ForegroundColor Red
    }

} else {
    Write-Host "[エラー] 学籍番号データが見つかりません．" -ForegroundColor Red
}

if (Test-Path $baseDir) {
    Remove-Item $baseDir -Recurse -Force -ErrorAction SilentlyContinue
}
