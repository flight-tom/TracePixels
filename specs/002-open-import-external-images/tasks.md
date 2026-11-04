---

description: "開啟與匯入外部圖片功能的任務清單"
---

# 任務：開啟與匯入外部圖片

**輸入**：`/specs/002-open-import-external-images/` 下的設計文件

**先決條件**：plan.md、spec.md、research.md、data-model.md、contracts/、quickstart.md

**測試**：依憲章原則 IV，`TracePixelsCore` 的邏輯（讀取、尺寸上限、方向、透明度、批次彙總、半成品防護）MUST 先寫測試、確認失敗，再實作。需要視窗、檔案選擇視窗、拖放或 Finder 的行為，以 [quickstart.md](./quickstart.md) 的手動程序驗證。

**組織方式**：任務依使用者故事分組。因為四個入口共用同一條匯入管線，管線本身放在 Phase 2（基礎），各故事只負責自己的入口與介面。

## 格式：`[ID] [P?] [Story] 說明`

- **[P]**：可平行執行（不同檔案、不依賴未完成的任務）
- **[Story]**：所屬使用者故事（US1～US4）
- 說明中包含精確的檔案路徑

## 路徑慣例

- `Core/` = `Packages/TracePixelsCore/Sources/TracePixelsCore/`
- `CoreTests/` = `Packages/TracePixelsCore/Tests/TracePixelsCoreTests/`
- `App/` = `TracePixels/`（App target），`AppTests/` = `TracePixelsTests/`

---

## Phase 1：設定

**目的**：確認基準線與測試素材工具。

- [X] T001 在 `Packages/TracePixelsCore` 執行 `swift test`，確認既有測試在分支起點全部通過（記錄通過數量作為回歸基準）
- [X] T002 [P] 擴充 `CoreTests/Support/TestImages.swift`：新增把 `CGImage` 寫成檔案的輔助函式，支援 PNG／JPEG／TIFF／GIF／BMP／HEIC（以 `CGImageDestination`）、可指定 EXIF `Orientation`（1～8）、可指定色彩空間（例如 Display P3）、可建立多格 GIF，以及可在暫存目錄建立「內容是文字的假 `.png`」、截斷的 PNG、資料夾與唯讀檔；所有輔助函式回傳檔案 URL，並提供清理暫存目錄的方式。HEIC 輔助函式先偵測 `CGImageDestinationCopyTypeIdentifiers()` 是否含 HEIC，不支援時回傳 `nil`，由呼叫的測試以 `XCTSkip` 略過（其餘格式照跑）

---

## Phase 2：基礎（阻擋所有使用者故事）

**目的**：匯入管線（核心）與 App 端的共用協調器。**此階段完成前，任何入口都無法運作。**

**⚠️ 關鍵**：核心測試（T003～T006，含 T005a）必須先寫並確認失敗，才能開始 T007～T010a。

### 核心測試（先寫，先失敗）

- [X] T003 [P] 在 `CoreTests/ModelCodingTests.swift` 新增 `CaptureSource.imported(fileName:)` 的測試：編碼為 `{"type":"imported","fileName":"photo.jpg"}`；解碼往返相等；`fileName` 缺漏時解碼為空字串；整個 `Capture` 含 imported 來源時 JSON 往返後 `schemaVersion` 仍為 1
- [X] T004 [P] 建立 `CoreTests/ImageImporterTests.swift`，涵蓋 contracts/core-api.md 的全部保證：
  - PNG／JPEG／TIFF／GIF／BMP／HEIC 各一，`image.width/height` 與來源尺寸相同（SC-011）；GIF 多格只取第 0 格
  - 含 alpha 的 PNG 載入後仍有 alpha，且像素值逐一相同
  - EXIF Orientation 6（及 5～8）的 JPEG：寬高對調，且左上角標記色出現在轉正後的正確位置
  - 方向為 1 的圖，兩條讀取路徑（直接解碼 vs. 縮圖 API）像素逐一相同（防止無謂重新取樣）
  - Display P3 色彩空間的圖載入後色彩空間名稱保留
  - 超過上限：單邊 16385 → `.tooLarge`；總像素 > 200 百萬（例如 14200×14200 的 8 位元灰階 PNG，或手工構造只有 IHDR 的 PNG 檔）→ `.tooLarge`，並確認是在解碼前依屬性判定
  - 恰在上限（16384×1、1×16384）可載入
  - 資料夾、不存在的路徑、`http://` URL → `.notAFile`；文字檔 → `.unsupportedFormat`；內容為文字的假 `.png` → `.unsupportedFormat`；簽名正確但被截斷的 PNG → `.corrupt`；無讀取權限的檔案 → `.unreadable`
  - 呼叫前後原檔的內容雜湊與修改時間相同（FR-035、SC-010）
  - `fileName` 含空白、中文、emoji 與超長檔名時原樣回傳（只含檔名，不含目錄）
