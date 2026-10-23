---

description: "截圖與標註功能的任務清單"
---

# 任務：截圖與標註

**輸入**：`/specs/001-screenshot-capture-annotation/` 下的設計文件

**先決條件**：plan.md、spec.md、research.md、data-model.md、contracts/、quickstart.md

**測試**：依憲章原則 IV，`SnagItCore` 的邏輯（標註模型、幾何、復原、持久化、渲染、匯出、遮蔽）MUST 先寫測試再實作。需要螢幕或視窗伺服器的 UI 與擷取行為以 [quickstart.md](./quickstart.md) 的手動程序驗證。

**組織方式**：任務依使用者故事分組，使每個故事都能獨立實作與測試。

## 格式：`[ID] [P?] [Story] 說明`

- **[P]**：可平行執行（不同檔案、不依賴未完成的任務）
- **[Story]**：所屬使用者故事（US1～US5）
- 說明中包含精確的檔案路徑

## 路徑慣例

- 核心套件：`Packages/SnagItCore/Sources/SnagItCore/`，測試在 `Packages/SnagItCore/Tests/SnagItCoreTests/`
- App target：`SnagItForever/`
- 以下 `Core/` 代表 `Packages/SnagItCore/Sources/SnagItCore/`，`CoreTests/` 代表 `Packages/SnagItCore/Tests/SnagItCoreTests/`

---

## Phase 1：設定（共用基礎建設）

**目的**：專案初始化與基本結構

- [X] T001 建立 `Packages/SnagItCore/Package.swift`（swift-tools-version 6.0、platforms `.macOS(.v14)`、library 產品 `SnagItCore`、測試 target `SnagItCoreTests`、Swift 6 語言模式），並建立 `Model/`、`History/`、`Rendering/`、`Persistence/` 子目錄與一個可編譯的占位檔
- [X] T002 [P] 建立 App target 骨架：以 `GENERATE_INFOPLIST_FILE` 產生 Info.plist（`INFOPLIST_KEY_LSUIElement` 為真，開發語言 `zh-Hant`，避免同步群組重複處理 Info.plist），並在儲存庫根目錄建立 `SnagItForever.entitlements`（不啟用 App Sandbox）
- [X] T003 建立 `SnagItForever.xcodeproj/project.pbxproj` 與共享 scheme `SnagItForever.xcscheme`：使用檔案系統同步群組指向 `SnagItForever/`、以 `XCLocalSwiftPackageReference` 引用 `Packages/SnagItCore`、部署目標 macOS 14.0、App target 使用 Swift 5 語言模式、啟用 Hardened Runtime、ad-hoc 簽署（`CODE_SIGN_IDENTITY = -`）
- [X] T004 [P] 建立 `SnagItForever/Resources/Assets.xcassets`（AppIcon 占位、AccentColor）與 `SnagItForever/Resources/Localizable.xcstrings`（開發語言 `zh-Hant`，並含 `en`）
- [X] T005 建立最小的 App 進入點 `SnagItForever/App/main.swift`（明確啟動 `NSApplication`）與 `SnagItForever/App/AppDelegate.swift`；驗證 `swift test`（於 `Packages/SnagItCore`）與 `xcodebuild -project SnagItForever.xcodeproj -scheme SnagItForever -configuration Debug -destination 'platform=macOS' build` 皆成功

---

## Phase 2：基礎（阻擋所有使用者故事的先決條件）

**目的**：所有使用者故事都依賴的核心資料模型、資料庫與 App 外殼

**⚠️ 重要**：此階段完成前，不可開始任何使用者故事

### 先寫測試（必須先失敗）

