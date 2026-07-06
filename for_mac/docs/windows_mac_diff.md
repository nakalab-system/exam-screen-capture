# Windows版とmac版の違い

このドキュメントは、このリポジトリに含まれる **Windows版** と **mac版（現在 `for_mac/配布用formac/CaptureSystem` に入っている実運用版）** の違いを整理したものです。

---

## 1. 全体像の違い

### Windows版

- 目的:
  試験中の画面記録に加えて、**オフライン強制、試験中ネットワーク監視、警告ロック、TA解除、提出用ZIP作成**までを一体化した高機能版。
- 実装:
  `bat + PowerShell` ベース。
- 主な実体:
  - `1_start.bat`
  - `start.ps1`
  - `capture.ps1`
  - `2_submit.bat`
  - `submit.ps1`

### mac版

- 目的:
  追加インストールなしで、BYODのMac上で**最低限の画面記録と提出用ZIP作成**を行う簡易版。
- 実装:
  `sh + osascript + screencapture + caffeinate` ベース。
- 主な実体:
  - `for_mac/配布用formac/CaptureSystem/start.sh`
  - `for_mac/配布用formac/CaptureSystem/bin/capture.sh`
  - `for_mac/配布用formac/CaptureSystem/bin/finish.sh`
  - `for_mac/配布用formac/CaptureSystem/Check.app`

要するに、**Windows版は監督機能まで含む本格版**、**mac版は配布と運用のしやすさを優先した簡略版**です。

---

## 2. 配布形態の違い

### Windows版

- リポジトリ直下の `1_start.bat` と `2_submit.bat` を実行する想定。
- PowerShell を `-ExecutionPolicy Bypass` 付きで起動する。
- Windows環境では `.bat` を入口にしやすい。

### mac版

- 現在の実運用版は `for_mac/配布用formac/CaptureSystem` フォルダ単位で配布する構成。
- `start.sh` を起点にしつつ、状態確認は `Check.app` を使う。
- Gatekeeper 対策が必要で、初回実行時の右クリック `開く` 運用が前提になりやすい。

---

## 3. 起動フローの違い

### Windows版の開始処理

`start.ps1` が担当する内容:

- 起動時にインターネット接続を複合判定する。
  - Ping
  - DNS
  - HTTP
- オンラインなら開始をブロックする。
- 当日の未提出データがあれば再開する。
- 提出済みZIPが見つかれば復元再開する。
- 学籍番号を受け取る。
- 内部保存フォルダと解答用フォルダを作る。
- `capture.ps1` をバックグラウンド起動する。

### mac版の開始処理

`start.sh` が担当する内容:

- `/tmp/CaptureSystem_capture.pid` で二重起動を確認する。
- 学籍番号をダイアログで受け取る。
- `CaptureSystem/Logs` フォルダを作る。
- `student_id.txt` を保存して `uchg` でロックする。
- `screencapture` を小さく実行して、画面収録権限を事前チェックする。
- 権限が通るまで再チェックのダイアログを出す。
- `caffeinate -d sh bin/capture.sh` を `nohup` で起動する。

### 違いの要点

- Windows版は**オフライン確認が必須**。
- mac版は**画面収録権限の確認が主**で、オフライン強制はしていない。
- Windows版は**途中再開・復元**に対応。
- mac版は**再開・復元ロジックをほぼ持たない**。

---

## 4. 画面キャプチャ処理の違い

### Windows版

`capture.ps1` の特徴:

- `System.Windows.Forms` と `System.Drawing` を使う。
- **マルチモニタ全体**を1枚の画像として取得する。
- 学籍番号、枚数、時刻を表示する**常時最前面バー**を表示する。
- キャプチャ間隔はランダム。
  - 実装上は `1〜59秒` の乱数になっている。
- キャプチャ枚数を連番管理する。
- ネットワーク監視タイマーと並行動作する。

### mac版

`bin/capture.sh` の特徴:

- `screencapture -m -x -t jpg` を使う。
- **メインモニタのみ**を撮影する。
- 画像ファイル名は `img_YYYYMMDD_HHMMSS.jpg`。
- キャプチャ間隔は `30〜90秒` のランダム。
- 証拠用画像は `CaptureSystem/Logs` に保存する。
- 状況確認用に同じ画像を `/tmp/CaptureSystemLogs` にコピーする。

### 違いの要点

- Windows版は**マルチモニタ全体対応**、mac版は**メインモニタのみ**。
- Windows版は**画面上の監視バー表示あり**、mac版は**表示なし**。
- Windows版はUI統合型、mac版はシェル中心のシンプル構成。

---

## 5. 保存先の違い

### Windows版

- 内部保存先:
  `%LOCALAPPDATA%\Microsoft\CaptureSystem\{学籍番号}_{日付}`
- 解答用フォルダ:
  - デスクトップ優先
  - だめならダウンロード
- 提出ZIP:
  解答用フォルダ内、またはフォールバックでデスクトップ

### mac版

- 証拠画像保存先:
  `for_mac/配布用formac/CaptureSystem/Logs`
- 状況確認用コピー:
  `/tmp/CaptureSystemLogs`