- [X] T005 [P] 建立 `CoreTests/LibraryImporterTests.swift`：
  - 有效檔 ×3 → `imported.count == 3`，順序與輸入一致，來源皆為 `.imported(fileName:)`、`scale == 1.0`、`pixelSize` 正確
  - 混合輸入（有效 ×2、假 `.png`、文字檔、資料夾、`http://` URL）→ `imported` 2 筆；`failures` 各自分類正確；`skippedNonFileCount` 為資料夾加 URL 的筆數；`LibraryStore.list()` 只有 2 筆可用項目、無不可用項目、目錄中無 `*.importing`（SC-013）
  - 同一檔案出現兩次 → 兩個不同 id 的項目
  - 匯入後刪除原檔，`LibraryStore.load(id)` 仍成功（FR-036）
  - 進度回呼依序回報 `done`／`total`／`currentName`
  - 取消：在第 2 個檔案前取消 → 已完成的保留、`cancelled == true`、無殘留
  - 載入後再 `LibraryStore.save` 一次標註，`image.png` 內容雜湊不變（匯入影像不可變）
  - 資料庫目錄不可寫（例如權限設為唯讀）時，該檔歸入 `.storageFailed`，其餘檔案不受影響、無殘留
  - 往返：匯入 → 加一個標註並 `save` → 以新的 `LibraryStore` 實例對同一目錄 `load` → 標註仍在且可編輯（SC-014）
  - HEIC 項目在編碼器不可用時 `XCTSkip`
- [X] T005a [P] 建立 `CoreTests/ImportReportTests.swift`（先寫、先失敗）：對 `ImportReport.make(from:openEditors:)` 斷言——成功 7 個且 `openEditors == true` → `editorsToOpen` 為前 5 個、`onlyInLibraryCount == 2`；`openEditors == false` → `editorsToOpen` 為空、`onlyInLibraryCount == 0`；失敗 12 筆 → `listedFailures` 8 筆、`unlistedFailureCount == 4`；`notAFile` 不進 `listedFailures` 而進 `skippedNonFileCount`；全成功且 ≤ 5 個且全開啟 → `needsAlert == false`；任一失敗、略過或僅在資料庫 → `needsAlert == true`
- [X] T006 [P] 在 `CoreTests/LibraryStoreTests.swift` 新增：
  - `create` 完成後資料庫目錄只有 `<UUID>.tracepixelscapture`，沒有 `*.importing`
  - 模擬暫存目錄中途失敗（例如先在目標位置放同名檔案使改名失敗，或注入失敗的寫入）→ `create` 丟錯、資料庫無任何新項目、無殘留
  - 手動放入殘留的 `abc.importing/` 目錄：`list()` 不含它；`removeStaleStaging()` 回傳 1 並移除；正式項目不受影響
  - `totalSize()` 包含暫存目錄的大小
  - `list()` 對 imported 項目回傳 `sourceFileName`，對區域擷取為 `nil`，對損毀項目為 `nil`

### 核心實作

