# 實作計畫：開啟與匯入外部圖片

**分支**：`002-open-import-external-images` | **日期**：2026-11-04 | **規格**：[spec.md](./spec.md)

**輸入**：功能規格 `/specs/002-open-import-external-images/spec.md`

## 摘要

讓編輯器不再依賴「先擷取」：使用者可從選單列、主選單、資料庫的「匯入…」按鈕、拖曳進資料庫視窗，以及 Finder 的「打開方式」／拖到 Dock 圖示，把電腦上的圖片檔帶進來標註。所有入口共用同一條匯入管線：**讀取並驗證（尺寸、格式、方向）→ 以新的資料庫項目保存一份副本（來源為「匯入」）→ 視入口決定是否開啟編輯器**。原始檔案不會被改動。

技術做法（細節見 [research.md](./research.md)）：

- **管線放核心**：新增 `ImageImporter`（以 ImageIO 讀取、驗證尺寸上限、套用方向）與 `LibraryImporter`（批次匯入、逐檔回報成功與失敗），皆在 `TracePixelsCore`，以 `swift test` 驗證（憲章原則 IV）。
- **資料模型只擴充一個列舉案例**：`CaptureSource.imported(fileName:)`；`schemaVersion` 維持 1（舊版讀到未知來源會當作 `region`，不影響標註）。
- **資料庫建立改為「暫存目錄 → 原子改名」**，確保匯入中途中斷不會留下半成品（FR-040、邊界情況）。
- **App 層**：`ImportCoordinator` 統一處理檔案選擇視窗、進度、彙總訊息與開啟編輯器（上限 5 個）；選單列、主選單、資料庫視圖、`application(_:open:)` 都只呼叫它。
- **零新增相依**，沒有網路程式碼。

## 技術脈絡

**語言／版本**：沿用功能 001：核心 Swift 6 語言模式、App target Swift 5 語言模式

**主要相依**：僅 Apple 框架 — ImageIO（讀取與方向）、UniformTypeIdentifiers（檔案類型過濾）、AppKit（`NSOpenPanel`、`application(_:open:)`）、SwiftUI（`dropDestination`）。無新增套件

**儲存**：沿用功能 001 的檔案式資料庫；匯入項目與擷取同格式（`image.png`、`document.json`、`thumbnail.jpg`），`document.json` 的 `source` 多一種型別

**測試**：核心以 XCTest／`swift test`（`ImageImporterTests`、`LibraryImporterTests`，並擴充 `LibraryStoreTests`、`ModelCodingTests`、`PerformanceTests`）；App 單元測試擴充 `MainMenuTests`；檔案選擇、拖曳、Finder 開啟等以 [quickstart.md](./quickstart.md) 手動驗證

**目標平台**：macOS 14.0 以上（與功能 001 相同）

**專案類型**：desktop-app（選單列常駐的原生 macOS 應用程式）

**效能目標**：≤ 12 百萬像素的圖片在確認選擇後 1 秒內於編輯器開啟（SC-009）；20 張一般圖片 10 秒內全部進資料庫（SC-012）

**限制**：離線；單邊 ≤ 16384 像素且總像素 ≤ 200 百萬像素，超過拒絕；原始檔案唯讀；匯入不得阻塞主執行緒

**規模／範圍**：新增約 7 個 Swift 檔案（核心 3：`ImageImporter`、`LibraryImporter`、`ImportReport`；App 2；測試 3：`ImageImporterTests`、`LibraryImporterTests`、`ImportReportTests`）與一份 `Info.plist` 片段；改動約 8 個既有檔案

## 憲章檢查

*關卡：進入 Phase 0 研究前必須通過；Phase 1 設計後重新檢查。*

| 原則 | 檢查 | 結果 |
|------|------|------|
| I. 原生 macOS，純 Swift | 只用 Swift 與 Apple 框架（ImageIO、AppKit、SwiftUI） | ✅ 通過 |
| II. 隱私與本機優先 | 只讀本機檔案；拖曳進來的非檔案 URL（網頁圖片）直接拒絕、不下載；無網路程式碼 | ✅ 通過 |
| III. 非破壞性編輯，不可逆遮蔽 | 原檔唯讀；匯入影像存成 `image.png` 後永不修改；標註、裁切仍是獨立物件 | ✅ 通過 |
| IV. 核心邏輯測試先行 | 讀取、尺寸上限、方向、透明度、批次彙總、半成品防護全在核心，先寫測試 | ✅ 通過 |
| V. 簡單與範圍紀律 | 無新相依；不含貼上剪貼簿、RAW／PDF／SVG 保證、覆寫原檔、錄影等範圍外項目；P3 的 Finder 入口僅增加一個 `Info.plist` 片段與一個委派方法 | ✅ 通過 |
| VI. 繁體中文溝通與文件 | 本計畫與所有設計文件皆為 zh-TW | ✅ 通過 |
| VII. 自主執行 SDD 流程 | 決策皆記錄於 research.md，未向使用者提問 | ✅ 通過 |