- [X] T006 [P] 撰寫 `CoreTests/GeometryTests.swift`：點、尺寸、矩形的正規化（負寬高）、交集、包含、夾限
- [X] T007 [P] 撰寫 `CoreTests/ModelCodingTests.swift`：`Capture` 與 10 種 `Annotation.Kind` 的 JSON 往返；驗證規則——`lineWidth` 範圍 1–64、`fontSize` 範圍 8–400、`blur`／`pixelate` 強度小於 8 時一律提升為 8、`pixelSize` 兩邊皆 > 0、`crop` 必須完全落在 `0..pixelSize` 內且寬高 ≥ 1、`annotations` 的 `id` 不可重複；未知 `kind.type` 時該標註被略過但保留原始 JSON
- [X] T008 [P] 撰寫 `CoreTests/LibraryStoreTests.swift`：建立、載入、儲存、刪除、`list()` 由新到舊、損毀目錄被隔離為不可用且不影響其他項目、`schemaVersion` 高於支援版本時為不可用且不被覆寫、`image.png` 位元組在儲存後保持不變、縮圖遺失時重建；並建立共用的 `CoreTests/Support/TestImages.swift`（產生純色、棋盤與漸層測試影像）

### 實作

- [X] T009 [P] 實作 `Core/Model/Geometry.swift`：`PixelPoint`、`PixelSize`、`PixelRect`（左上為原點的像素座標，皆為 `Codable`、`Sendable`）
- [X] T010 [P] 實作 `Core/Model/Style.swift` 與 `Core/Model/Annotation.swift`：`RGBAColor`、`Style`（`lineWidth` 1–64、`fontSize` 8–400）、`Annotation`、`Annotation.Kind`（arrow、line、rectangle、ellipse、pen、highlighter、text、step、blur、pixelate；`blur`／`pixelate` 強度 < 8 時提升為 8）與保留未知類型的解碼
- [X] T011 實作 `Core/Model/Capture.swift`：`Capture`、`CaptureSource`、`Finish`、`schemaVersion` 與驗證（相依 T009、T010）
- [X] T012 實作 `Core/Persistence/LibraryStore.swift` 與 `Core/Persistence/Thumbnailer.swift`：依 [contracts/library-format.md](./contracts/library-format.md) 與 [contracts/core-api.md](./contracts/core-api.md)，`<UUID>.snagitcapture/` 目錄、原子寫入、縮圖長邊 320 px；跨 actor 傳遞的影像以 `SendableImage: @unchecked Sendable` 包裝（見 core-api.md）（相依 T011）
- [X] T013 [P] 實作 `SnagItForever/Settings/Preferences.swift`：以 `UserDefaults` 封裝 data-model.md 中的偏好設定鍵與預設值（`hotKey`＝`⌃⇧4`、`afterCapture`＝`[openEditor]`、`saveFolder`＝`~/Pictures/SnagItForever`、`jpegQuality`＝0.9 等）
- [X] T014 [P] 實作 `SnagItForever/App/StatusItemController.swift`（選單列圖示與選單項目，依 [contracts/commands.md](./contracts/commands.md)）與 `SnagItForever/App/ActivationPolicyManager.swift`（無視窗時隱藏 Dock 圖示、有編輯器或資料庫視窗時顯示，FR-029）
- [X] T015 實作 `SnagItForever/App/AppEnvironment.swift`：建立共用的 `LibraryStore`（目錄 `~/Library/Application Support/SnagItForever/Library/`）與 `Preferences`，並接上 `AppDelegate`（相依 T012、T013）

**檢查點**：基礎就緒——`swift test` 全數通過，App 可啟動並顯示選單列圖示；使用者故事可開始實作

---

## Phase 3：使用者故事 1 — 擷取螢幕截圖（優先級：P1）🎯 MVP

**目標**：以全域快速鍵或選單列擷取區域、視窗、全螢幕，擷取結果自動加入資料庫並依偏好開啟編輯器、複製或儲存。

**獨立測試**：觸發三種擷取模式，確認影像出現在編輯器中；Esc 取消無副作用；缺少權限時顯示說明（quickstart M1）。

### 先寫測試

- [X] T016 [P] [US1] 撰寫 `CoreTests/CaptureGeometryTests.swift`：螢幕點座標選取矩形轉為顯示器像素 `sourceRect`（含 2.0 縮放、多螢幕原點偏移、選取超出邊界時夾限、拖曳方向反向的正規化、選取橫跨多個顯示器時限制在拖曳起點所在的顯示器內）