- [X] T007 在 `Core/Model/Capture.swift` 的 `CaptureSource` 新增 `case imported(fileName: String)`，更新 `CodingKeys` 與 `init(from:)`／`encode(to:)`：`type` 為 `"imported"`，`fileName` 缺漏時為 `""`；其餘既有行為（未知型別回落 `region`）不變。使 T003 通過
- [X] T008 在 `Core/Persistence/LibraryStore.swift`：(a) `LibraryEntry` 新增 `public let sourceFileName: String?`，`list()` 對可用的 imported 項目填入檔名、其餘為 nil；(b) `create` 改為在資料庫目錄建立 `<UUID>.importing/`，寫齊 `image.png`、`document.json`、`thumbnail.jpg` 後以單次 `moveItem` 改名為 `<UUID>.tracepixelscapture/`，任何步驟失敗都移除暫存目錄並重新丟出錯誤；(c) 新增 `@discardableResult public func removeStaleStaging() -> Int`，只移除副檔名為 `importing` 的目錄；`list()` 維持只認 `tracepixelscapture`。使 T006 與既有 `LibraryStoreTests`、`ReopenRoundTripTests` 通過
- [X] T009 建立 `Core/Persistence/ImageImporter.swift`：定義 `ImportLimits`（`maxSide = 16384`、`maxPixels = 200_000_000`）、`ImportFailure`（`notAFile`／`unreadable`／`unsupportedFormat`／`corrupt`／`tooLarge(width:height:)`／`storageFailed`，符合 `Error, Equatable, Sendable`；`storageFailed` 只由 `LibraryImporter` 使用）、`LoadedImage`、`ImageImporter.load(from:)`。流程依 research.md D-04／D-06：先確認為本機一般檔案；以 `CGImageSourceCreate(url)` 取得來源；用 `CGImageSourceCopyPropertiesAtIndex` 讀 `PixelWidth`／`PixelHeight`／`Orientation`（方向 5～8 寬高對調），**在解碼前**以 `Int` 運算比對 `ImportLimits`；方向為 1 時用 `CGImageSourceCreateImageAtIndex(index 0)`，否則用 `CGImageSourceCreateThumbnailAtIndex` 搭配 `kCGImageSourceCreateThumbnailWithTransform`、`kCGImageSourceCreateThumbnailFromImageAlways`、`kCGImageSourceThumbnailMaxPixelSize` = 套用方向後的較長邊；不做色彩轉換或去 alpha；不寫入或鎖定原檔。使 T004 通過
- [X] T010 建立 `Core/Persistence/LibraryImporter.swift`：定義 `ImportFailureItem`、`ImportResult`（含 `skippedNonFileCount`）、`ImportProgress`、`LibraryImporter.importFiles(_:progress:)`。依 research.md D-08：循序處理；解碼在呼叫端的執行情境進行、只有 `LibraryStore.create` 進入 actor；以 `.imported(fileName: url.lastPathComponent)`、`scale: 1.0` 建立項目；單檔失敗收集到 `failures` 而不中斷（`LibraryStore.create` 丟出的任何錯誤歸入 `.storageFailed`）；每檔之間檢查 `Task.isCancelled`；`failures[].name` 對檔案 URL 為檔名、對非檔案 URL 為 `absoluteString`。使 T005 通過。完成後在 `Packages/TracePixelsCore` 跑全部 `swift test`（Debug），確認無回歸

### App 共用協調器

