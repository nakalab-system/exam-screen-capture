# mac版 USB解除（候補1） ファイル仕様

この文書は、候補1
**「USB上の鍵ファイル + TA手入力PIN」**
を実装するための、

- `.ta_unlock_policy`
- `ta_unlock.key`

の具体フォーマット仕様を定めるものです。

---

## 1. この仕様の目的

この仕様では、次を満たすことを目指す。

- 配布システムから平文の解除鍵を推測できない
- 実装が shell ベースでも扱いやすい
- 将来の候補3
  `署名ファイル + 公開鍵`
  に発展しやすい

---

## 2. 採用する方針

最初の実装では、次のシンプルな構成を採用する。

### 本体側

- `.ta_unlock_policy`
  に
  - `challenge_id`
  - `required_key_filename`
  - `key_hash`
  を保存する

### USB側

- `ta_unlock.key`
  に
  - `challenge_id`
  - `unlock_key`
  - `pin_hash`
  を保存する

### 解除条件

- Wi-Fi が OFF
- USB内に `ta_unlock.key` が存在
- `challenge_id` が一致
- `unlock_key` のハッシュが一致
- TA PIN のハッシュが一致

---

## 3. `.ta_unlock_policy` 仕様

### 3-1. 保存場所

候補:

- `CaptureSystem/.ta_unlock_policy`

隠しファイルとして保持する。

### 3-2. 形式

シンプルな `key=value` 形式を採用する。

例:

```text
challenge_id=2026-final-01
required_key_filename=ta_unlock.key
key_hash=0f8b0f1d6d7d6e5a62f31f8c3f13c33d42d405ef90b3920b0e6f4a2d9d1b2345
```

### 3-3. 各項目の意味

#### `challenge_id`

- 試験配布ごとの識別子
- 毎回変更する
- 人が見て分かる文字列でもよい

例:

- `2026-final-01`
- `2026-07-midterm-A`

#### `required_key_filename`

- USB側で探す鍵ファイル名
- 初期実装では固定でよい

推奨:

- `ta_unlock.key`

#### `key_hash`

- USB鍵ファイル内の `unlock_key` 値の SHA-256
- **平文鍵そのものは保存しない**

## 4. `ta_unlock.key` 仕様

### 4-1. 配置場所

推奨:

- `/Volumes/TA_USB/ta_unlock.key`

ただし実装では、

- `/Volumes/*/ta_unlock.key`

探索にも対応できるようにする。

### 4-2. 形式

こちらも `key=value` 形式にする。

例:

```text
challenge_id=2026-final-01
unlock_key=9Rr3M2Yp8Kq4Xn7Vb1AaBcCdDeEfFgGh
pin_hash=9af15b336e6a9619928537df30b2e6a2376569fcf9d7e773eccede65606529a0
```

### 4-3. 各項目の意味

#### `challenge_id`

- 本体側と一致すべき識別子
- 配布物の `challenge_id` と一致しない場合は失敗

#### `unlock_key`

- 毎回ランダム生成する秘密文字列
- 32文字以上を推奨
- 英数字のみで十分

#### `pin_hash`

- TA PIN の SHA-256
- 平文PINは保存しない

---

## 5. 解除時の照合手順

### Step 1

- Wi-Fi OFF を確認する

### Step 2

- `/Volumes` 配下から `required_key_filename` を探す

### Step 3

- 見つかった `ta_unlock.key` を読む

### Step 4

- USB側 `challenge_id` を取得する
- `.ta_unlock_policy` 側 `challenge_id` と一致確認する

### Step 5

- USB側 `unlock_key` を取得する
- SHA-256 を計算する
- `.ta_unlock_policy` の `key_hash` と一致確認する

### Step 6

- USB側 `pin_hash` を取得する
- TAが入力した PIN の SHA-256 を計算する
- USB側 `pin_hash` と一致確認する

### Step 7

- 全て一致した場合のみ解除する

---

## 6. 鍵生成ルール

### 6-1. `unlock_key`

推奨条件:

- 32文字以上
- ランダム
- 英数字

例:

```text
9Rr3M2Yp8Kq4Xn7Vb1AaBcCdDeEfFgGh
```

### 6-2. TA PIN

推奨条件:

- 4桁固定よりは 6桁以上が望ましい
- 試験ごと変更が理想
- ただし運用負担とのバランスを取る

---

## 7. 生成手順（手動運用版）

### 7-1. `unlock_key` を決める

TA または管理者がランダムな文字列を生成する。

### 7-2. `key_hash` を作る

```sh
printf '%s' 'ここにunlock_key' | shasum -a 256
```

### 7-3. `pin_hash` を作る

```sh
printf '%s' 'ここにTA_PIN' | shasum -a 256
```

### 7-4. `.ta_unlock_policy` を作る

例:

```text
challenge_id=2026-final-01
required_key_filename=ta_unlock.key
key_hash=<生成したkey_hash>
```

### 7-5. USBに `ta_unlock.key` を置く

例:

```text
challenge_id=2026-final-01
unlock_key=<生成したunlock_key>
pin_hash=<生成したpin_hash>
```

---

## 8. 実装時のパース方針

shell 実装では、`key=value` 形式を次のように読む。

例:

```sh
grep '^challenge_id=' .ta_unlock_policy | cut -d= -f2-
```

同様に

- `required_key_filename`
- `key_hash`
- `unlock_key`
- `pin_hash`

も取り出せる。

この形式は JSON より shell で扱いやすい。

---

## 9. 失敗時メッセージ方針

解除失敗時は、原因を分けて表示すると運用しやすい。

候補:

- `Wi-Fiをオフにしてから解除してください`
- `TA用USBが見つかりません`
- `TA用鍵ファイルが見つかりません`
- `TA用USBの鍵が一致しません`
- `TA用PINが正しくありません`

---

## 10. セキュリティ上の注意

この候補1は、
**配布システム内に平文鍵を残さない**
ことが主目的である。

ただし、次の弱点は残る。

- USB鍵ファイルがコピーされると弱い
- PINが漏れると危険

そのため運用上は、

- USBをTA管理下に置く
- PINを安易に固定し続けない
- 試験ごとに `challenge_id` と `unlock_key` を変える

ことが望ましい。

---

## 11. 応急処置

通常解除とは別に、
`LOCK_ACTIVE.flag` 削除による応急解除は残す。

これは次のため。

- 実装不具合
- USB認識失敗
- 緊急時の復旧

この応急処置は、
**通常手段ではなく、最後の手段**
として扱う。

---

## 12. 次に実装する内容

この仕様に基づき、次に実装するなら以下。

1. `.ta_unlock_policy` 読込処理
2. `/Volumes` 配下の USB探索
3. `ta_unlock.key` 読込処理
4. `challenge_id` 一致確認
5. `unlock_key` ハッシュ照合
6. USB内 `pin_hash` 読込
7. TA PIN 照合
8. 解除成功時の既存ロジック接続