### 實作

- [X] T017 [US1] 實作 `Core/Model/CaptureGeometry.swift`，使 T016 通過
- [X] T018 [P] [US1] 實作 `SnagItForever/Capture/ScreenCapturePermission.swift` 與 `SnagItForever/Capture/PermissionGuideWindow.swift`：`CGPreflightScreenCaptureAccess`／`CGRequestScreenCaptureAccess`，缺少時顯示說明視窗與開啟「螢幕與系統音訊錄製」設定的按鈕（FR-005）
- [X] T019 [P] [US1] 實作 `SnagItForever/Capture/GlobalHotKey.swift`：Carbon `RegisterEventHotKey` 封裝，註冊失敗（被占用）時回報錯誤供偏好設定顯示警告（FR-001）
- [X] T020 [US1] 實作 `SnagItForever/Capture/CaptureService.swift`：以 `SCScreenshotManager.captureImage` 擷取區域（`sourceRect` 並以 `exceptingWindows` 排除自家覆蓋層）、視窗（`desktopIndependentWindow`，被遮擋仍取得完整內容，`ignoreShadowsSingleWindow` 受偏好設定控制）、全螢幕（游標所在顯示器）；輸出為顯示器原生像素解析度，`showsCursor` 受偏好設定控制（FR-002、FR-003、FR-006）
- [X] T021 [US1] 實作 `SnagItForever/Capture/CaptureOverlayController.swift`：每個顯示器一個無邊框覆蓋層視窗、`R`／`W`／`F` 切換模式、上方三個模式按鈕、`Esc` 取消且無副作用（FR-004，依 commands.md）
- [X] T022 [P] [US1] 實作 `SnagItForever/Capture/RegionSelectionView.swift`：拖曳選取、即時顯示寬高與游標座標、放大鏡、放開滑鼠即確認，選取範圍限制在拖曳起點所在的顯示器，使用 `CaptureGeometry`（相依 T017）
- [X] T023 [P] [US1] 實作 `SnagItForever/Capture/WindowPicker.swift`：以 `SCShareableContent` 列出視窗、游標命中測試與高亮、點擊確認
- [X] T024 [US1] 實作 `SnagItForever/Capture/CaptureCoordinator.swift`：快速鍵或選單 → 權限檢查 → 覆蓋層 → `CaptureService` → `LibraryStore.create` → 依 `afterCapture` 執行開啟編輯器、複製到剪貼簿、儲存到預設資料夾（FR-007）；每次擷取都重新檢查權限，執行期間權限被撤銷時改顯示說明視窗；儲存失敗（位置不可用、磁碟已滿）時顯示錯誤提示，但擷取仍保留在資料庫中（相依 T015、T018～T023、T025；T025 須先於本任務完成）
- [X] T025 [US1] 實作 `SnagItForever/Editor/EditorWindowController.swift`、`SnagItForever/Editor/CanvasView.swift` 與 `SnagItForever/Editor/EditorWindowRegistry.swift`：先能顯示擷取影像；同一擷取最多一個視窗、可同時開多個（FR-030）
- [X] T026 [P] [US1] 實作 `SnagItForever/Settings/SettingsWindowController.swift` 與 `SnagItForever/Settings/CaptureSettingsView.swift`（SwiftUI）：快速鍵錄製元件（含被占用警告）、擷取後行為、是否含游標、是否含視窗陰影、預設儲存資料夾
- [X] T027 [US1] 在 `AppDelegate` 與 `StatusItemController` 接上快速鍵註冊與「擷取區域／視窗／全螢幕」「偏好設定…」選單項目（相依 T014、T019、T024、T026）
- [X] T028 [US1] 驗證：`swift test` 全數通過、`xcodebuild … build` 成功，並啟動 App 確認不崩潰且選單列圖示出現；在 `CaptureCoordinator` 加入以 `os.Logger`（子系統 `com.snagitforever.app`、類別 `capture`）記錄的耗時日誌（快速鍵→覆蓋層顯示、確認擷取→編輯器開啟），供審查者量測 SC-003；quickstart M1 的互動步驟列入 PR 供審查者手動驗證

