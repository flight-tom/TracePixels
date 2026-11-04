# 研究與決策：開啟與匯入外部圖片

依專案憲章原則 VII，所有決策由 Claude 自行做出並記錄理由；沒有向使用者提問。

## D-01：開啟外部檔案 = 匯入一份副本再開啟

- **決策**：不論從哪個入口，圖片都先成為資料庫的新項目（`image.png` 為解碼後的無損副本），編輯器照舊以資料庫項目運作。
- **理由**：編輯器的狀態模型、自動保存、復原與縮圖全部以資料庫項目為單位；原地編輯原檔會破壞「`image.png` 永不修改」與憲章原則 III。
- **替代方案**：(a) 為外部檔案另開「無資料庫」的編輯模式——要複製整套保存邏輯、且關閉後標註無處可存，否決；(b) 直接引用原檔路徑而不複製——原檔移動／刪除後項目失效，違反 FR-036，否決。

## D-02：匯入管線放在核心，分成單檔與批次兩層

- **決策**：`ImageImporter.load(from:)` 負責單檔（檢查、解碼、方向）；`LibraryImporter.importFiles(_:)` 負責批次（逐檔呼叫、收集成功與失敗、可回報進度、可取消）。兩者都不依賴 AppKit。
- **理由**：絕大部分風險（尺寸上限、方向、透明度、半成品）都在這裡，放核心才能無螢幕測試（原則 IV）。
- **替代方案**：把批次邏輯寫在 App 的 coordinator——無法單元測試，否決。

## D-03：`CaptureSource` 新增 `imported(fileName:)`，不升 schemaVersion

- **決策**：JSON 為 `{"type":"imported","fileName":"photo.jpg"}`。`schemaVersion` 維持 1。
- **理由**：既有 `CaptureSource` 解碼遇到未知 `type` 一律回落成 `region`，舊版本讀到新項目仍能開啟與編輯，只是來源顯示為區域；升版本反而會讓舊版把整個項目標為「不可用」，傷害更大。唯一代價：舊版重新保存會把來源寫回 `region`、丟掉檔名，可接受。
- **替代方案**：另存 `importedFrom` 欄位於 Capture 頂層——多一個可為空欄位、與 `source` 語意重複，否決。

## D-04：用 ImageIO 讀取，方向與尺寸檢查分兩步

- **決策**：
  1. `CGImageSourceCopyPropertiesAtIndex` 先取 `PixelWidth`／`PixelHeight`／`Orientation`，**在解碼前**判斷是否超過上限（單邊 16384、總像素 200 百萬；方向為 5–8 時寬高對調）。
  2. 通過後以 `CGImageSourceCreateThumbnailAtIndex` 搭配 `kCGImageSourceCreateThumbnailWithTransform`、`kCGImageSourceCreateThumbnailFromImageAlways`、`kCGImageSourceThumbnailMaxPixelSize = 較長邊`，取得「已套用方向、未縮小」的影像；方向為「正」時直接用 `CGImageSourceCreateImageAtIndex`。
  3. 只取 index 0（動態 GIF 取第一格）。
- **理由**：先查屬性可避免為了拒絕一張 5 億像素的圖而先配置數 GB 記憶體；縮圖 API 是 ImageIO 內建套用 EXIF 方向的標準路徑。PNG 存檔本身無損，所以像素內容與解碼結果一致（SC-011）。
- **實測發現**：(1) 只有標頭的 PNG，ImageIO 不給屬性（會是 `corrupt`），所以尺寸上限測試改用真正的 14200×14200 灰階 PNG（壓縮後很小）。(2) ImageIO 對被截斷的檔案很寬鬆，缺的部分補空白仍回報成功；因此對 PNG 額外檢查檔尾 IEND 區塊，缺了視為 `corrupt`。JPEG 等格式不做同樣檢查（常有合法的結尾雜訊，檢查會誤殺好檔案），截斷的 JPEG 會被當成可匯入、缺的部分為空白。
- **風險與驗證**：`MaxPixelSize` 等於原尺寸時不應重新取樣；以測試比對「方向為正的圖」兩條路徑的像素完全一致，並以含 EXIF 方向 6 的測試檔驗證寬高對調與內容旋轉。
- **替代方案**：自己用 `CGContext` 依方向旋轉——要自行處理 8 種方向矩陣與色彩空間，易錯，否決。

## D-05：透明度與色彩

- **決策**：不做任何色彩轉換或去 alpha；解碼出的 `CGImage` 原樣交給既有的 PNG 編碼（會內嵌色彩描述檔）。縮圖 JPEG 沿用既有 `Thumbnailer`（白底、sRGB）。
- **理由**：「顏色與系統預覽程式一致」最穩妥的做法就是不動色彩資料；透明 PNG 因 `image.png` 本身是 PNG 而完整保留。
- **驗證**：測試以含 alpha 的 PNG 與非 sRGB 色彩空間的圖往返，比對 alpha 與色彩空間名稱保留。

