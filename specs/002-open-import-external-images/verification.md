# 驗證紀錄：開啟與匯入外部圖片

**日期**：2026-11-04　**分支**：`002-open-import-external-images`　**環境**：Xcode 27.1、Swift 6.4、macOS 26.7（Apple Silicon）

本文件區分兩類結果：**已自動驗證**，以及**需審查者手動驗證**。沒有視窗伺服器互動、檔案選擇視窗、拖放與 Finder 的環境無法驗證的項目，沒有被當成已驗證。

## 1. 自動化驗證

| 項目 | 指令 | 結果 |
|------|------|------|
| 核心邏輯測試（Release） | `cd Packages/TracePixelsCore && swift test -c release` | 179 項全過 |
| 核心邏輯測試（Debug） | `cd Packages/TracePixelsCore && swift test` | 179 項全過（功能 001 的 130 項＋本功能新增 49 項），沒有被略過的測試 |
| 核心效能測試（Debug／Release） | `swift test [-c release] --filter PerformanceTests` | 5 項全過（見下表） |
| App 單元測試 | `xcodebuild … test` | 24 項全過（`EditorViewModelTests` 18＋`MainMenuTests` 6） |
| App 建置（Debug） | `xcodebuild … -configuration Debug build` | BUILD SUCCEEDED |
| App 建置（Release Universal） | 比照 `release.yml`：`ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO MARKETING_VERSION=9.9.9 CURRENT_PROJECT_VERSION=42` | BUILD SUCCEEDED；`lipo -archs` 為 `x86_64 arm64`；版本號覆寫生效（`CFBundleShortVersionString` 9.9.9、`CFBundleVersion` 42） |
| Info.plist 合併 | `plutil -p …/Info.plist` | 同時含自動產生的 `LSUIElement`／`CFBundleDisplayName` 與 `CFBundleDocumentTypes`（`public.image`、`LSHandlerRank = Alternate`、`CFBundleTypeRole = Editor`），Debug 與 Release 皆然 |
| 本地化 | 從 `.stringsdata` 取出所有 key 比對 `Localizable.xcstrings` | 缺漏為 0；23 個新 key 皆有英文（含 3 組複數形式）；移除 1 個不再使用的舊說明文字；`en.lproj` 已確認編入 |

### 規格對照

| 規格項目 | 驗證 |
|----------|------|
| FR-033、FR-037、SC-011 各格式的原始尺寸 | `ImageImporterTests`：PNG／JPEG／TIFF／GIF／BMP／HEIC 皆測，尺寸相符 |
| FR-038、SC-011 透明度、方向、色彩 | `ImageImporterTests`：alpha 保留；EXIF 方向 1～8 在無損 TIFF 上**逐像素**驗證轉正位置與寬高對調；直拍 JPEG 轉正；Display P3 色彩空間保留 |
| 邊界：動態 GIF 只取第一格 | `ImageImporterTests` |
| FR-040 尺寸上限 | `ImageImporterTests`：單邊 16384 可、16385 拒；總像素 201.6 百萬（14200×14200）拒；方向 6 的 16384×2 圖尺寸對調後仍可 |
| FR-040、FR-045、SC-013 損毀／不支援／資料夾／非本機 URL／無權限 | `ImageImporterTests`、`LibraryImporterTests`：分類正確、資料庫無不可用項目、無殘留 `*.importing` |
| 邊界：磁碟滿或位置不可寫 | `LibraryImporterTests`：資料庫目錄唯讀時歸入 `storageFailed`、無殘留；`LibraryStoreTests`：`create` 失敗不留項目 |
| FR-035、SC-010 原檔不被改動 | `ImageImporterTests`、`LibraryImporterTests`：內容與修改時間相同 |
| FR-036 副本獨立於來源 | `LibraryImporterTests`：匯入後刪原檔仍可載入 |
| 邊界：同檔匯入多次 | `LibraryImporterTests`：兩個不同 id 的項目 |
| FR-039 來源與檔名 | `ModelCodingTests`（JSON 契約、缺漏檔名、舊版未知型別回落）、`LibraryStoreTests`（`sourceFileName`） |
| FR-034、FR-040、FR-045 編輯器上限與彙總規則 | `ImportReportTests`（7 項） |
| SC-014 重新啟動後仍可編輯 | `LibraryImporterTests`：匯入 → 加標註 → 存檔 → 全新 `LibraryStore` 實例載入，標註與來源仍在，`image.png` 位元組不變 |
| 取消與進度 | `LibraryImporterTests` |
| FR-031 主選單項目與快速鍵 | `MainMenuTests`：⌘O、⇧⌘I、位置、快速鍵不重複 |
| FR-042 不碰網路 | 沒有新增任何網路程式碼；`ImageImporter` 對非 `file:` URL 直接回報 `notAFile`（`ImageImporterTests`）。未重做功能 001 的 `otool -L` 稽核，本功能沒有新增連結的框架 |

### 效能（SC-009、SC-012）

| 測試 | Debug | Release | 上限 |
|------|-------|---------|------|
| 12 百萬像素截圖：解碼＋存入資料庫 | 146 ms | 147 ms | 700 ms |
| 12 百萬像素高細節照片：解碼＋存入資料庫 | 1677 ms | 1698 ms | 3000 ms |
| 匯入 20 張 1600×1000 PNG | 493 ms | 487 ms | 10000 ms |