**檢查點**：使用者故事 1 可獨立運作，構成 MVP

---

## Phase 4：使用者故事 2 — 標註擷取的影像（優先級：P1）

**目標**：在編輯器以十種工具標註，標註可個別選取與編輯，支援復原／重做、縮放與平移，遮蔽不可逆。

**獨立測試**：開啟任一影像，每種標註各加一個，編輯與刪除其中幾個，復原／重做（quickstart M2）。

### 先寫測試

- [X] T029 [P] [US2] 撰寫 `CoreTests/EditingDocumentTests.swift`：新增／更新／移除、`reorder`（最上層、最下層、上移、下移）、`undo`／`redo`、`beginGesture`／`endGesture` 合併為一次歷史、`hitTest` 的容差與最上層優先、`step` 放置時編號為「目前最大編號 + 1」且不自動重新編號
- [X] T030 [P] [US2] 撰寫 `CoreTests/RedactionTests.swift`：給定兩張僅在某磁磚內部細節不同、但該磁磚平均值相同的原圖，`blur` 與 `pixelate` 遮蔽後輸出逐像素相同（SC-005）；強度最小為 8 px；區域外像素不變
- [X] T031 [P] [US2] 撰寫 `CoreTests/RendererTests.swift`：每種 `Kind` 畫出的像素落在預期位置；`draw` 與 `flatten` 對同一份資料輸出相同像素（SC-006）；`flatten` 不修改傳入的原圖

### 實作

- [X] T032 [P] [US2] 實作 `Core/History/History.swift`：標註陣列的快照式復原／重做堆疊與手勢合併（D-09）
- [X] T033 [US2] 實作 `Core/History/EditingDocument.swift`：依 [contracts/core-api.md](./contracts/core-api.md) 提供編輯操作、`hitTest`、`reorder`（相依 T032）
- [X] T034 [P] [US2] 實作 `Core/Rendering/Redaction.swift`：磁磚平均的馬賽克，以及先磁磚平均再平滑的模糊（最小磁磚 8 px，D-08）
- [X] T035 [US2] 實作 `Core/Rendering/Renderer.swift`：`draw` 與 `flatten`（暫不含 crop／finish／outputScale）逐類型繪製，呼叫 `Redaction`（相依 T034）
- [X] T036 [US2] 實作 `SnagItForever/Editor/Tools/ToolController.swift`（草稿形狀換算與太小判定放在核心的 `Core/Model/DraftShape.swift`，並有 `DraftShapeTests`）：箭頭、線條、矩形、橢圓、手繪筆、螢光筆、步驟標記、模糊、馬賽克的拖曳建立流程（相依 T033）
- [X] T037 [US2] 擴充 `SnagItForever/Editor/CanvasView.swift`：改用 `Renderer.draw` 繪製、縮放與平移（`⌘+`／`⌘-`／`⌘0`，FR-015）、視圖座標與影像像素座標轉換（相依 T035）
- [X] T038 [US2] 實作 `SnagItForever/Editor/Tools/SelectionController.swift`（移動與控制點縮放的幾何放在核心的 `Core/Model/Annotation+Transform.swift`，並有 `AnnotationTransformTests`）：選取、控制點、移動、縮放、多選（FR-011，相依 T036、T037）
- [X] T039 [US2] 實作 `SnagItForever/Editor/Tools/TextEditingController.swift`：文字工具的就地編輯，完成前保持可編輯，雙擊可再編輯
- [X] T040 [P] [US2] 實作 `SnagItForever/Editor/ToolbarView.swift`（SwiftUI）：十一個工具按鈕、工具鍵依 commands.md，每個按鈕提供 `accessibilityLabel`
- [X] T041 [P] [US2] 實作 `SnagItForever/Editor/InspectorView.swift`（SwiftUI）：顏色、填滿、線條粗細、字型、字級，作用於選取的標註或目前工具的預設樣式（FR-010）
- [X] T042 [US2] 實作 `SnagItForever/Editor/EditorViewModel.swift` 並接上編輯選單：復原／重做、刪除、移到最上層／最下層、預設樣式（來自 Preferences）（相依 T033、T038～T041）
- [X] T043 [US2] 實作 `SnagItForever/Editor/AutosaveController.swift`：變更後 0.5 秒去抖動呼叫 `LibraryStore.save`，視窗關閉與應用程式結束時同步保存；`⌘W` 不跳警告；保存失敗（磁碟已滿、目錄不可寫）時於編輯器顯示不阻擋操作的提示並持續重試（FR-022，相依 T012、T042）
- [X] T044 [US2] 驗證：`swift test` 全數通過、`xcodebuild … build` 成功；quickstart M2 列入 PR 供手動驗證