## D-06：哪些輸入算「可匯入」

- **決策**：以「是否為本機一般檔案」＋「ImageIO 能否解出第 0 格」判定，而不是只看副檔名。分類結果（`ImportFailure`）：
  - `notAFile`：資料夾、非本機 URL（網頁圖片）、不存在。
  - `unreadable`：沒有讀取權限或讀取失敗。
  - `unsupportedFormat`：ImageIO 不認得（文字檔、PDF、SVG、副檔名假的…）。
  - `corrupt`：認得格式但解碼失敗。
  - `tooLarge(width:height:)`：超過上限。
  - `storageFailed`：寫入資料庫失敗（磁碟已滿、位置不可寫）。由 `LibraryImporter` 把 `LibraryStore.create` 丟出的任何錯誤歸入此類；`ImageImporter.load` 不會丟出它。
- **理由**：副檔名不可靠；以實際解碼結果判斷同時處理「副檔名是圖片、內容損毀」的邊界情況。檔案選擇視窗另以 `UTType.image` 限定可選取類型（只是便利，不當作驗證）。
- **替代方案**：白名單副檔名——漏掉 HEIC 變體、`.jpeg`／`.jpe`／`.tif` 等，且擋不住假副檔名，否決。

## D-07：資料庫建立改為「暫存目錄 → 原子改名」

- **決策**：`LibraryStore.create` 先在同一資料庫目錄建 `<UUID>.importing/`，寫完 `image.png`、`document.json`、`thumbnail.jpg` 後一次 `moveItem` 成 `<UUID>.tracepixelscapture/`。`list()` 只認副檔名為 `tracepixelscapture` 的項目，所以暫存目錄永遠不會被當成項目；失敗時移除暫存目錄；啟動時清除殘留的 `*.importing`。
- **理由**：現行 `create` 先建正式目錄再逐檔寫入，中途終止會留下沒有 `document.json` 的項目，在資料庫顯示為「無法讀取」，違反 FR-040／SC-013。同一檔案系統內的目錄改名是原子的。此修改同時讓螢幕擷取更安全。
- **替代方案**：寫完之後才建立 `document.json` 當作「完成標記」——仍會留下無效目錄，且列表邏輯要區分兩種不完整狀態，否決。

## D-08：批次匯入循序進行，解碼在背景

- **決策**：`LibraryImporter` 逐檔循序處理（解碼在非主執行緒的呼叫端執行，只有 `create` 進入 `LibraryStore` actor）；每完成一檔回報 `(done, total, fileName)`；支援 `Task` 取消（檢查點在檔案之間）。
- **理由**：一般圖片 20 張在 10 秒內綽綽有餘（SC-012）；循序處理把記憶體峰值限制為一張圖，避免同時解碼多張大圖。
- **替代方案**：平行解碼——快一些但記憶體峰值失控（多張 200 百萬像素），目前沒有需要，否決。

## D-09：進度只在超過 1 秒才出現

- **決策**：`ImportCoordinator` 開始匯入後啟動 1 秒計時，仍未完成才顯示小型進度面板（`NSPanel`，非模態，顯示「正在匯入 3／20」與進度條，單檔大圖時為不定長度）；面板不阻擋其他視窗。
- **理由**：FR-041 要求超過 1 秒才顯示；快速匯入時不閃一下面板。

## D-10：彙總訊息只顯示一次

- **決策**：匯入結束後若有失敗，用單一 `NSAlert` 列出：成功數量、略過項目的數量（資料夾／網頁圖片等合併計數）、失敗檔案的檔名與原因（最多列 8 筆，其餘寫「…等 N 個」）。全部成功時不跳訊息。
- **理由**：FR-040、FR-045 要求彙總；逐檔對話框在拖曳 20 個檔案時不可用。

## D-10a：彙總規則做成核心的純函式

- **決策**：「要開哪些編輯器、列哪些失敗、要不要跳訊息」由核心的 `ImportReport.make(from:openEditors:)` 推導；`ImportCoordinator` 只負責把報告顯示成 `NSAlert` 並開啟編輯器。
- **理由**：這些規則（上限 5、最多列 8 筆、合併略過計數、全成功不跳訊息）不需要螢幕，依憲章原則 IV 必須自動化測試。

## D-11：開啟的編輯器上限 5

- **決策**：只有「開啟圖片…」與 Finder／Dock 入口（意圖是編輯）會開編輯器，且至多開前 5 個，其餘匯入後在訊息中提示；資料庫的「匯入…」與拖放不開編輯器（意圖是管理）。
- **理由**：FR-034；資料庫匯入的使用者要的是把圖放進去，自動彈出編輯器反而打斷。
- **補充**：開啟順序依使用者選取順序，最後一個開啟的視窗在最前。

