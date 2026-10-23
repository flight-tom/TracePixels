# Phase 0 研究：技術決策

所有決策由 Claude 依憲章原則 VII 自行做出。計畫的技術脈絡中沒有殘留的 NEEDS CLARIFICATION。

## D-01 最低支援 macOS 版本

- **決策**：macOS 14.0（Sonoma）。
- **理由**：`SCScreenshotManager.captureImage`（單張截圖 API）自 macOS 14 提供，是目前 Apple 建議的擷取方式；舊的 `CGWindowListCreateImage` 已被標示為棄用且在新系統上受限。`@Observable` 與其他現代 SwiftUI 功能同樣自 14 起可用。14 仍涵蓋絕大多數目前在用的 Mac。
- **替代方案**：macOS 13（需維持 `CGWindowListCreateImage` 備援路徑，增加維護成本）；macOS 15／26（可用更新的 API，但無謂縮小使用者範圍）。

## D-02 UI 框架：AppKit + SwiftUI 混合

- **決策**：
  - **AppKit**：擷取覆蓋層（每個顯示器一個無邊框 `NSWindow`）、編輯器畫布（自訂 `NSView`，處理滑鼠、縮放、平移、選取控制點、文字就地編輯）、全域快速鍵、選單列（`NSStatusItem`）。
  - **SwiftUI**：偏好設定、資料庫縮圖格狀檢視、工具列與屬性面板，透過 `NSHostingView` 嵌入。
- **理由**：低階滑鼠事件、游標、無邊框覆蓋層與精細繪圖在 AppKit 中最可控；表單式介面用 SwiftUI 最快。畫布若用 SwiftUI `Canvas` 會在命中測試、控制點與文字就地編輯上受限。
- **語言模式**：App target 用 Swift 5 語言模式，避免 AppKit 回呼與 `@MainActor` 在 Swift 6 嚴格檢查下的大量樣板；`SnagItCore` 為純值型別，使用 Swift 6 語言模式取得完整資料競爭檢查。
- **替代方案**：純 SwiftUI（畫布互動受限）；純 AppKit（設定與列表表單開發成本高）。

## D-03 擷取 API

- **決策**：ScreenCaptureKit 的 `SCScreenshotManager.captureImage(contentFilter:configuration:)`。
  - **區域**：覆蓋層選取後，對該顯示器以 `sourceRect` 擷取，並用 `exceptingWindows` 排除自家覆蓋層。
  - **視窗**：以 `SCShareableContent` 列出視窗並做游標命中測試，用 `SCContentFilter(desktopIndependentWindow:)` 擷取，因此被遮擋的視窗仍能取得完整內容；陰影由 `ignoreShadowsSingleWindow` 控制。
  - **全螢幕**：以游標所在的 `SCDisplay` 擷取。
  - **解析度**：`SCStreamConfiguration.width/height` 以顯示器像素尺寸（`pointPixelScale`）設定，確保原生解析度；`showsCursor` 對應偏好設定。
- **權限**：以 `CGPreflightScreenCaptureAccess()` 偵測、`CGRequestScreenCaptureAccess()` 請求；缺少時顯示說明視窗，並提供開啟「系統設定 › 隱私權與安全性 › 螢幕與系統音訊錄製」的按鈕。
- **替代方案**：`CGWindowListCreateImage`（棄用）；呼叫 `screencapture` 命令列（無法精細控制覆蓋層，且難以測試與發行）。

## D-04 全域快速鍵

- **決策**：Carbon `RegisterEventHotKey`，自行封裝；偏好設定中以一個簡單的快速鍵錄製元件設定。預設為 `⌃⇧4`（不與 macOS 內建 `⌘⇧4` 衝突）。註冊失敗（被占用）時在偏好設定顯示警告。
- **理由**：此 API 不需要額外的輔助使用權限，且為 Apple 框架（符合原則 V）。
- **替代方案**：第三方 KeyboardShortcuts／HotKey 套件（違反「優先 Apple 框架」）；`NSEvent.addGlobalMonitor`（需要輔助使用權限且無法攔截事件）。

## D-05 標註資料模型與座標系

- **決策**：標註為值型別（`struct Annotation`，含 `enum Kind`），座標一律用「影像像素座標、左上為原點」，與顯示縮放無關。以 `Codable` 儲存為 JSON。每個標註含穩定 `id`、`zIndex`、`style`。
- **理由**：與解析度無關才能讓畫布縮放、匯出、裁切與重新開啟都一致；值型別讓復原歷史與測試簡單。
- **替代方案**：`NSObject` 子類別圖層（難以序列化與測試）。

## D-06 渲染與所見即所得

- **決策**：`SnagItCore` 提供單一 `AnnotationRenderer`，把標註繪進 `CGContext`。畫布 `draw(_:)` 與匯出（`ExportRenderer`）呼叫同一份程式碼，只在 context 的縮放與視口不同。
- **理由**：直接保證 SC-006（匯出與畫面一致），並讓渲染可在無頭環境測試（把輸出與預期像素比對）。
- **替代方案**：畫布用 CALayer、匯出另寫一份（兩份實作必然漂移）。

## D-07 沙盒與簽署