**檢查點**：使用者故事 1 與 2 皆可獨立運作

---

## Phase 5：使用者故事 3 — 儲存、複製與分享成果（優先級：P2）

**目標**：複製、另存 PNG／JPEG、拖曳到其他 App、macOS 標準分享。

**獨立測試**：標註後複製貼到其他 App、另存兩種格式、拖曳、分享（quickstart M3）。

### 先寫測試

- [X] T045 [P] [US3] 撰寫 `CoreTests/FileNamerTests.swift`：檔名格式 `SnagItForever yyyy-MM-dd HH.mm.ss.<ext>`、重名時加序號 ` 2`、` 3`…
- [X] T046 [P] [US3] 撰寫 `CoreTests/ExportTests.swift`：PNG 與 JPEG 編碼可被解碼回等尺寸影像；JPEG 品質越低檔案越小；`flatten` 後的標註已合成進像素

### 實作

- [X] T047 [P] [US3] 實作 `Core/Persistence/FileNamer.swift`，使 T045 通過
- [X] T048 [US3] 實作 `Core/Rendering/Export.swift`：`ImageFormat`、`Renderer.encode`，使 T046 通過（相依 T035）
- [X] T049 [US3] 實作 `SnagItForever/Editor/ExportActions.swift`：複製到剪貼簿（`⌘C`）、另存新檔面板（`⇧⌘S`，預設資料夾與格式取自 Preferences；預設資料夾不存在時自動建立，寫入失敗時顯示錯誤提示並讓使用者重選位置）（FR-016、FR-017，相依 T047、T048）
- [X] T050 [P] [US3] 實作 `SnagItForever/Editor/DragSourceView.swift`：從編輯器把合成後的影像（暫存 PNG 檔）拖曳到其他 App（FR-018）
- [X] T051 [P] [US3] 實作 `SnagItForever/Editor/ShareButton.swift`：以 `NSSharingServicePicker` 提供標準分享選項（FR-019）
- [X] T052 [P] [US3] 實作 `SnagItForever/Settings/ExportSettingsView.swift`（SwiftUI）：預設格式、JPEG 品質
- [X] T053 [US3] 更新 `SnagItForever/Capture/CaptureCoordinator.swift`，使「儲存到預設資料夾」使用 `FileNamer` 與偏好格式（相依 T047、T048）
- [X] T054 [US3] 驗證：`swift test` 全數通過、`xcodebuild … build` 成功；quickstart M3 列入 PR 供手動驗證

**檢查點**：使用者故事 1～3 皆可獨立運作

---

## Phase 6：使用者故事 4 — 回到先前的擷取（優先級：P2）

**目標**：資料庫視窗列出最近擷取，可重新開啟、重新編輯、確認後刪除，標註保持可編輯。

**獨立測試**：擷取並標註，結束後重新啟動，從資料庫重新開啟，標註仍可個別編輯（quickstart M4）。

### 先寫測試