**Phase 1 設計後重新檢查**：設計引入的唯一結構性變更是 `CaptureSource` 新增案例與資料庫建立流程改為暫存目錄＋改名，皆為既有概念的小幅擴充，沒有新相依或範圍外功能。七項原則仍全數通過，複雜度追蹤無需填寫。

## 專案結構

### 文件（本功能）

```text
specs/002-open-import-external-images/
├── plan.md              # 本檔案
├── research.md          # Phase 0：決策與替代方案
├── data-model.md        # Phase 1：實體與驗證規則
├── quickstart.md        # Phase 1：手動驗證程序
├── contracts/
│   ├── core-api.md      # 核心新增的公開介面
│   ├── commands.md      # 選單、快速鍵與拖曳行為
│   └── library-format.md# 磁碟格式的增補
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks 產生
```

### 原始碼

```text
Packages/TracePixelsCore/
├── Sources/TracePixelsCore/
│   ├── Model/Capture.swift                  # 改：CaptureSource 新增 .imported(fileName:)
│   └── Persistence/
│       ├── ImageImporter.swift              # 新：單檔讀取、驗證、方向
│       ├── LibraryImporter.swift            # 新：批次匯入與 ImportResult
│       ├── ImportReport.swift               # 新：彙總報告的純函式（編輯器上限、失敗列舉規則）
│       └── LibraryStore.swift               # 改：暫存目錄建立、LibraryEntry.sourceFileName、清理殘留
└── Tests/TracePixelsCoreTests/
    ├── ImageImporterTests.swift             # 新
    ├── LibraryImporterTests.swift           # 新
    ├── ImportReportTests.swift              # 新
    ├── LibraryStoreTests.swift              # 改：暫存目錄與殘留清理
    ├── ModelCodingTests.swift               # 改：imported 來源的編解碼
    ├── PerformanceTests.swift               # 改：12 百萬像素匯入
    └── Support/TestImages.swift             # 改：產生各格式／方向／透明度的測試檔

TracePixels/
├── App/
│   ├── AppDelegate.swift                    # 改：openImage／importImages、application(_:open:)、啟動前暫存
│   ├── MainMenuBuilder.swift                # 改：檔案選單新增兩項
│   └── StatusItemController.swift           # 改：選單列新增「開啟圖片…」
├── Library/
│   ├── ImportCoordinator.swift              # 新：檔案選擇、批次、彙總訊息、開啟編輯器（≤ 5）
│   ├── ImportProgressPanel.swift            # 新：超過 1 秒才出現的進度面板
│   ├── LibraryView.swift                    # 改：拖放目標、匯入按鈕、匯入圖示與提示、空白狀態文字
│   ├── LibraryViewModel.swift               # 改：匯入入口
│   └── LibraryWindowController.swift        # 改：傳入 ImportCoordinator
└── Resources/Localizable.xcstrings          # 改：新增字串與 en 翻譯

Config/Info-DocumentTypes.plist              # 新：CFBundleDocumentTypes（與自動產生的 Info.plist 合併）
TracePixels.xcodeproj/project.pbxproj        # 改：兩個組態加上 INFOPLIST_FILE
TracePixelsTests/MainMenuTests.swift         # 改：新選單項目
```

**結構決策**：沿用兩層架構。可在無螢幕環境測試的邏輯（讀取、驗證、批次、清理）全在核心；`NSOpenPanel`、進度視窗、拖放與 `application(_:open:)` 在 App。`Info.plist` 片段刻意放在 `Config/`，**不在**檔案系統同步群組 `TracePixels/` 內，避免被當成資源複製而與自動產生的 Info.plist 衝突。

## 複雜度追蹤

無違反項目，無需填寫。
