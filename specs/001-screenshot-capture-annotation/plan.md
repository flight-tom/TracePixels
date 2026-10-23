# 實作計畫：截圖與標註

**分支**：`001-screenshot-capture-annotation` | **日期**：2026-10-23 | **規格**：[spec.md](./spec.md)

**輸入**：功能規格 `/specs/001-screenshot-capture-annotation/spec.md`

## 摘要

建立一個原生 macOS 選單列應用程式：以全域快速鍵啟動擷取（區域、視窗、全螢幕），擷取結果自動進入本機資料庫並在編輯器開啟，使用者可用一組向量式標註工具（含不可逆的模糊與馬賽克）編輯，最後複製、儲存、拖曳或分享。

技術做法（細節見 [research.md](./research.md)）：

- **架構分兩層**：`SnagItCore`（本地 Swift Package，純 Foundation / CoreGraphics / ImageIO，無 UI 相依）負責標註模型、復原歷史、渲染與匯出、遮蔽、資料庫儲存；App target（AppKit + SwiftUI 混合）負責擷取、視窗、畫布互動與設定。
- **所見即所得**：畫布與匯出共用同一個 CoreGraphics 渲染器，確保畫面與匯出一致（SC-006）。
- **可測試性**：所有不需螢幕的邏輯都放在 `SnagItCore`，以 `swift test` 在無視窗環境下驗證（憲章原則 IV）。
- **零第三方相依**（憲章原則 V）。

## 技術脈絡

**語言／版本**：Swift 6.4（Xcode 27.1）。`SnagItCore` 使用 Swift 6 語言模式；App target 使用 Swift 5 語言模式（AppKit 互動的嚴格並行檢查成本高於收益，理由見 research.md D-02）

**主要相依**：僅 Apple 框架 — ScreenCaptureKit（擷取）、AppKit + SwiftUI（UI）、CoreGraphics + ImageIO（渲染與編碼）、Carbon `RegisterEventHotKey`（全域快速鍵）、UniformTypeIdentifiers、ServiceManagement（登入時啟動）

**儲存**：檔案式資料庫，位於 `~/Library/Application Support/SnagItForever/Library/`；每個擷取為一個目錄（原始 PNG + `document.json` + 縮圖）。偏好設定使用 `UserDefaults`

**測試**：`SnagItCore` 以 XCTest 搭配 `swift test`；App target 以 `xcodebuild build` 作為建置關卡；擷取與 UI 以 [quickstart.md](./quickstart.md) 的手動程序驗證

**目標平台**：macOS 14.0（Sonoma）以上，開發與驗證環境為 macOS 26.7；Apple Silicon 與 Intel 皆可（Universal）

**專案類型**：desktop-app（選單列常駐的原生 macOS 應用程式）

**效能目標**：快速鍵後 300 ms 內顯示擷取覆蓋層；擷取後 1 秒內開啟編輯器；5K 影像含 100 個標註時每個畫面更新耗時中位數 ≤ 33 ms（SC-003、SC-004）

**限制**：離線、無網路請求；非沙盒（理由見 research.md D-07）並啟用 Hardened Runtime；以 ad-hoc 簽署供開發

**規模／範圍**：單一使用者、單一 Mac；約 3 個 UI 區域（擷取覆蓋層、編輯器、資料庫）加偏好設定；預估 50–80 個 Swift 檔案

## 憲章檢查

*關卡：進入 Phase 0 研究前必須通過；Phase 1 設計後重新檢查。*

| 原則 | 檢查 | 結果 |
|------|------|------|
| I. 原生 macOS，純 Swift | 全部以 Swift 撰寫、Xcode 專案建置，僅用 Apple 框架；UI 為 AppKit + SwiftUI | ✅ 通過 |
| II. 隱私與本機優先 | 無網路程式碼；資料僅存本機；權限缺失時顯示說明頁而非空白影像；僅在需要時請求權限 | ✅ 通過 |
| III. 非破壞性編輯，不可逆遮蔽 | 標註與原圖分檔儲存（`image.png` 不被修改）；匯出時遮蔽以磁磚平均重建像素，輸出僅為磁磚平均值的函數 | ✅ 通過 |
| IV. 核心邏輯測試先行 | 標註模型、幾何、復原、持久化、匯出、遮蔽全在 `SnagItCore`，以 `swift test` 驗證；遮蔽不可逆性有專屬測試 | ✅ 通過 |
| V. 簡單與範圍紀律 | 無第三方相依；未加入錄影、GIF、捲動擷取、OCR、延遲擷取、雲端 | ✅ 通過 |
| VI. 繁體中文溝通與文件 | 本計畫與所有設計文件皆為 zh-TW | ✅ 通過 |
| VII. 自主執行 SDD 流程 | 所有決策已記錄於 research.md，未向使用者提問 | ✅ 通過 |

**Phase 1 設計後重新檢查**：設計（資料模型、契約、快速入門）未引入任何新的相依或範圍外功能，七項原則仍全數通過。複雜度追蹤無需填寫。

## 專案結構

### 文件（本功能）

```text
specs/001-screenshot-capture-annotation/
├── plan.md              # 本檔案（/speckit-plan 的輸出）
├── research.md          # Phase 0 輸出：技術決策與理由
├── data-model.md        # Phase 1 輸出：實體、欄位與狀態
├── quickstart.md        # Phase 1 輸出：建置、測試與手動驗證程序
├── contracts/           # Phase 1 輸出：UI／命令契約與磁碟格式
│   ├── library-format.md   # 資料庫磁碟格式（document.json 結構）
│   ├── core-api.md         # SnagItCore 對 App 公開的介面
│   └── commands.md         # 選單、快速鍵與工具鍵契約
└── tasks.md             # Phase 2 輸出（/speckit-tasks 產生，非本命令建立）
```

### 原始碼（儲存庫根目錄）

```text
SnagItForever.xcodeproj/          # Xcode 專案（使用檔案系統同步群組，新增檔案不需改 pbxproj）
SnagItForever/                    # App target
├── App/                          # 進入點、AppDelegate、選單列、視窗管理、Dock 圖示策略
├── Capture/                      # 快速鍵、覆蓋層、區域／視窗／全螢幕擷取、權限引導
├── Editor/                       # 編輯器視窗、畫布（NSView）、工具列與屬性面板（SwiftUI）
├── Library/                      # 資料庫視窗（縮圖格狀檢視）
├── Settings/                     # 偏好設定（SwiftUI）
├── Resources/                    # Assets.xcassets、Localizable.xcstrings（zh-Hant、en）
└── （Info.plist 由 GENERATE_INFOPLIST_FILE 產生，不是原始碼檔案）
SnagItForeverTests/               # App 單元測試（EditorViewModel、主選單；以 App 為宿主）
Packages/SnagItCore/              # 本地 Swift Package（無 UI 相依）
├── Package.swift
├── Sources/SnagItCore/
│   ├── Model/                    # Capture、Annotation、Style、幾何
│   ├── History/                  # 復原／重做
│   ├── Rendering/                # 標註渲染、遮蔽、合成與匯出
│   └── Persistence/              # 資料庫儲存、自動保存
└── Tests/SnagItCoreTests/
```

**結構決策**：採「Xcode App target ＋ 本地 Swift Package」。UI 與系統整合（需要螢幕、視窗伺服器、權限）留在 App target，其餘邏輯放進 `SnagItCore` 以便無頭測試。專案檔以 Xcode 16 起支援的檔案系統同步群組建立，因環境未安裝 xcodegen／tuist，且憲章偏好少相依。

## 複雜度追蹤

無憲章違反，本表無需填寫。