- [X] T055 [P] [US4] 撰寫 `CoreTests/LibraryRetentionTests.swift`：`totalSize()` 回傳目錄總位元組、`deleteOlder(than:)` 只刪除早於指定日期的項目並回傳數量、預設不自動刪除任何項目
- [X] T056 [P] [US4] 撰寫 `CoreTests/ReopenRoundTripTests.swift`：儲存含各種標註的 `Capture` 後重新載入，每個標註都可由 `EditingDocument` 個別編輯，且復原歷史為空（FR-012、SC-007）

### 實作

- [X] T057 [US4] 在 `Core/Persistence/LibraryStore.swift` 實作 `totalSize()` 與 `deleteOlder(than:)`，使 T055 通過
- [X] T058 [US4] 實作 `SnagItForever/Library/LibraryViewModel.swift` 與 `SnagItForever/Library/LibraryWindowController.swift`、`SnagItForever/Library/LibraryView.swift`（SwiftUI 縮圖格狀檢視，由新到舊，不可用項目以占位顯示）
- [X] T059 [US4] 在資料庫視窗接上：雙擊重新開啟（經 `EditorWindowRegistry`，已開啟則帶到前景）、`⌫`／右鍵刪除並跳出確認對話框後才永久刪除（FR-021、FR-022，相依 T058）
- [X] T060 [P] [US4] 實作 `SnagItForever/Settings/LibrarySettingsView.swift`（SwiftUI）：顯示資料庫佔用空間與手動「清除 N 天前的擷取」，並在 `StatusItemController` 加入「開啟資料庫…」（FR-020，相依 T057）
- [X] T061 [US4] 驗證：`swift test` 全數通過、`xcodebuild … build` 成功；quickstart M4 列入 PR 供手動驗證

**檢查點**：使用者故事 1～4 皆可獨立運作

---

## Phase 7：使用者故事 5 — 修飾影像（優先級：P3）

**目標**：裁切、調整大小、邊框、陰影、圓角，且為非破壞性並可復原。

**獨立測試**：裁切、調整大小、加邊框與陰影後匯出（quickstart M5）。

### 先寫測試

- [ ] T062 [P] [US5] 撰寫 `CoreTests/FinishAndCropTests.swift`：`crop` 必須完全落在 `0..pixelSize` 內且寬高 ≥ 1；`outputScale` 範圍 0.1–4.0；`flatten` 尺寸等於裁切範圍乘以 `outputScale`（加上邊框與陰影的擴張）；圓角使四個角落像素為透明；裁切可復原；原圖與標註資料不被修改

### 實作

- [ ] T063 [US5] 實作 `Core/Rendering/Renderer.swift` 的 `crop`、`outputScale`、`finish` 處理，以及 `EditingDocument.setCrop`／`setOutputScale`／`setFinish`，使 T062 通過
- [ ] T064 [P] [US5] 實作 `SnagItForever/Editor/Tools/CropToolController.swift`：裁切工具（`C`）與預覽
- [ ] T065 [P] [US5] 實作 `SnagItForever/Editor/ResizeSheet.swift`（SwiftUI）：調整輸出大小
- [ ] T066 [P] [US5] 在 `SnagItForever/Editor/InspectorView.swift` 加入邊框、陰影、圓角控制，預覽與匯出一致（FR-024）
- [ ] T067 [US5] 驗證：`swift test` 全數通過、`xcodebuild … build` 成功；quickstart M5 列入 PR 供手動驗證

**檢查點**：所有使用者故事皆可獨立運作

---

## Phase 8：收尾與跨領域事項

**目的**：影響多個使用者故事的改善、文件與最終驗證

