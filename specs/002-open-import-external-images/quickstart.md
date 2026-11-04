# 快速入門：建置、測試與驗證（開啟與匯入外部圖片）

本文件是驗證指南，不含實作程式碼。契約見 [contracts/](./contracts/)，資料模型見 [data-model.md](./data-model.md)。建置與執行的通用指令見[功能 001 的快速入門](../001-screenshot-capture-annotation/quickstart.md)。

## 自動化測試

```bash
# 核心：匯入相關
cd Packages/TracePixelsCore && swift test --filter ImageImporterTests
cd Packages/TracePixelsCore && swift test --filter LibraryImporterTests
cd Packages/TracePixelsCore && swift test --filter ImportReportTests
cd Packages/TracePixelsCore && swift test --filter LibraryStoreTests
cd Packages/TracePixelsCore && swift test            # 全部，確認沒有回歸

# 效能（SC-009）；Debug 與 Release 都應通過
cd Packages/TracePixelsCore && swift test --filter PerformanceTests
cd Packages/TracePixelsCore && swift test -c release --filter PerformanceTests

# App 單元測試（主選單新增項目）
xcodebuild -project TracePixels.xcodeproj -scheme TracePixels \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

**通過標準**：全部測試通過；`xcodebuild` 為 `BUILD SUCCEEDED`；建置後的 `Info.plist` 同時含 `LSUIElement` 與 `CFBundleDocumentTypes`：

```bash
plutil -p build/DerivedData/Build/Products/Debug/TracePixels.app/Contents/Info.plist | grep -E "LSUIElement|CFBundleDocumentTypes|LSHandlerRank"
```

### 自動化驗證對照

| 規格項目 | 驗證方式 |
|----------|----------|
| FR-033、SC-011 原始尺寸、各格式 | `ImageImporterTests`：PNG／JPEG／HEIC／TIFF／GIF／BMP 各一，尺寸逐一相符 |
| FR-038、SC-011 透明度、方向、色彩 | `ImageImporterTests`：含 alpha 的 PNG 保留 alpha；EXIF 方向 6 的 JPEG 寬高對調且內容轉正；非 sRGB 色彩空間保留 |
| 邊界：動態 GIF 取第一格 | `ImageImporterTests` |
| FR-040 尺寸上限 | `ImageImporterTests`：單邊 16385、總像素超過 200 百萬各被 `tooLarge` 拒絕，且未配置像素記憶體（只靠屬性判斷） |
| FR-040、SC-013 損毀／不支援／資料夾／非本機 URL | `ImageImporterTests`、`LibraryImporterTests`：分類正確，且資料庫沒有任何殘留 |
| FR-035、SC-010 原檔不被改動 | `ImageImporterTests`、`LibraryImporterTests`：匯入前後原檔內容雜湊與修改時間相同 |
| FR-036 副本獨立於來源 | `LibraryImporterTests`：匯入後刪除原檔，`LibraryStore.load` 仍成功 |
| 邊界：同一檔案匯入多次 | `LibraryImporterTests`：得到不同 id 的多個項目 |
| FR-039 來源與檔名 | `ModelCodingTests`（編解碼往返、缺漏 `fileName`）、`LibraryStoreTests`（`LibraryEntry.sourceFileName`） |
| 邊界：中途中斷不留半成品 | `LibraryStoreTests`：模擬寫入失敗與殘留 `*.importing`，`list()` 不含它、`removeStaleStaging()` 清除 |
| FR-034、FR-040、FR-045 編輯器上限與彙總規則 | `ImportReportTests`：超過 5 個只開前 5 個並記錄其餘數量；失敗最多列 8 筆、其餘計數；`notAFile` 合併計數；全成功且全開啟時 `needsAlert == false`；`openEditors == false` 時不開任何編輯器 |
| 邊界：磁碟滿／位置不可寫 | `LibraryImporterTests`：資料庫目錄不可寫時該檔歸入 `storageFailed`，其餘檔案不受影響、無殘留 |
| SC-014 重新啟動後仍可編輯 | `LibraryImporterTests`：匯入 → 加標註 → 存檔 → 以新的 `LibraryStore` 實例載入 → 標註仍在 |
| FR-045 混合輸入彙總 | `LibraryImporterTests`：有效＋損毀＋資料夾＋http URL 的組合，`imported`／`failures`／`skippedNonFileCount` 正確 |
| 取消 | `LibraryImporterTests`：取消後已完成的保留、`cancelled == true` |
| SC-009 ≤ 12 百萬像素 | `PerformanceTests`：核心步驟 ≤ 700 毫秒 |
| FR-031 主選單項目與快速鍵 | `TracePixelsTests/MainMenuTests`：「開啟圖片…」`⌘O`、「匯入…」`⇧⌘I` 存在且位置正確 |

## 手動驗證程序

需要視窗、檔案選擇視窗、拖放與 Finder 的行為，依下列步驟逐項勾選。準備素材：一張一般 PNG、一張手機直拍的 JPEG（有 EXIF 方向）、一張含透明背景的 PNG、一張 HEIC、一個多格 GIF、一個文字檔、一個資料夾、一個損毀的「假圖」（把文字檔改名成 `.png`）。

### M7 從選單列開啟（使用者故事 1）

1. 結束所有視窗，Dock 圖示隱藏。點選單列圖示 → 看到「開啟圖片…」（`⌘O`）。
2. 選取一張 PNG → 編輯器以原始像素尺寸開啟，工具列與屬性面板與擷取後相同。加一個箭頭與一個遮蔽，`⌘C` 後貼到其他 App。
3. 在 Finder 確認該 PNG 的修改時間與內容沒變。
4. 關閉編輯器，開資料庫 → 該項目在最前面；雙擊重新開啟，標註仍可個別選取與編輯。
5. 再次「開啟圖片…」後按取消 → 沒有編輯器、資料庫沒有新增項目。
6. 一次選取 3 張 → 3 個編輯器各開一個、資料庫新增 3 項。
7. 一次選取 7 張 → 只開 5 個編輯器，並提示其餘 2 張已在資料庫。
8. 關閉全部編輯器 → Dock 圖示回到隱藏。

### M8 匯入與外觀（使用者故事 2）

1. 開資料庫 → 點底部「匯入…」（或 `⇧⌘I`）→ 選 PNG、JPEG（直拍）、透明 PNG、HEIC、GIF。
2. 五個新項目依匯入時間排在最前面，縮圖可見；直拍 JPEG 縮圖與編輯器內方向正確；透明 PNG 在編輯器與匯出後仍透明；GIF 只是靜態單張。
3. 項目日期旁有「匯入」小圖示；滑鼠停留顯示原始檔名；螢幕擷取項目沒有這個圖示。
4. 在 Finder 把其中一個原檔移到垃圾桶 → 從資料庫仍可開啟與編輯該項目。
5. 結束並重新啟動 App → 項目仍在，標註仍可編輯。
6. 切換淺色／深色外觀 → 圖示與拖放高亮邊框皆清楚。

### M9 拖曳進資料庫（使用者故事 3）

1. 把兩張圖片與一個文字檔從 Finder 一起拖過資料庫視窗但先不放開 → 視窗出現強調色邊框。
2. 放開 → 兩張圖片匯入、不開編輯器；出現單一訊息說明 1 個檔案被略過。
3. 只拖文字檔放開 → 不新增項目，訊息說明原因。
4. 拖一個資料夾 → 視為不支援略過並說明；不展開。
5. 從瀏覽器拖一張網頁圖片進來 → 不匯入、不下載（可用網路監視確認沒有連線）。
6. 清空資料庫（全部刪除）後再拖一張圖片 → 空白狀態同樣接受。空白狀態說明文字提到「匯入…」與「拖曳」。

### M10 失敗與邊界

1. 一次匯入「有效圖 ×2、假 `.png`、文字檔、資料夾」→ 2 個成功項目；單一訊息列出假圖的檔名與原因，其餘合併計數；資料庫沒有「無法讀取」的項目。
2. 準備單邊 20000 像素的圖（可用腳本產生，不需內容有意義）→ 被拒絕並顯示尺寸，App 沒有當機或卡住。
3. 匯入 20 張一般圖片，計時 → 10 秒內全部出現，期間可以切換其他視窗。
4. 匯入一張約 100 百萬像素的圖 → 超過 1 秒時出現進度面板，匯入完成後消失。
5. 匯入同一個檔案兩次 → 兩個獨立項目。
6. 匯入進行中以 `⌘Q` 結束，再啟動 → 資料庫完好，沒有「無法讀取」的項目。

### M11 Finder 與 Dock（使用者故事 4）

1. 在 Finder 對一張 JPEG 按右鍵「打開方式」→ 清單有 TracePixels；選它 → 編輯器開啟該圖片。確認系統預設的圖片程式沒有被改成 TracePixels。
2. 結束 App，再以「打開方式」冷啟動 → 啟動後直接開編輯器，沒有多餘視窗。
3. 把 3 張圖片拖到 Dock 圖示（App 正在執行）→ 各自匯入並開編輯器。

### 字串檢核

新增使用者可見字串後，依 `CLAUDE.md` 的方式比對缺漏，補齊 `en` 翻譯。本功能新增或修改的字串：「開啟圖片…」「匯入…」「開啟圖片」「匯入圖片」「開啟」「匯入」、資料庫空白狀態說明、匯入圖示的提示與 VoiceOver 標籤（「匯入自 %@」）、進度面板文字（「正在匯入 %lld／%lld」）、彙總訊息（成功／略過／失敗／其餘 N 張已在資料庫）、六種 `ImportFailure` 的原因文字。