## D-12：選單列、主選單、資料庫按鈕共用同一個 coordinator

- **決策**：`ImportCoordinator` 提供 `openImages()`（顯示選擇視窗後匯入並開編輯器）、`importImages()`（顯示選擇視窗後只匯入）與 `process(urls:openEditors:)`（拖放與 Finder 用）。`StatusItemController.Actions`、`AppMenuActions`、`LibraryViewModel` 只呼叫它。
- **理由**：避免三份相同流程；行為（上限、訊息）集中。
- **選單列從背景呼叫**：App 是 accessory（無 Dock 圖示），顯示 `NSOpenPanel` 前必須 `NSApp.activate(ignoringOtherApps:)`，否則視窗在其他 App 後面。

## D-13：資料庫的「匯入…」按鈕放在視窗內底部列

- **決策**：資料庫視圖底部狀態列右側加入「匯入…」按鈕，並在「檔案」選單提供 ⇧⌘I。
- **理由**：視窗以 `NSHostingController` 承載；在這種視窗用 SwiftUI `.toolbar` 的行為在 macOS 14 上不夠可預期。底部列按鈕行為確定，且仍滿足「視窗中的匯入功能」。規格相應改為「視窗內的按鈕」。
- **替代方案**：自建 `NSToolbar`——為單一按鈕增加一整層 AppKit 程式碼，否決。

## D-14：拖放使用 SwiftUI `dropDestination(for: URL.self)`

- **決策**：套用在 `LibraryView` 最外層（空白狀態與格狀清單都涵蓋），`isTargeted` 驅動一圈高亮邊框作為可放下的回饋。收到的 URL 先以 `isFileURL` 分流：非檔案 URL 計入「不支援」，不嘗試下載。
- **理由**：原生、無需 AppKit 手寫 `NSDraggingDestination`；網頁圖片通常以 `http(s)` URL 拖入，剛好能在這裡被辨識並拒絕（憲章原則 II）。
- **限制**：只接受「檔案 URL」；從瀏覽器拖出圖片資料（沒有 URL）時不會觸發此目標，使用者看到不可放下的游標，等同被拒絕，不另外處理。

## D-15：Finder「打開方式」與 Dock 拖放

- **決策**：
  - `Config/Info-DocumentTypes.plist` 宣告 `CFBundleDocumentTypes`：`LSItemContentTypes = [public.image]`、`CFBundleTypeRole = Editor`、`LSHandlerRank = Alternate`（出現在「打開方式」，但**不**搶預設，滿足 FR-047）。
  - 專案設定 `GENERATE_INFOPLIST_FILE = YES` 與 `INFOPLIST_FILE = Config/Info-DocumentTypes.plist` 並用，Xcode 會合併。
  - `AppDelegate` 實作 `application(_:open:)` → `ImportCoordinator.process(urls:openEditors: true)`。
  - 冷啟動時 `application(_:open:)` 可能早於環境就緒，先暫存 URL，`applicationDidFinishLaunching` 結尾再處理。
- **驗證**：建置後檢查產出的 `Info.plist` 同時含自動產生的鍵（如 `LSUIElement`）與 `CFBundleDocumentTypes`；`lsregister -dump` 或 Finder 實測確認「打開方式」出現且預設程式未改變。
- **替代方案**：完全改用手寫 `Info.plist` 取代自動產生——要搬移所有 `INFOPLIST_KEY_*` 並影響發行流程的版本號覆寫，風險大，否決。

## D-16：匯入項目的 `scale` 與縮放顯示

- **決策**：`Capture.scale` 一律記 1.0；編輯器以影像像素為單位顯示（功能 001 已是如此），不讀檔案內 DPI。
- **理由**：假設中已定「一個影像像素對應一個編輯器像素」；螢幕擷取的 `scale` 只用在複製到剪貼簿時換算點尺寸，匯入圖用 1.0 是安全的。

## D-17：本地化

- **決策**：新增字串全部進 `Localizable.xcstrings`（key 為中文原文）並補 `en`；清單見 [quickstart.md](./quickstart.md) 的「字串檢核」。

## D-18：效能量測

- **決策**：在 `PerformanceTests` 新增 12 百萬像素（4000×3000）JPEG 的 `ImageImporter.load` ＋ `LibraryStore.create` 耗時測試，Debug 與 Release 都跑；門檻 1 秒內留出編輯器開啟時間，核心步驟目標 ≤ 700 毫秒。
- **理由**：SC-009 的主要成本是解碼與 PNG 編碼，二者都在核心，可自動化量測。