- [X] T010a 建立 `Core/Persistence/ImportReport.swift`：依 data-model.md 的 `ImportReport` 與 contracts/core-api.md 實作純函式 `make(from:openEditors:)`（`maxEditors = 5`、`maxListedFailures = 8`）。使 T005a 通過
- [ ] T011 [P] 建立 `App/Library/ImportProgressPanel.swift`：非模態 `NSPanel`（不搶焦點、浮在其他視窗上），顯示「正在匯入 N／M」與進度條，單檔時為不定長度；提供 `show()`、`update(done:total:)`、`close()`。字串先以 `String(localized:)` 撰寫（zh-TW）
- [ ] T012 建立 `App/Library/ImportCoordinator.swift`（`@MainActor final class`，持有 `LibraryStore`、`EditorWindowRegistry`）：實作 `process(urls: [URL], openEditors: Bool) async`——啟動 1 秒計時，仍未完成才顯示 `ImportProgressPanel`（研究 D-09）；呼叫 `LibraryImporter.importFiles`；有成功項目就 `NotificationCenter.default.post(name: .libraryDidChange, object: nil)`；`editorsToOpen` 的項目依序以 `library.load` 後 `editors.open(capture:image:)` 開啟；結束後以 `ImportReport.make(from:openEditors:)` 取得報告（T010a），**規則不在此處重寫**：依 `editorsToOpen` 開編輯器，依 `needsAlert` 以單一 `NSAlert` 顯示報告內容（`ImportFailure` 對應 data-model.md 的六種 zh-TW 原因文字）。同時避免兩批匯入同時彈出多個彙總視窗（以序列化的 Task 排隊）
- [ ] T013 在 `App/App/AppDelegate.swift` 建立 `ImportCoordinator` 並持有；`applicationDidFinishLaunching` 在建立環境後呼叫 `environment.library.removeStaleStaging()`（背景 Task，不阻擋啟動）；`App/Library/LibraryWindowController.swift` 的 `init` 接收 `ImportCoordinator` 並傳給 `LibraryViewModel`（`LibraryViewModel.init` 新增 `importer: ImportCoordinator` 參數，既有呼叫端一併更新）。完成後 `xcodebuild … build` 確認可編譯

**檢查點**：核心匯入管線與協調器就緒；各入口可以開始實作。

---

## Phase 3：使用者故事 1 — 從選單列開啟外部圖片進行編輯（優先級：P1）🎯 MVP

**目標**：選單列與主選單的「開啟圖片…」（`⌘O`）→ 選檔 → 編輯器開啟。

**獨立測試**：quickstart.md M7。

- [ ] T014 [P] [US1] 更新 `AppTests/MainMenuTests.swift`：測試用 `Target` 補上 `openImage(_:)`、`importImages(_:)`；`testEveryActionInThePlanHasAMenuItem` 的必要清單加入「開啟圖片…」「匯入…」；新增測試斷言「開啟圖片…」快速鍵為 `⌘O`、「匯入…」為 `⇧⌘I`，兩者在「檔案」選單，且整份主選單的快速鍵組合仍無重複。先確認測試失敗
- [ ] T015 [US1] 在 `App/Library/ImportCoordinator.swift` 新增共用的檔案選擇輔助與兩個入口 `openImages() async`、`importImages() async`（後者供 US2 使用，選擇視窗標題「匯入圖片」、確認鈕「匯入」，確認後呼叫 `process(urls:openEditors: false)`）。`openImages()`：先 `NSApp.activate(ignoringOtherApps: true)`，顯示 `NSOpenPanel`（`allowedContentTypes = [.image]`、`allowsMultipleSelection = true`、`canChooseDirectories = false`、標題「開啟圖片」、確認鈕「開啟」）；取消直接返回、不產生副作用；確認後呼叫 `process(urls:openEditors: true)`
- [ ] T016 [P] [US1] 在 `App/App/StatusItemController.swift`：`Actions` 新增 `openImage`，選單在「擷取全螢幕」之後、分隔線之前加入「開啟圖片…」（`keyEquivalent: "o"`），對應 `@objc` 方法呼叫 `actions.openImage()`
- [ ] T017 [US1] 在 `App/App/MainMenuBuilder.swift` 的 `AppMenuActions` 新增 `openImage(_:)` 與 `importImages(_:)`；「檔案」選單在「擷取全螢幕」之後加入「開啟圖片…」（`⌘O`、target 為 `appTarget`），並在「開啟資料庫…」之後加入「匯入…」（`⇧⌘I`）。在 `AppDelegate.swift` 實作兩個 `@objc` 方法（`MainActor.assumeIsolated` 呼叫 coordinator 的 `openImages()`／`importImages()`），並在 `applicationDidFinishLaunching` 的 `Actions` 設定 `actions.openImage`。`importImages(_:)` 同樣呼叫 coordinator 的 `importImages()`（T015 已提供）
- [ ] T018 [US1] 執行 `xcodebuild … test`：`MainMenuTests` 通過（T014）；手動依 quickstart.md M7 驗證並記錄結果（無法在本環境驗證的項目標示「需審查者手動驗證」）

