# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案

TracePixels 是原生 macOS 的截圖與標註工具（Swift、Xcode 專案、僅用 Apple 框架）。選單列常駐，以全域快速鍵擷取區域／視窗／全螢幕，在編輯器標註，再複製、儲存、拖曳或分享。範圍外：錄影、GIF、捲動／全景／延遲擷取、OCR、雲端。

專案憲章在 `.specify/memory/constitution.md`，必須遵守。幾條會直接影響日常工作的規則：

- 與使用者的對話與所有文件、commit 訊息、PR 一律使用**繁體中文（zh-TW）**（程式碼與識別名稱除外）。
- SDD 流程（specify → clarify → plan → tasks → analyze → implement）由 Claude **自主**執行、不中途詢問；完成後建立 PR 供審查，不直接推主要分支、不自行合併。
- `TracePixelsCore` 的邏輯**測試先行**；遮蔽不可逆性必須有自動化測試。
- 沒有網路程式碼；擷取與標註只留在本機。

功能規格、計畫與任務在 `specs/001-screenshot-capture-annotation/`（`spec.md`、`plan.md`、`research.md`、`tasks.md`、`contracts/`、`quickstart.md`、`verification.md`）。

## 指令

```bash
# 核心邏輯測試（無需螢幕，最快的回饋迴圈）
cd Packages/TracePixelsCore && swift test

# 單一測試類別或方法
cd Packages/TracePixelsCore && swift test --filter RedactionTests
cd Packages/TracePixelsCore && swift test --filter ExportTests/testPNGRoundTripIsLossless

# 效能測試（SC-004）；Debug 與 Release 都應通過
cd Packages/TracePixelsCore && swift test --filter PerformanceTests
cd Packages/TracePixelsCore && swift test -c release --filter PerformanceTests

# App 單元測試（EditorViewModel、主選單；以 App 為宿主，執行時不會註冊快速鍵與選單列圖示）
xcodebuild -project TracePixels.xcodeproj -scheme TracePixels \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test
# 單一 App 測試：加上 -only-testing:TracePixelsTests/EditorViewModelTests/testNudgeMovesTheSelectionAndEachNudgeIsOneUndoStep

# 建置 App（產物放在被 .gitignore 忽略的 build/）
xcodebuild -project TracePixels.xcodeproj -scheme TracePixels \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build

# 執行
open build/DerivedData/Build/Products/Debug/TracePixels.app

# 擷取耗時日誌（SC-003）：快速鍵→覆蓋層、確認擷取→編輯器
log stream --predicate 'subsystem == "com.tracepixels.app"' --level info
```

`TracePixelsTests/` 涵蓋不需要螢幕的 App 狀態邏輯（`EditorViewModel`、主選單）；需要螢幕、視窗伺服器或權限的行為（擷取、覆蓋層、拖曳、分享…）以 `specs/001-screenshot-capture-annotation/quickstart.md` 的手動程序驗證。

## 架構

兩層：**`Packages/TracePixelsCore`**（本地 Swift Package，只用 Foundation／CoreGraphics／CoreText／ImageIO，無 UI 相依）與 **`TracePixels/`**（App target，AppKit＋SwiftUI 混合）。能在無螢幕環境測試的邏輯一律放核心。

### 核心（`TracePixelsCore`）

- **模型**：`Capture`（擷取＋標註＋非破壞性的裁切／縮放／修飾，`schemaVersion` 1）、`Annotation`（`Kind` 十種，座標一律是**影像像素、左上為原點**）、`Style`。`lineWidth`、`fontSize`、遮蔽強度（≥ 8）、`outputScale` 在 setter 與解碼時都夾限。不認得的標註類型解碼時略過但原樣保存（`JSONValue`），儲存時寫回。
- **`EditingDocument`**：編輯器的可變狀態。快照式復原（不設上限）、`beginGesture`／`endGesture` 把拖曳合併成一步、z 順序、命中測試。`Annotation+Transform`（控制點縮放、平移）與 `DraftShape`（拖曳草稿形狀、Shift 約束）是互動用的純邏輯。
- **`Renderer`**：畫布與匯出**共用同一份**程式碼（SC-006）。`composite` = 原圖＋標註；`flatten` = composite → 裁切 → 縮放 → 邊框／陰影／圓角；`encode` 輸出 PNG／JPEG。**遮蔽直接重建像素**（`Redaction`）：輸出只取決於各磁磚的平均值，所以不可還原；遮蔽也會蓋住它下方較低層的標註。
- **`LibraryStore`**（actor）：檔案式資料庫，每個擷取一個 `<UUID>.tracepixelscapture/`（`image.png` 建立後**永不修改**、`document.json`、`thumbnail.jpg`）。原子寫入；損毀或版本較新的項目列為不可用但絕不刪除或覆寫。格式見 `contracts/library-format.md`。
- 跨 actor 的 `CGImage` 用 `SendableImage` 包裝。

