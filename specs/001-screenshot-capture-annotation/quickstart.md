# 快速入門：建置、測試與驗證

本文件是驗證指南，不含實作程式碼。契約請見 [contracts/](./contracts/)，資料模型請見 [data-model.md](./data-model.md)。

## 先決條件

- macOS 14.0 以上；Xcode 16 以上（開發環境為 Xcode 27.1）
- 不需要安裝任何第三方工具

## 建置與自動化測試

```bash
# 1. 核心邏輯測試（無需螢幕，最快的回饋迴圈）
cd Packages/SnagItCore && swift test

# 2. 只跑單一測試
cd Packages/SnagItCore && swift test --filter RedactionTests

# 3. 建置 App
xcodebuild -project SnagItForever.xcodeproj -scheme SnagItForever \
  -configuration Debug -destination 'platform=macOS' build

# 4. 執行 App
open "$(xcodebuild -project SnagItForever.xcodeproj -scheme SnagItForever \
  -configuration Debug -showBuildSettings | awk '/ BUILT_PRODUCTS_DIR/{print $3}')/SnagItForever.app"
```

**通過標準**：第 1 步全部測試通過；第 3 步 `BUILD SUCCEEDED` 且無警告升級為錯誤。

## 螢幕擷取權限（開發注意事項）

首次擷取時 macOS 會要求「螢幕與系統音訊錄製」權限。開發使用 ad-hoc 簽署，每次重新建置後系統可能要求重新授權；若擷取結果是空白或被拒絕，請到「系統設定 › 隱私權與安全性 › 螢幕與系統音訊錄製」移除舊項目後重新授權。應用程式本身會在缺少權限時顯示說明視窗並提供前往設定的按鈕（FR-005）。

## 自動化驗證對照

| 規格項目 | 驗證方式 |
|----------|----------|
| FR-011、FR-012 標註編輯與復原 | `SnagItCoreTests/EditingDocumentTests` |
| FR-013、SC-005 遮蔽不可逆 | `SnagItCoreTests/RedactionTests`：兩張只在磁磚內部細節不同的圖，遮蔽後輸出必須逐像素相同 |
| SC-006 匯出與畫面一致 | `SnagItCoreTests/RendererTests`：`draw` 與 `flatten` 對同一份資料輸出相同像素 |
| FR-017 檔名與格式 | `SnagItCoreTests/FileNamerTests`、`ExportTests` |
| FR-020～FR-022、SC-007 資料庫與持久化 | `SnagItCoreTests/LibraryStoreTests`：寫入、重新載入、損毀項目隔離、原圖不被修改 |
| FR-023、FR-024 裁切、縮放、修飾 | `SnagItCoreTests/FinishAndCropTests` |

## 手動驗證程序

擷取與 UI 行為無法完全自動化，依下列步驟逐項勾選。每一項對應規格的驗收情境。

### M1 擷取（使用者故事 1）

1. 按 `⌃⇧4`，拖曳一個區域 → 編輯器開啟，影像為所選區域，且為原生解析度（Retina 上像素尺寸為點數的 2 倍）。
2. 按 `⌃⇧4`，按 `W` 後點擊某視窗 → 只擷取該視窗；用另一個視窗遮住它再擷取，內容仍完整。
3. 按 `⌃⇧4`，按 `F` 後在第二個螢幕點擊（若有）→ 擷取游標所在螢幕。
4. 按 `⌃⇧4` 後按 `Esc` → 不產生任何擷取、剪貼簿不變。
5. 在系統設定撤銷權限後擷取 → 出現說明視窗與前往設定按鈕，不產生空白影像。
6. 計時：按下快速鍵到覆蓋層出現 < 300 ms（SC-003）。

### M2 標註（使用者故事 2）

1. 依序使用每個工具（箭頭、線條、矩形、橢圓、手繪筆、螢光筆、文字、步驟標記、模糊、馬賽克），每種至少一個。
2. 選取、移動、縮放、改色、改粗細、刪除任一標註，其他標註與原圖不受影響。
3. 連續 `⌘Z` 回到空白，再 `⇧⌘Z` 全部恢復。
4. 連點步驟標記工具三次 → 編號 1、2、3。
5. 輸入文字後點擊空白處完成，雙擊文字可再編輯。

### M3 輸出（使用者故事 3）

1. `⌘C` 後貼到「預覽程式」→ 含標註的影像。
2. `⇧⌘S` 存成 PNG 與 JPEG，檔名符合 `SnagItForever yyyy-MM-dd HH.mm.ss`，重複儲存會加序號。
3. 把影像從編輯器拖曳到「備忘錄」或訊息視窗。
4. 分享按鈕顯示 macOS 標準分享選單。

### M4 資料庫（使用者故事 4）

1. 做 3 次擷取並標註，結束 App 後重新啟動，開啟資料庫 → 縮圖由新到舊。
2. 雙擊任一項 → 標註仍可個別選取與編輯。
3. 刪除一項 → 先出現確認對話框。

### M5 修飾（使用者故事 5）

1. 裁切後匯出 → 尺寸為裁切範圍；復原後可還原。
2. 加上邊框與陰影 → 預覽與匯出一致。

### M6 一般

1. 切換淺色／深色外觀，編輯器正常顯示（FR-025）。
2. 切換系統語言為英文與繁體中文，介面對應切換（FR-027）。
3. 使用 VoiceOver 可讀出工具列按鈕名稱（FR-028）。
4. 只有選單列圖示（無視窗時），Dock 無圖示；開啟編輯器時 Dock 圖示出現（FR-029）。
5. 以 `nettop` 或 Little Snitch 類工具觀察，應用程式沒有任何對外連線（FR-026）。