**檢查點**：使用者故事 1 可獨立運作——可從選單列／`⌘O` 開啟外部圖片並完整編輯。

---

## Phase 4：使用者故事 2 — 在資料庫中匯入外部圖檔（優先級：P1）

**目標**：資料庫的「匯入…」按鈕與 `⇧⌘I`；匯入項目可辨識來源。

**獨立測試**：quickstart.md M8。

- [ ] T019 [US2] 確認 `ImportCoordinator.importImages()`（T015）在「只匯入、不開編輯器」下行為正確：成功項目出現在資料庫、不開任何編輯器、彙總訊息規則與 `openImages()` 一致；必要時補強
- [ ] T020 [US2] 在 `App/Library/LibraryViewModel.swift` 新增 `importImages()`（呼叫 `importer.importImages()`），供視圖的按鈕使用
- [ ] T021 [US2] 修改 `App/Library/LibraryView.swift`：(a) 底部列右側加入「匯入…」按鈕（快速鍵由主選單負責，按鈕本身不加快速鍵；提供 `accessibilityLabel`）；(b) `LibraryCell` 在日期旁對 `entry.sourceFileName != nil` 的項目顯示 `square.and.arrow.down` 小圖示，整個卡片加 `.help(fileName)`，VoiceOver 標籤附上「匯入自 \(檔名)」；(c) 空白狀態說明改為「擷取的影像會自動出現在這裡。也可以按「匯入…」或把圖片拖曳到這個視窗。」（FR-046）；(d) 底部計數文字「N 個擷取」維持（匯入項目也算入）
- [ ] T022 [US2] 手動依 quickstart.md M8 驗證並記錄結果；確認匯入完成後資料庫視窗不需手動重新整理即出現新項目（`.libraryDidChange`）

**檢查點**：使用者故事 1 與 2 皆可獨立運作。

---

## Phase 5：使用者故事 3 — 把外部圖檔拖曳進資料庫（優先級：P2）

**目標**：圖片檔可直接拖進資料庫視窗匯入，有可放下回饋與混合內容的彙總。

**獨立測試**：quickstart.md M9。

- [ ] T023 [US3] 在 `App/Library/LibraryView.swift` 最外層加上 `.dropDestination(for: URL.self) { urls, _ in … } isTargeted: { … }`：以 `@State` 的 `isDropTargeted` 在拖曳經過時於整個視圖疊上強調色圓角邊框（空白狀態與格狀清單皆涵蓋）；放開後呼叫 `viewModel.importDropped(urls)` 並回傳 `true`
- [ ] T024 [US3] 在 `App/Library/LibraryViewModel.swift` 新增 `importDropped(_ urls: [URL])`：不論檔案或非檔案 URL 一律交給 `importer.process(urls:openEditors: false)`（分類與彙總由核心與協調器負責，非檔案 URL 會被分類為 `notAFile` 且不下載）。為拖放區域加上 VoiceOver 提示（`accessibilityHint`：「可拖曳圖片檔到此匯入」）
- [ ] T025 [US3] 手動依 quickstart.md M9 驗證並記錄結果；其中第 5 項（瀏覽器網頁圖片）以網路監視確認沒有任何連線

**檢查點**：使用者故事 1～3 皆可獨立運作。

---

## Phase 6：使用者故事 4 — Finder「打開方式」與拖到 Dock 圖示（優先級：P3）

**目標**：從 Finder 與 Dock 開啟圖片，不改變預設程式。

**獨立測試**：quickstart.md M11。