**SC-009 在實測後從單一門檻改為兩層**（截圖 1 秒、照片 3 秒）：高細節照片幾乎無法壓縮，PNG 編碼要 1.7 秒（輸出約 30 MB），ImageIO 沒有壓縮等級選項，濾波器選項只省約 30%。理由與替代方案見 [research.md](./research.md) D-18；這是對規格的修正，不是放寬測試去遷就結果。

## 2. 需審查者手動驗證（本環境無法驗證）

這個環境無法由真人操作檔案選擇視窗、拖放與 Finder，也**不能啟動開發版 App**：作業環境中 `/Applications/TracePixels.app` 正在執行，開發版與它共用 bundle id，同時執行會讓全域快速鍵與選單列圖示衝突。所以下列項目**尚未驗證**。步驟見 [quickstart.md](./quickstart.md) 的 M7～M11。請先結束已安裝的版本再驗證。

### 從選單列開啟（M7，使用者故事 1）

- [ ] 沒有任何視窗、Dock 圖示隱藏時，選單列出現「開啟圖片…」，點選後檔案選擇視窗出現在最前面（而不是其他 App 後面）。
- [ ] 選一張 PNG → 編輯器以原始像素尺寸開啟；標註、複製後貼到其他 App；原檔修改時間與內容不變。
- [ ] 取消不產生任何副作用；多選 3 張開 3 個編輯器；多選 7 張只開 5 個並提示其餘 2 張已在資料庫。
- [ ] 編輯器全關後 Dock 圖示回到隱藏。
- [ ] `⌘O` 在 App 啟用時生效。

### 資料庫匯入（M8，使用者故事 2）

- [ ] 底部「匯入…」按鈕與 `⇧⌘I`；匯入的項目出現在最前面、不需手動重新整理、**不自動開編輯器**。
- [ ] 縮圖卡片的「匯入」小圖示與滑鼠停留提示（原始檔名）；螢幕擷取項目沒有圖示。
- [ ] 直拍 JPEG 縮圖與編輯器內方向正確；透明 PNG 在編輯器與匯出後仍透明；GIF 只是靜態單張。
- [ ] 原檔移到垃圾桶後仍可從資料庫開啟；結束並重新啟動後項目仍在。
- [ ] 淺色與深色外觀下，圖示與拖放高亮邊框皆清楚（FR-049）。

### 拖曳（M9，使用者故事 3）

- [ ] 拖曳經過視窗時出現強調色邊框；放開後匯入且不開編輯器。
- [ ] 混有文字檔／資料夾時，圖片照常匯入並以單一訊息說明略過數量；全部不支援時不新增項目。
- [ ] 從瀏覽器拖網頁圖片：不匯入、不下載（可用網路監視確認沒有連線，FR-042）。**注意**：SwiftUI `dropDestination(for: URL.self)` 對「只有圖片資料、沒有 URL」的拖曳不會觸發，使用者看到的是不可放下的游標；這是預期行為。
- [ ] 資料庫為空時，空白狀態同樣接受放下，且說明文字提到「匯入…」與「拖曳」。

### 失敗與邊界（M10）

- [ ] 混合輸入的單一彙總訊息內容與格式；沒有「無法讀取」的項目。
- [ ] 單邊 20000 像素的圖被拒絕並顯示尺寸，App 不卡住。
- [ ] 匯入 ≈100 百萬像素的圖：超過 1 秒時進度面板出現、完成後消失，匯入期間其他視窗可操作（SC-012 的「介面保持可操作」）。
- [ ] 匯入進行中以 `⌘Q` 結束後再啟動：資料庫完好。

### Finder 與 Dock（M11，使用者故事 4）

- [ ] Finder「打開方式」清單出現 TracePixels，且**系統預設的圖片程式沒有被改變**。
- [ ] 冷啟動由 Finder 開啟：啟動後直接開編輯器，沒有多餘視窗。
- [ ] 拖 3 張圖片到 Dock 圖示：各自匯入並開編輯器。

### 其他

- [ ] 英文介面（系統語言切換為英文）下，新增字串的實際呈現與複數形式。
- [ ] VoiceOver 實際唸出「匯入圖片」按鈕與匯入項目的「匯入自 <檔名>」。
- [ ] **SC-015**（使用者測試 ≥ 90%）：屬使用者測試，尚未進行。

## 3. 已知限制

- **舊版重新保存會丟失匯入檔名**：舊版程式讀到 `imported` 來源會當作 `region`，之後保存時把來源寫回 `region`。標註與影像不受影響。
- **被截斷的 JPEG 等非 PNG 檔會被接受**：ImageIO 對截斷檔很寬鬆（缺的部分補空白仍回報成功）。只對 PNG 檢查 IEND 結尾；JPEG 常有合法的結尾雜訊，加同樣的檢查會誤殺好檔案。
- **高細節照片匯入較慢**：12 百萬像素的雜訊照片約 1.7 秒（見上方效能表）。
- **拖放只接受檔案 URL**：沒有本機檔案的網頁圖片資料拖曳不會被接受。
- **匯入彙總使用模態 `NSAlert`**：在 App 啟用的情況下會搶焦點；一般匯入全成功時不會出現。
