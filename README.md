# TracePixels

原生 macOS 的截圖與標註工具。以 Swift 撰寫，Xcode 專案，只使用 Apple 框架，所有資料留在本機。

## 功能

- **擷取**：全域快速鍵（預設 `⌃⇧4`）或選單列，擷取拖曳選取的區域、單一視窗（被遮擋也能取得完整內容）或整個顯示器；原生像素解析度、區域選取有座標與寬高讀數及放大鏡。
- **標註**：箭頭、線條、矩形、橢圓、手繪筆、螢光筆、文字、編號步驟標記，以及**不可逆**的模糊與馬賽克。每個標註都能個別選取、移動、縮放、改樣式、調整前後順序，並可無限次復原／重做。
- **輸出**：複製到剪貼簿、另存 PNG／JPEG、拖曳到其他 App、macOS 標準分享；可裁切、調整輸出大小、加邊框、陰影與圓角（皆為非破壞性）。
- **資料庫**：每次擷取自動存入，之後可重新開啟並繼續編輯（標註不會被壓平）；編輯內容持續自動保存。
- 介面支援繁體中文與英文、淺色與深色外觀、VoiceOver。

不在範圍內：錄影、GIF、捲動／全景／延遲擷取、OCR、雲端同步。

## 需求

- macOS 14（Sonoma）以上；開發環境為 Xcode 27.1、macOS 26。
- 首次擷取時需授予「螢幕與系統音訊錄製」權限。

## 建置與執行

```bash
# 核心邏輯測試
cd Packages/TracePixelsCore && swift test

# 建置並執行 App
xcodebuild -project TracePixels.xcodeproj -scheme TracePixels \
  -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/TracePixels.app
```

也可以直接用 Xcode 開啟 `TracePixels.xcodeproj`。

## 專案結構

```text
TracePixels.xcodeproj/      Xcode 專案（檔案系統同步群組）
TracePixels/                App：擷取、編輯器、資料庫、偏好設定
TracePixelsTests/           App 單元測試（EditorViewModel、主選單）
Packages/TracePixelsCore/   核心套件：模型、復原、渲染、遮蔽、匯出、資料庫（含測試）
specs/                      功能規格、計畫、任務與驗證紀錄（Spec Kit）
.specify/                   Spec Kit 設定與專案憲章
```

## 開發

本專案以 [Spec Kit](https://github.com/github/spec-kit) 的 Spec-Driven Development 流程開發。專案憲章在 `.specify/memory/constitution.md`；功能文件與手動驗證程序在 `specs/001-screenshot-capture-annotation/`。給 Claude Code 的工作指引見 `CLAUDE.md`。

## 授權

見 [LICENSE](LICENSE)。
