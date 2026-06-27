# exam-screen-capture（Windows版）

プログラミング試験中の画面を定期的に保存し、終了時に提出用ZIPを作成するツールです。  
このREADMEは **Windows版のみ** を対象にしています（`for_mac` 配下は対象外）。

## 構成ファイル（Windows）

- `/home/runner/work/exam-screen-capture/exam-screen-capture/1_start.bat`  
  試験開始時の起動バッチ
- `/home/runner/work/exam-screen-capture/exam-screen-capture/start.ps1`  
  オフライン確認、学籍番号受付、保存先準備、監視プロセス起動
- `/home/runner/work/exam-screen-capture/exam-screen-capture/capture.ps1`  
  画面キャプチャ、画面上部ステータス表示、試験中ネットワーク監視、ロック画面制御
- `/home/runner/work/exam-screen-capture/exam-screen-capture/2_submit.bat`  
  試験終了時の提出バッチ
- `/home/runner/work/exam-screen-capture/exam-screen-capture/submit.ps1`  
  監視プロセス停止、ZIP作成、提出フォルダへの配置、後処理

## 受験者向け使い方

### 1. 試験開始

1. `1_start.bat` を実行します。
2. インターネット接続が検出された場合は、オフラインにして再確認します。
3. 学籍番号（半角数字8桁）を入力します。
4. 画面上部にステータスバー（`[学籍番号] 試験中: ...`）が表示されたら開始です。

### 2. 試験中

- ツールが定期的に画面全体（マルチモニタ含む）をJPEG保存します。
- ネットワーク接続を検知するとロック画面が表示されます。
- ロック画面が出た場合は、受験者は操作せずTAを呼んでください。

### 3. 試験終了

1. 解答ファイルを解答用フォルダに保存します。
2. `2_submit.bat` を実行します。
3. ZIPファイルが解答用フォルダ（またはデスクトップ直下）に作成されたことを確認します。
4. 解答ファイルとZIPを提出します。

## 保存先仕様

- 内部保存先（キャプチャ作業領域）  
  `%LOCALAPPDATA%\Microsoft\CaptureSystem\{学籍番号}_{YYYYMMDD}`
- 解答用フォルダ（優先順）  
  1. `デスクトップ\{学籍番号}_{YYYYMMDD}`  
  2. `ダウンロード\{学籍番号}_{YYYYMMDD}`
- 提出ZIP名  
  `{学籍番号}_{YYYYMMDD_HHMMSS}.zip`

## 復旧・再開

- 前回の未提出データが内部保存先にあれば、`1_start.bat` 実行時に再開します。
- 誤って提出した場合でも、解答フォルダ内の最新ZIPが見つかれば復元して再開します。

## TA向け補足（ロック解除）

ロック画面の解除には、以下を満たすUSBメモリが必要です。

- USBルートに `TA_unlock.key`
- USBルートに `ta_unlock.pfx`
- 解除時に正しいPIN入力

※証明書のサムプリント一致検証を行うため、正しいTA用メディア以外では解除できません。

## 注意事項

- 本ツールはWindows PowerShell実行を前提にしています。
- 実行ポリシーの都合上、バッチ内で `-ExecutionPolicy Bypass` を利用しています。
- 起動・提出は必ずリポジトリ直下の `1_start.bat` / `2_submit.bat` から行ってください。