### App

- **擷取流程**：`GlobalHotKey`（Carbon，不需輔助使用權限）／選單列 → `CaptureCoordinator`（檢查權限 → `CaptureOverlayController` 每顯示器一個覆蓋層視窗 → `CaptureService` 以 ScreenCaptureKit 擷取 → `LibraryStore.create` → 開編輯器／複製／儲存）。座標換算在核心的 `CaptureGeometry`（可測試）；選取限制在拖曳起點所在的顯示器。覆蓋層自己的視窗 ID 擷取時要排除。
- **編輯器**：每個擷取一個視窗（`EditorWindowRegistry` 保證同一擷取只開一個）。`EditorViewModel` 持有 `EditingDocument` 與選取／工具／樣式，每次變更重新 `Renderer.composite` 並顯示；`CanvasView`（`NSView`，翻轉座標）把滑鼠事件交給 `ToolController`／`SelectionController`；屬性面板與工具列是 SwiftUI。`AutosaveController` 0.5 秒去抖動寫回資料庫，視窗關閉與結束應用程式時同步保存，所以沒有「未儲存」狀態。
- **Dock 圖示**：`LSUIElement` 為真；`ActivationPolicyManager` 只在有**編輯器或資料庫**視窗時切到 `.regular`（FR-029），全關後切回 `.accessory`；偏好設定與權限說明視窗不觸發。
- 偏好設定存 `UserDefaults`（`Preferences`）。**不啟用 App Sandbox**，啟用 Hardened Runtime，ad-hoc 簽署。

## 注意事項

- **專案檔是手寫的**，使用檔案系統同步群組：在 `TracePixels/` 或 `TracePixelsTests/` 下新增檔案**不需要**修改 `project.pbxproj`。環境沒有 xcodegen／tuist，也不要為此安裝。
- **語言模式**：核心用 Swift 6；App target 用 Swift 5（AppKit 回呼的嚴格並行檢查成本高於收益）。從非隔離的閉包（Carbon 回呼、`Actions` 閉包）呼叫 `@MainActor` 程式碼時用 `MainActor.assumeIsolated`。
- **核心在 Debug 組態也以 `-O` 編譯**（`Package.swift` 的 `unsafeFlags`，僅本地套件允許）：渲染器的像素迴圈在 `-Onone` 下慢近百倍，畫布會卡。像素緩衝用 `calloc`，不要用 `[UInt8](repeating:count:)`（Debug 下是未特化的泛型）。
- **本地化**：`Localizable.xcstrings`，開發語言 `zh-Hant`，key 就是中文原文。用 `xcodebuild`／`swift build` 建置**不會**回寫目錄；新增使用者可見字串後，要補上 `en` 翻譯（可從 `build/DerivedData/**/TracePixels.build/**/*.stringsdata` 取出所有 key 比對缺漏）。
- **`NSTextView` 的 Esc 對應 `complete:`**，不是 `cancelOperation:`；文字就地編輯的委派兩個都要接。
- **CoreGraphics 字形快取**：同字型與大小的第一次繪製與之後的邊緣像素有細微差異。比對渲染結果的測試要先渲染一次再比。
- **開發時的螢幕擷取權限**：ad-hoc 簽署的 build 每次重新建置後，macOS 可能要求重新授權；擷取空白或被拒絕時，到「系統設定 › 隱私權與安全性 › 螢幕與系統音訊錄製」移除舊項目後重新授權。在沒有此權限的環境（例如本機 CI、沙箱 shell）無法驗證覆蓋層與實際擷取。
- 新增或修改字串後，記得同步 `quickstart.md` 的手動驗證步驟與 `verification.md`。