- **決策**：不啟用 App Sandbox，啟用 Hardened Runtime；開發用 ad-hoc 簽署（`CODE_SIGN_IDENTITY = -`）。
- **理由**：發行方式尚未決定（規格假設）。非沙盒能避免儲存位置、拖曳與登入啟動的額外授權流程；之後若要上 Mac App Store，再另開功能處理沙盒。已知注意事項：ad-hoc 簽署的 build 每次重新建置後，macOS 可能要求重新授予螢幕擷取權限，這已寫入 quickstart。
- **替代方案**：直接啟用沙盒（需處理 security-scoped bookmark、預設儲存位置等，超出本功能範圍）。

## D-08 遮蔽（模糊／馬賽克）的不可逆性

- **決策**：遮蔽在合成階段直接**重建像素**，輸出只依賴磁磚平均值：
  - **馬賽克**：把區域切成 N×N 磁磚（N 為強度，最小 8 px），每個磁磚填入該磁磚的平均顏色。
  - **模糊**：先做同樣的磁磚平均（最小 8 px），再對磁磚網格做平滑；因此輸出同樣只是磁磚平均值的函數。
- **可驗證的不變量（對應 SC-005）**：給定兩張僅在某磁磚「內部細節」不同、但該磁磚平均值相同的原圖，遮蔽後的輸出必須逐像素相同。此性質以自動化測試覆蓋。
- **理由**：一般高斯模糊理論上可被反卷積部分復原；先降到磁磚平均再平滑，等同丟棄磁磚內的高頻資訊，無法還原。
- **替代方案**：單純 `CIGaussianBlur`（可能被反卷積還原，不符原則 III）。
- **備註**：編輯中的畫布預覽與匯出使用同一演算法，使用者看到的就是匯出的結果。

## D-09 復原／重做

- **決策**：快照式歷史：每次提交的編輯（放置、移動結束、縮放結束、刪除、樣式變更）存下標註陣列的快照；連續拖曳以單一提交合併。歷史上限以記憶體估計不設硬性次數，符合「無限次」需求；因標註為輕量值型別，100 個標註的快照成本可忽略。
- **理由**：實作簡單、行為可預測、易測試。不跨工作階段保留（澄清結果）。
- **替代方案**：命令模式（每種操作寫正反兩個方向，容易漏寫）；`NSUndoManager`（與 `SnagItCore` 的無 UI 相依衝突）。

## D-10 資料庫儲存與自動保存

- **決策**：每個擷取一個目錄 `<UUID>.snagitcapture/`，內含 `image.png`（原圖，建立後不再修改）、`document.json`（標註與中繼資料）、`thumbnail.jpg`。寫入採「寫入暫存檔再原子取代」。編輯器變更後以 0.5 秒去抖動自動保存，並在關閉視窗與應用程式結束時同步保存一次。資料庫列表於啟動時掃描目錄並依擷取時間排序；損毀的目錄標記為不可用而不影響其他項目。
- **理由**：檔案式簡單、可除錯、不需要資料庫遷移；符合「原圖不被修改」（原則 III）；能直接以 Finder 檢視。
- **替代方案**：SwiftData／Core Data（遷移與測試成本、Swift 6 並行摩擦）；單一大型 JSON 索引（寫入放大、易損毀）。

## D-11 裁切與縮放的語意

- **決策**：裁切與調整大小是「文件層級的非破壞性變換」，記錄在 `document.json` 的 `crop` 與 `outputScale`，原圖不變。裁切時，完全落在裁切範圍外的標註在匯出時自然被排除、部分重疊者被裁掉；標註資料本身保留，使用者可以復原裁切。邊框與陰影為匯出時套用的 `finish` 設定。
- **理由**：維持原則 III 的非破壞性，且讓裁切可復原。

## D-12 本地化與無障礙

- **決策**：使用 String Catalog（`Localizable.xcstrings`）提供 `zh-Hant` 與 `en`，開發語言為 `zh-Hant`。所有工具鍵與動作皆有選單項目與鍵盤快速鍵；工具列按鈕設定 `accessibilityLabel`。畫布提供標註清單供 VoiceOver 導覽。
- **理由**：對應 FR-027、FR-028。

## D-13 專案檔建立方式

- **決策**：手寫 `SnagItForever.xcodeproj/project.pbxproj`，使用 Xcode 16 起的檔案系統同步群組（`PBXFileSystemSynchronizedRootGroup`），並以 `XCLocalSwiftPackageReference` 引用 `Packages/SnagItCore`。建立後以 `xcodebuild -list` 與實際建置驗證。
- **理由**：環境未安裝 xcodegen／tuist，且不應為了產生專案檔而增加使用者必須安裝的工具；同步群組使新增檔案不需修改 pbxproj，大幅降低手寫風險與日後合併衝突。
- **替代方案**：以 Homebrew 安裝 xcodegen（修改使用者系統環境，且使專案依賴外部工具）。
- **風險**：手寫 pbxproj 可能被 Xcode 拒絕；若建置驗證失敗，退而在 Xcode 內以命令列建立等價專案並記錄原因。

## D-14 預設值彙整

| 項目 | 預設值 |
|------|--------|
| 全域快速鍵 | `⌃⇧4` |
| 擷取後行為 | 在編輯器開啟 |
| 預設儲存位置 | `~/Pictures/SnagItForever/` |
| 檔名 | `SnagItForever yyyy-MM-dd HH.mm.ss`，重名加序號 |
| JPEG 品質 | 90% |
| 是否含游標／視窗陰影 | 否／否 |
| 登入時啟動 | 關閉 |
| 預設標註顏色／粗細 | 紅色／4 px |
| 遮蔽最小磁磚 | 8 px |
