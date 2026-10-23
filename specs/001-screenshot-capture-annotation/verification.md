# 驗證紀錄：截圖與標註

**日期**：2026-10-23　**分支**：`001-screenshot-capture-annotation`　**環境**：Xcode 27.1、Swift 6.4、macOS 26.7（Apple Silicon）

本文件區分三類結果：**已自動驗證**、**已用合成事件驗證**（走過真實程式碼路徑，但沒有真人操作）、**需審查者手動驗證**。不能在這個環境驗證的項目沒有被當成已驗證。

## 1. 自動化驗證

| 項目 | 指令 | 結果 |
|------|------|------|
| 核心邏輯測試（Debug） | `cd Packages/TracePixelsCore && swift test` | 127 項全過 |
| 核心邏輯測試（Release） | `cd Packages/TracePixelsCore && swift test -c release` | 127 項全過 |
| App 單元測試 | `xcodebuild … test`（`EditorViewModelTests` 18＋`MainMenuTests` 5） | 23 項全過；連續 4 次皆通過。**另有 1 次早先的執行顯示 `TEST FAILED`，我當時只過濾輸出、沒留下失敗原因，之後無法重現，原因不明**（可能是新增測試檔後第一次啟動宿主 App 的暫時性問題） |
| App 建置（Debug） | `xcodebuild … -configuration Debug build` | BUILD SUCCEEDED，無警告 |
| App 建置（Release） | `xcodebuild … -configuration Release build` | BUILD SUCCEEDED，無警告（Phase 9 後重新確認）；Universal（x86_64、arm64）；ad-hoc＋Hardened Runtime 簽署 |
| 啟動煙霧測試 | 啟動後等待數秒 | 程序持續執行、無崩潰報告 |
| 無網路稽核（T073） | 原始碼搜尋 `URLSession`／`NWConnection`／`WKWebView`／`http(s)://` 等；`otool -L` | 原始碼為零；未連結 Network／WebKit／CFNetwork；entitlements 無 network |
| 本地化（T068） | 從建置產物取出所有 key 比對 `Localizable.xcstrings` | 156 項皆有英文（含 4 項複數形式）；`en.lproj` 與 `zh-Hant.lproj` 皆已編入 |

### 規格對照

| 規格項目 | 驗證 |
|----------|------|
| FR-028 所有動作都有選單項目、快速鍵不重複 | `MainMenuTests`（App 單元測試） |
| 匯出尺寸算式與 `flatten` 一致 | `FinishAndCropTests`（25 種裁切／縮放／修飾組合）、`EditorViewModelTests` |
| 檢視模型狀態邏輯（文字結束編輯、工具樣式、選取、微調、順序） | `EditorViewModelTests`（18） |
| FR-011、FR-012 標註編輯與復原 | `EditingDocumentTests`（16）、`AnnotationTransformTests`（8）、`DraftShapeTests`（5） |
| FR-013、SC-005 遮蔽不可逆 | `RedactionTests`（8）：磁磚內部細節不同但平均值相同的兩張圖，遮蔽後區域內逐像素相同；強度下限 8；遮蔽也蓋住下層標註 |
| SC-006 畫面與匯出一致 | `RendererTests`（10）：`draw`／`composite`／`flatten` 逐像素相同 |
| FR-002 區域換算（多螢幕、夾限在起點所在顯示器） | `CaptureGeometryTests`（10） |
| FR-017 檔名與格式 | `FileNamerTests`（5）、`ExportTests`（6） |
| FR-020～FR-022、SC-007 資料庫與持久化 | `LibraryStoreTests`（10）、`LibraryRetentionTests`（6）、`ReopenRoundTripTests`（5）：原子寫入、`image.png` 位元組不變、損毀與較新版本項目隔離不刪除、重新載入後每個標註可個別編輯、復原歷史為空 |
| FR-023、FR-024 裁切、縮放、修飾 | `FinishAndCropTests`（13） |
| SC-004 5K＋100 個標註 | `PerformanceTests`：單次渲染中位數 Debug 19.8 ms／Release 16.6–19.4 ms（上限 33 ms）；`flatten`（含邊框陰影圓角）約 130 ms（上限 2 s） |
| FR-026 本機優先 | 無網路稽核（見上） |

## 2. 以合成事件驗證（暫時腳手架，驗證後已移除、未提交）

用合成的 `NSEvent` 呼叫真實的 `CanvasView`／`ToolController`／`SelectionController` 與視窗，並以 `cacheDisplay` 輸出 PNG（不需螢幕錄製權限）：

- **標註編輯器**：建立箭頭、矩形、步驟標記（自動編號 1、2）、手繪、馬賽克、文字；選取、移動、復原；文字就地編輯以 **Esc** 與**點到畫布**兩種方式結束；0.5 秒後自動保存，磁碟與記憶體的標註數相同。此過程發現並修正一個真 bug：`NSTextView` 的 Esc 對應 `complete:` 而非 `cancelOperation:`。證據：[`evidence/us2-flatten-export.png`](./evidence/us2-flatten-export.png)（含中文文字、箭頭、矩形、步驟標記）、[`evidence/us2-editor-window-snapshot.png`](./evidence/us2-editor-window-snapshot.png)。
- **資料庫**：資料庫視窗列出縮圖（新到舊）；重新開啟同一擷取不重複開窗；刪除後項目減少且對應的編輯器視窗一併關閉。
- **裁切＋縮放＋修飾**：拖曳裁切框、縮放 50%、邊框＋陰影＋圓角，匯出尺寸（322×212）與檢視模型算出的一致，匯出預覽有產生，四次復原後全部還原。證據：[`evidence/us5-crop-scale-finish-export.png`](./evidence/us5-crop-scale-finish-export.png)。