- [ ] T068 [P] 補齊 `SnagItForever/Resources/Localizable.xcstrings`：所有使用者可見字串的 `zh-Hant` 與 `en` 翻譯（FR-027）
- [ ] T069 [P] 補齊無障礙：工具列與面板元件的 VoiceOver 標籤、畫布提供標註清單供 VoiceOver 導覽、所有動作皆有選單項目與快速鍵（FR-028）
- [ ] T070 [P] 實作 `SnagItForever/Settings/GeneralSettingsView.swift`：以 `SMAppService` 提供「登入時啟動」，預設關閉（FR-029）
- [ ] T071 [P] 檢查淺色與深色外觀：全部使用動態系統顏色，畫布背景與控制點在兩種外觀都清楚（FR-025）
- [ ] T072 [P] 撰寫 `CoreTests/PerformanceTests.swift`：5K（5120×2880）影像含 100 個標註時，單一畫面的 `Renderer.draw` 耗時中位數（30 次）≤ 33 ms，`flatten` 在 2 秒內完成（SC-004）
- [ ] T073 稽核無網路行為：在 `SnagItForever/` 與 `Packages/` 搜尋 `URLSession`、`NWConnection`、`CFNetwork`、`WKWebView` 等網路用法，確認為零（FR-026，憲章原則 II）
- [ ] T074 以繁體中文更新 `CLAUDE.md`：建置、測試、單一測試指令、高階架構（App target ＋ `SnagItCore`）、螢幕擷取權限的開發注意事項（憲章開發流程要求）
- [ ] T075 [P] 以繁體中文更新 `README.md`：專案簡介、需求、建置與執行
- [ ] T076 最終驗證：執行 quickstart 的所有自動化步驟（`swift test`、`xcodebuild build`），將結果、「需審查者手動驗證的項目」（含 SC-001、SC-003 的量測）與已知限制（受保護內容如 DRM 影片在擷取中為空白，系統無法偵測）寫入 `specs/001-screenshot-capture-annotation/verification.md`

---

## 相依性與執行順序

### 階段相依

- **設定（Phase 1）**：無相依，可立即開始
- **基礎（Phase 2）**：相依設定完成——阻擋所有使用者故事
- **使用者故事（Phase 3–7）**：皆相依基礎階段完成
  - US1（擷取）→ US2（標註，需要 US1 建立的編輯器視窗與畫布）
  - US3（輸出）與 US5（修飾）相依 US2 的 `Renderer`
  - US4（資料庫）相依 US1 的編輯器視窗與 US2 的自動保存
- **收尾（Phase 8）**：相依所有想納入的使用者故事

### 故事內順序

- 測試 MUST 先寫並確認失敗，再做對應實作（憲章原則 IV）
- 模型 → 服務／渲染 → UI → 整合
- 每個故事完成後在檢查點驗證，再進入下一個

### 平行機會

- Phase 1：T002、T004 可平行
- Phase 2：T006～T008 可平行；T009、T010 可平行；T013、T014 可平行
- 各故事內標記 [P] 的測試與不同檔案的實作可平行

## 平行執行範例

### 基礎階段的測試

```text
T006 CoreTests/GeometryTests.swift
T007 CoreTests/ModelCodingTests.swift
T008 CoreTests/LibraryStoreTests.swift
```

### 使用者故事 2 的測試

```text
T029 CoreTests/EditingDocumentTests.swift
T030 CoreTests/RedactionTests.swift
T031 CoreTests/RendererTests.swift
```

## 實作策略

### MVP 優先

1. 完成 Phase 1：設定
2. 完成 Phase 2：基礎
3. 完成 Phase 3：使用者故事 1
4. **停下並驗證**：擷取流程可獨立運作，即為 MVP

### 漸進式交付

1. 設定 ＋ 基礎 → 地基就緒
2. 加入 US1 → 驗證 → MVP（可擷取）
3. 加入 US2 → 驗證（擷取並標註，滿足兩項必備功能）
4. 加入 US3、US4 → 驗證（可輸出、可回頭編輯）
5. 加入 US5 → 驗證（修飾）
6. 收尾與最終驗證

### 備註

- [P] 任務＝不同檔案、無相依
- [Story] 標籤把任務對應到使用者故事，便於追蹤
- 實作前先確認測試失敗，每個任務或邏輯群組完成後 commit
- 無法在無頭環境自動化的行為（擷取、覆蓋層、拖曳、VoiceOver）列入 PR 供審查者手動驗證，不得宣稱已驗證