- [ ] T026 [P] [US4] 建立 `Config/Info-DocumentTypes.plist`：僅含 `CFBundleDocumentTypes` 一個項目——`CFBundleTypeName` = `Image`、`CFBundleTypeRole` = `Editor`、`LSHandlerRank` = `Alternate`、`LSItemContentTypes` = [`public.image`]。檔案放在 `Config/`，不在 `TracePixels/` 同步群組內（plan.md 結構決策）
- [ ] T027 [US4] 修改 `TracePixels.xcodeproj/project.pbxproj`：App target 的 Debug 與 Release 兩個組態都加上 `INFOPLIST_FILE = Config/Info-DocumentTypes.plist;`，維持 `GENERATE_INFOPLIST_FILE = YES`。建置後以 `plutil -p build/DerivedData/Build/Products/Debug/TracePixels.app/Contents/Info.plist` 確認同時含 `LSUIElement`、`CFBundleDocumentTypes` 與 `LSHandlerRank = Alternate`；再建置 Release（`ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO`，與發行工作流程相同）確認版本號覆寫與合併後的 Info.plist 都正常
- [ ] T028 [US4] 在 `App/App/AppDelegate.swift` 實作 `application(_ sender: NSApplication, open urls: [URL])`：環境（`importCoordinator`）尚未就緒時把 URL 存入 `pendingOpenURLs`，並在 `applicationDidFinishLaunching` 結尾處理；就緒後直接呼叫 `importCoordinator.process(urls: urls, openEditors: true)`。XCTest 宿主（`XCTestConfigurationFilePath`）下不處理
- [ ] T029 [US4] 手動依 quickstart.md M11 驗證並記錄結果（含：預設程式未被更動、冷啟動不出現多餘視窗）

**檢查點**：全部四個使用者故事皆可獨立運作。

---

## Phase 7：收尾與跨領域事項

- [ ] T030 [P] 在 `CoreTests/PerformanceTests.swift` 新增 12 百萬像素（4000×3000）JPEG 的 `ImageImporter.load` ＋ `LibraryStore.create` 耗時測試，核心步驟 ≤ 700 毫秒（SC-009）；另新增 20 張一般圖片的 `LibraryImporter.importFiles` 總耗時 ≤ 10 秒（SC-012）。`swift test` 與 `swift test -c release` 皆須通過
- [ ] T031 [P] 更新 `App/Resources/Localizable.xcstrings`：依 quickstart.md「字串檢核」清單，從 `build/DerivedData/**/TracePixels.build/**/*.stringsdata` 取出所有 key 比對缺漏，補齊 `en` 翻譯（含六種匯入失敗原因、進度、彙總訊息與 VoiceOver 標籤）
- [ ] T032 [P] 更新功能 001 的文件以反映新行為：`specs/001-screenshot-capture-annotation/contracts/library-format.md` 加上指向本功能 `contracts/library-format.md` 的說明；`contracts/commands.md` 的選單列項目與「檔案」選單加入「開啟圖片…」「匯入…」；`contracts/core-api.md` 加上指向本功能 `contracts/core-api.md` 的說明
- [ ] T033 [P] 更新 `CLAUDE.md`：架構段落補充匯入管線（`ImageImporter`／`LibraryImporter`、`CaptureSource.imported`、暫存目錄建立）、`Config/Info-DocumentTypes.plist` 與 `INFOPLIST_FILE` 的合併方式、App 端的 `ImportCoordinator`；注意事項補上「新增使用者可見字串後同步 quickstart」的既有規則適用於本功能的 quickstart
- [ ] T034 建立 `specs/002-open-import-external-images/verification.md`，格式比照功能 001 的 `verification.md`：自動化驗證結果（各測試數量與通過狀態）、規格對照（FR-031～FR-049、SC-009～SC-015 各自的驗證方式與結果）、需審查者手動驗證的清單（M7～M11 中本環境無法驗證者）、已知限制（舊版重新保存會把 imported 來源寫回 region；網頁圖片資料拖放不支援）
- [ ] T035 全面驗證：`swift test`（Debug）、`swift test -c release --filter PerformanceTests`、`xcodebuild … test`、`xcodebuild … build`（Debug 與 Release Universal）皆通過；`git status` 確認沒有 `build/` 以外的非預期檔案、原有 `.gitignore` 規則未被破壞
- [ ] T036 依憲章原則 VII 交付：在功能分支 `002-open-import-external-images` 上以繁體中文提交（分段 commit，結尾加上 Co-Authored-By 歸屬行），推送分支並建立 Pull Request（標題與描述皆為 zh-TW，結尾加上 Claude Code 產生標註）；**不自行合併、不推主要分支**。若沒有可用的遠端或推送被拒，改為回報已嘗試的做法與阻礙

