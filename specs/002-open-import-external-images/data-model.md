# 資料模型（增補）

本文件只描述相對於[功能 001 的資料模型](../001-screenshot-capture-annotation/data-model.md)的**新增與變更**。座標、標註、修飾等一切不變。

## CaptureSource（變更）

新增案例：

| 案例 | 欄位 | 說明 |
|------|------|------|
| `imported` | `fileName: String` | 使用者從本機檔案匯入。`fileName` 為原始檔名（含副檔名，不含路徑） |

- JSON：`{ "type": "imported", "fileName": "photo.jpg" }`。
- `fileName` 缺漏時解碼為空字串（與 `window` 案例的容錯一致）。
- 不認得的 `type` 仍回落成 `region`（既有行為，向前相容）。

## Capture（行為說明，欄位不變）

匯入項目的欄位值：

| 欄位 | 值 |
|------|----|
| `id` | 新的 UUID（同一檔案匯入多次得到不同 id，不去重） |
| `createdAt` / `modifiedAt` | 匯入時間（秒為單位，與擷取一致） |
| `source` | `.imported(fileName:)` |
| `pixelSize` | 套用方向後的影像像素尺寸，等於檔案在系統預覽程式中呈現的尺寸 |
| `scale` | 1.0 |
| `annotations` / `crop` / `outputScale` / `finish` | 空／nil／1.0／`Finish.none` |
| `schemaVersion` | 1（不變） |

## LibraryEntry（變更）

| 欄位 | 型別 | 說明 |
|------|------|------|
| `sourceFileName` | `String?` | 新增。匯入項目為原始檔名，其他為 nil。不可用的項目為 nil |

資料庫視圖以 `sourceFileName != nil` 決定是否顯示「匯入」小圖示，並以它作為提示文字。

## ImportLimits（新）

| 常數 | 值 | 說明 |
|------|----|------|
| `maxSide` | 16384 | 單邊像素上限（套用方向後） |
| `maxPixels` | 200_000_000 | 總像素上限 |

驗證規則：寬、高皆 ≥ 1；`max(width, height) ≤ maxSide`；`width × height ≤ maxPixels`（用 `Int` 運算，不溢位）。

## ImportFailure（新，錯誤列舉）

| 案例 | 觸發 | 使用者看到的原因（zh-TW） |
|------|------|---------------------------|
| `notAFile` | 資料夾、非本機 URL、不存在 | 不是圖片檔（資料夾或網頁圖片） |
| `unreadable` | 無讀取權限、讀取失敗 | 無法讀取檔案 |
| `unsupportedFormat` | ImageIO 不認得 | 不支援的檔案格式 |
| `corrupt` | 認得格式但解碼失敗 | 檔案已損毀 |
| `tooLarge(width, height)` | 超過 `ImportLimits` | 圖片過大（寬 × 高） |
| `storageFailed` | 寫入資料庫失敗（磁碟已滿、位置不可寫、編碼失敗） | 無法儲存到資料庫（磁碟空間不足或位置無法寫入） |

## ImportReport（新，不持久保存）

由 `ImportResult` 與「是否開啟編輯器」推導出的純資料，供 App 顯示彙總訊息；規則可無螢幕測試：

| 欄位 | 說明 |
|------|------|
| `editorsToOpen` | 要自動開啟編輯器的項目（`openEditors` 為真時取前 5 個，否則為空） |
| `onlyInLibraryCount` | 已匯入但因超過 5 個而未開啟編輯器的數量 |
| `listedFailures` | 要逐筆列出的失敗（排除 `notAFile`，最多 8 筆） |
| `unlistedFailureCount` | 超過 8 筆而未列出的失敗數量 |
| `skippedNonFileCount` | `notAFile` 的合併計數 |
| `needsAlert` | 是否需要跳出彙總訊息：有失敗、有略過，或有「僅在資料庫」的項目時為真；全部成功且全部開啟時為假 |

## ImportResult（新，不持久保存）

| 欄位 | 型別 | 說明 |
|------|------|------|
| `imported` | `[Capture]` | 成功建立的項目，依輸入順序 |
| `failures` | `[ImportFailureItem]` | 每筆含 `name`（檔名或 URL 字串）與 `reason: ImportFailure` |
| `cancelled` | `Bool` | 是否因取消而提早結束；已完成的項目保留 |

衍生：`skippedNonFileCount`（`notAFile` 的筆數，彙總訊息合併計數）。

## 狀態與生命週期

- **建立**：暫存目錄 `<UUID>.importing/` →（三個檔案寫完）→ 原子改名為 `<UUID>.tracepixelscapture/`。改名前的任何失敗都移除暫存目錄，項目不存在。
- **啟動清理**：App 啟動時移除所有殘留的 `*.importing`（上一次異常結束留下的）。
- 其餘（自動保存、刪除、清除舊擷取）與擷取完全相同。