## 3. 需審查者手動驗證（本環境無法驗證）

這個環境沒有「螢幕與系統音訊錄製」權限（`screencapture` 本身即失敗），也無法由真人操作，所以下列項目**尚未驗證**。步驟見 [quickstart.md](./quickstart.md) 的 M1～M6。

### 擷取（M1，使用者故事 1）— 全部未驗證

- [ ] `⌃⇧4` 全域快速鍵實際觸發；快速鍵被占用時偏好設定顯示警告。
- [ ] 覆蓋層：區域拖曳選取、寬高與座標讀數、放大鏡、`R`／`W`／`F` 切換、模式列按鈕、`Esc` 取消且無副作用。
- [ ] 擷取結果為顯示器**原生像素解析度**（Retina 上像素為點數的 2 倍）；多顯示器各自的縮放比例。
- [ ] 視窗擷取：被其他視窗遮擋仍取得完整內容；預設不含陰影、偏好設定開啟後含陰影（**視窗陰影開啟時的輸出尺寸尚未確認**，目前以 `SCShareableContent.info(for:)` 的 `contentRect` 決定大小）。
- [ ] 權限缺失時出現說明視窗與前往系統設定的按鈕；執行期間撤銷權限後再擷取也是。
- [ ] **SC-001**（快速鍵到剪貼簿 < 5 秒）、**SC-003**（覆蓋層 < 300 ms、編輯器 < 1 秒）：以 `log stream --predicate 'subsystem == "com.tracepixels.app"'` 觀察耗時日誌。

### 編輯器（M2、M3，使用者故事 2、3）

- [ ] 工具列圖示的實際外觀。（`cacheDisplay` 輸出的快照裡看不到工具列的 SF Symbols，我判斷是離屏繪製的限制，**無法確認**；其餘文字與版面正常。）
- [ ] 縮放（`⌘+`／`⌘-`／`⌘0`、觸控板捏合）與平移。
- [ ] 拖曳匯出到其他 App（`DragExportHandle`）、macOS 分享選單。
- [ ] `⌘C` 複製後貼到「預覽程式」、`⇧⌘S` 另存的檔案實際內容與檔名；寫入失敗時的錯誤提示與重選位置。
- [ ] 主選單各項目與快速鍵（Dock 圖示出現時才看得到）。

### 其他（M4～M6）

- [ ] 結束並重新啟動 App 後，資料庫仍列出擷取且標註可編輯（核心已有測試；App 端未實測）。
- [ ] 淺色與深色外觀的實際外觀（已稽核硬編碼顏色，見 `CLAUDE.md`／稽核紀錄，但未目視兩種外觀）。
- [ ] 英文介面（系統語言切換為英文）與繁體中文介面的實際呈現。
- [ ] VoiceOver 實際唸出工具列、模式列、資料庫項目與畫布標註清單。
- [ ] 「登入時啟動」實際生效（`SMAppService`）；Dock 圖示在編輯器／資料庫視窗開啟與全關時的出現與消失；偏好設定與權限說明視窗**不**觸發 Dock 圖示，且仍能取得鍵盤焦點與輸入。
- [ ] 主選單各項目（含新增的擷取三項、開啟資料庫、調整輸出大小、清除裁切）實際可點擊、快速鍵生效。
- [ ] **SC-002**（首次使用者 2 分鐘內完成擷取＋箭頭＋文字＋複製）、**SC-008**（使用者測試 ≥ 90%）：屬使用者測試，尚未進行。

## 4. 已知限制

- **受保護內容**（DRM 影片、安全輸入欄位）在擷取結果中為空白，系統無法偵測，因此無法提示使用者（規格邊界情況的「不誤導使用者」只能做到不假裝有內容）。
- **ad-hoc 簽署**：每次重新建置後 macOS 可能要求重新授予螢幕擷取權限（見 `CLAUDE.md`）。正式發行需要 Developer ID 簽署與公證，發行方式不在本功能範圍。
- **未啟用 App Sandbox**（研究 D-07）；日後上 Mac App Store 需另開功能處理。
- **最低 macOS 14**（`SCScreenshotManager`）。
- 核心套件在 Debug 組態也以 `-O` 編譯（研究 D-15），Debug 下單步除錯核心程式碼的體驗較差。
- 同字型與大小的文字，CoreGraphics 字形快取使第一次繪製與之後的邊緣像素有細微差異（不影響畫布與匯出的實質一致）。

## 5. 稽核紀錄

- **外觀（T071）**：硬編碼顏色只出現在覆蓋在使用者內容之上的層（擷取覆蓋層的加暗與讀數、畫布的裁切加暗與控制點）以及邊框預設色的資料值；介面外框使用系統動態顏色與材質。
- **無障礙（T069）**：工具列、模式列、資料庫項目、拖曳把手與分享按鈕皆有 `accessibilityLabel`；畫布以 `NSAccessibilityElement` 公開標註清單（由上到下、按下即選取）；所有工具與動作皆有選單項目。