---

## 相依與執行順序

### 階段相依

- **Phase 1（設定）**：無相依，立即開始
- **Phase 2（基礎）**：依賴 Phase 1；**阻擋所有使用者故事**。內部順序：測試 T003～T006 → 核心實作 T007～T010 → App 協調器 T011～T013
- **Phase 3～6（使用者故事）**：皆依賴 Phase 2
  - US1（P1）與 US2（P1）：共用 `ImportCoordinator.swift` 與 `AppDelegate.swift`，**建議循序**（US1 → US2）
  - US3（P2）依賴 US2 的 `LibraryView`／`LibraryViewModel` 變更（T020、T021），故排在 US2 之後
  - US4（P3）只依賴 Phase 2；plist 與 pbxproj（T026、T027）可與 US1～US3 平行，但 T028 與 T013、T017 都改 `AppDelegate.swift`，須排在 T017 之後再做
- **Phase 7（收尾）**：依賴所有想交付的故事完成

### 故事間相依

- US1：Phase 2 之後可獨立（MVP）
- US2：Phase 2 之後可獨立；與 US1 只共用 coordinator 檔案
- US3：需要 US2 的視圖與 view model 修改
- US4：Phase 2 之後可獨立

### 故事內順序

測試先行（核心在 Phase 2；App 端選單測試 T014）→ 模型／協調器 → 介面 → 手動驗證。

### 平行機會

- Phase 1：T002 與 T001 可同時進行
- Phase 2 測試：T003、T004、T005、T005a、T006 為不同檔案，可同時撰寫；T011 與核心實作可同時進行
- US4 的 T026、T027 與 US1～US3 的任何工作可同時進行（T028 不行，見上）
- Phase 7：T030、T031、T032、T033 為不同檔案，可同時進行

### 平行執行範例：Phase 2 測試

```text
T003 CoreTests/ModelCodingTests.swift      （imported 來源編解碼）
T004 CoreTests/ImageImporterTests.swift    （單檔讀取與驗證）
T005 CoreTests/LibraryImporterTests.swift  （批次匯入）
T005a CoreTests/ImportReportTests.swift   （彙總與編輯器上限規則）
T006 CoreTests/LibraryStoreTests.swift     （暫存目錄與殘留清理）
```

## 實作策略

### MVP 優先（只做使用者故事 1）

1. 完成 Phase 1、Phase 2（含全部核心測試與管線）
2. 完成 Phase 3（US1：選單列／`⌘O` 開啟圖片）
3. **停下來驗證**：M7，確認原檔未被改動、可標註並複製
4. 此時已交付「不必先截圖就能標註任何圖片」的核心價值

### 漸進式交付

1. Phase 2 → 管線就緒
2. + US1 → 選單開啟（MVP）
3. + US2 → 資料庫匯入
4. + US3 → 拖放
5. + US4 → Finder／Dock
6. 收尾 → 效能、翻譯、文件、驗證、PR

## 備註

- 核心測試（T003～T006）必須在對應實作前撰寫並確認失敗（憲章原則 IV）。
- 每完成一個任務或一組邏輯相關的任務就提交一次；提交訊息使用繁體中文。
- T004 中「假 `.png`」的分類（`corrupt` 或 `unsupportedFormat`）依 ImageIO 的實際行為決定，並同步 `data-model.md` 與 `contracts/core-api.md` 的說明，避免文件與行為不一致。
- 若 T027 發現 `INFOPLIST_FILE` 與 `GENERATE_INFOPLIST_FILE` 並用導致合併失敗，回到 research.md D-15 的替代方案評估，並先更新 research.md 再改做法。