- PIDファイル:
  `/tmp/CaptureSystem_capture.pid`
- 提出ZIP:
  `for_mac/配布用formac/CaptureSystem/{学籍番号}_evidence.zip`

### 違いの要点

- Windows版は**ユーザーのローカルアプリ領域に隠して保存**する。
- mac版は**配布フォルダ内に保存**する。
- mac版はUSBや配布フォルダをそのまま持ち回る運用と相性がよい。

---

## 6. 不正抑止・監督機能の違い

### Windows版

- 開始前のオフライン強制確認あり。
- 試験中のネットワーク監視あり。
- ネット接続検知時に警告ログを残す。
- ロック画面を最前面表示する。
- TA専用USB、証明書、PINでのみ解除可能。
- ロック中は提出処理もブロックする。

### mac版

- 開始前のオフライン確認なし。
- 試験中のネットワーク監視なし。
- ロック画面なし。
- TA解除機構なし。

### 違いの要点

- 不正抑止の厳しさは **Windows版が大幅に強い**。
- mac版は主に**事後証跡の収集**に寄っている。

---

## 7. 状況確認機能の違い

### Windows版

- 画面上部に常時ステータスバーを出す。
- 学籍番号、撮影枚数、時刻が見える。
- 別アプリを起動しなくても稼働状況が見える。

### mac版

- `Check.app` を手動起動して確認する。
- `/tmp/CaptureSystemLogs` の最新画像時刻を見て、
  `正常に稼働中 / 停止中` をダイアログ表示する。

### 違いの要点

- Windows版は**常時見える**。
- mac版は**必要時だけ確認アプリを開く**。

---

## 8. 終了・提出フローの違い

### Windows版

`submit.ps1` が担当する内容:

- バックグラウンドプロセスを終了する。
- ロック画面中なら提出を拒否する。
- キャプチャ画像をZIP化する。
- ZIPを解答用フォルダへ移動する。
- 内部保存領域を削除する。

ZIP名:

- `{学籍番号}_{YYYYMMDD_HHMMSS}.zip`

### mac版

`bin/finish.sh` が担当する内容:

- PIDを見てキャプチャプロセスを停止する。
- `Logs` 配下の `uchg` を解除する。
- `Logs` の中身をZIP化する。
- ZIPは `CaptureSystem` フォルダ直下へ出力する。
- 同名ZIPがあれば `_2`, `_3` を付けて退避する。
- `Logs` フォルダを削除する。

ZIP名:

- `{学籍番号}_evidence.zip`
- 重複時は `{学籍番号}_evidence_2.zip` のように連番回避

### 違いの要点

- Windows版は**タイムスタンプ付きZIP名**。
- mac版は**固定名ベース + 重複時のみ連番回避**。
- Windows版は**解答用フォルダへ誘導**する。
- mac版は**配布フォルダ内にZIPを残す**。

---

## 9. 再開・復旧の違い

### Windows版

- 当日の未提出データを自動再開できる。
- 誤って作成された提出ZIPから復元再開できる。
- 途中終了への耐性が高い。

### mac版

- PIDファイルで二重起動は防ぐ。
- ただし Windows版のような**明確な復元再開機構はない**。
- `Logs` が残っていれば手動で再利用できる余地はあるが、設計としては復旧機能が弱い。

---

## 10. 権限・OS依存の違い

### Windows版

- PowerShell 実行ポリシーの回避が必要。
- `System.Windows.Forms` / `System.Drawing` / Win32 API に依存する。
- TA解除で証明書処理を使う。

### mac版

- 画面収録権限が必須。
- `screencapture`, `osascript`, `caffeinate`, `jot`, `zip`, `chflags` に依存する。
- Gatekeeper の未署名アプリ制限を受けやすい。
- `start.sh` では `xattr -cr` で `Check.app` の quarantine 回避も試みている。

---

## 11. 実運用上の評価

### Windows版の強み

- 試験監督向け機能が多い。
- 不正抑止が強い。
- 再開・復旧に強い。
- 画面状態の可視化がしやすい。

### Windows版の弱み

- 実装が重い。
- OS依存が強い。
- UIと監視ロジックが複雑。

### mac版の強み

- 実装が軽い。
- macOS標準機能だけで完結しやすい。
- USB配布や簡易運用に向いている。

### mac版の弱み

- 不正抑止機能がかなり少ない。
- マルチモニタ対応が弱い。
- 復旧や再開に弱い。
- 現在の `for_mac/README.md` や `docs/plan.md` と実物構成にズレがある。

---

## 12. まとめ

最も大きな違いは次の3点です。

1. Windows版は **監督機能込みの厳格版**、mac版は **記録重視の簡易版**。
2. Windows版は **ローカル内部保存 + 解答フォルダ提出**、mac版は **配布フォルダ内保存 + フォルダ直下ZIP提出**。
3. Windows版は **ネットワーク検知・ロック・TA解除まで実装**、mac版は **そこまで実装していない**。

そのため、mac版は「Windows版の完全移植」ではなく、**運用制約に合わせて機能を絞った別系統の実装**と考えるのが実態に近いです。
