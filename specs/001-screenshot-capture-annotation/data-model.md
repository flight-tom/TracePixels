# 資料模型

所有實體定義於 `TracePixelsCore`，皆為值型別並符合 `Codable`、`Sendable`。座標一律為「影像像素座標，左上為原點」。

## Capture（擷取）

| 欄位 | 型別 | 說明 |
|------|------|------|
| `id` | UUID | 唯一識別，也是資料庫目錄名稱 |
| `createdAt` | Date | 擷取時間 |
| `modifiedAt` | Date | 最後修改時間；每次自動保存更新 |
| `source` | CaptureSource | `region`、`window(title, appName)`、`display(index)` |
| `pixelSize` | Size（整數寬高） | 原圖像素尺寸，建立後不變 |
| `scale` | Double | 擷取時顯示器的像素／點比例，例如 2.0 |
| `annotations` | [Annotation] | 依 `zIndex` 排序的標註 |
| `crop` | Rect? | 非破壞性裁切範圍；`nil` 表示不裁切 |
| `outputScale` | Double | 匯出縮放比例，預設 1.0，範圍 0.1–4.0 |
| `finish` | Finish | 匯出修飾：邊框與陰影 |
| `schemaVersion` | Int | 磁碟格式版本，目前為 1 |

**驗證規則**

- `pixelSize` 兩邊皆 > 0。
- `crop` 若存在，必須完全落在 `0..pixelSize` 內，且寬高 ≥ 1。
- `annotations` 中的 `id` 不可重複。

## Annotation（標註）

| 欄位 | 型別 | 說明 |
|------|------|------|
| `id` | UUID | 唯一識別 |
| `zIndex` | Int | 前後順序，數字大者在上 |
| `kind` | Kind | 見下表 |
| `style` | Style | 顏色、粗細、字型等 |

**Kind**

| 類型 | 幾何資料 |
|------|----------|
| `arrow` | 起點、終點 |
| `line` | 起點、終點 |
| `rectangle` | 矩形、是否填滿 |
| `ellipse` | 外接矩形、是否填滿 |
| `pen` | 點陣列（手繪路徑） |
| `highlighter` | 點陣列（半透明粗筆） |
| `text` | 矩形（文字框）、字串 |
| `step` | 中心點、編號（整數） |
| `blur` | 矩形、強度（磁磚大小，≥ 8） |
| `pixelate` | 矩形、強度（磁磚大小，≥ 8） |

**Style**

| 欄位 | 型別 | 說明 |
|------|------|------|
| `color` | RGBA（0–1 的 Double） | 線條或文字顏色 |
| `fillColor` | RGBA? | 填滿顏色，無則不填 |
| `lineWidth` | Double | 像素，範圍 1–64 |
| `fontName` | String | 文字用，預設系統字型 |
| `fontSize` | Double | 文字用，單位像素，範圍 8–400 |

**驗證規則**

- `blur`、`pixelate` 的強度 < 8 時一律提升為 8（不可逆性的下限）。
- 幾何可延伸到影像之外；匯出時裁掉。
- `step` 的編號在放置時取「目前最大編號 + 1」，之後可手動修改；不自動重新編號。

## Finish（匯出修飾）

| 欄位 | 型別 | 說明 |
|------|------|------|
| `border` | Border? | 顏色與寬度（像素） |
| `shadow` | Shadow? | 模糊半徑、位移、顏色 |
| `cornerRadius` | Double | 圓角半徑，預設 0 |

## Preferences（偏好設定）

存於 `UserDefaults`，不在 `TracePixelsCore` 內序列化。

| 鍵 | 型別 | 預設 |
|----|------|------|
| `hotKey` | keyCode＋modifiers | `⌃⇧4` |
| `afterCapture` | 集合：openEditor、copy、saveToFolder | `[openEditor]` |
| `saveFolder` | URL | `~/Pictures/TracePixels` |
| `saveFormat` | `png` ／ `jpeg` | `png` |
| `jpegQuality` | Double | 0.9 |
| `includeCursor` | Bool | false |
| `includeWindowShadow` | Bool | false |
| `launchAtLogin` | Bool | false |
| `defaultStyle` | 每種工具一份 Style | 紅色、4 px |

## Library（資料庫）

不是獨立持久化的實體，而是 `LibraryStore` 對資料庫目錄的檢視。

- 以 `createdAt` 由新到舊排序。
- 項目 = 一個有效的擷取目錄；損毀目錄以「不可用」狀態列出，不影響其他項目。

## 狀態與轉換

**Capture 生命週期**

```text
（擷取完成）→ 已建立 ──編輯／自動保存──▶ 已建立（modifiedAt 更新）
                  └──使用者確認刪除──▶ 已刪除（目錄移除）
```

- 擷取一建立就寫入資料庫（FR-020），因此沒有「未儲存」狀態。
- 匯出（複製、另存、拖曳、分享）不改變 Capture，只產生一份合成後的影像。

**編輯器工作階段（記憶體內，不持久化）**

- `history`：標註陣列的快照堆疊，含 `undo` 與 `redo` 兩個方向。
- `selection`：被選取的標註 id 集合。
- `activeTool`：目前工具。
- 關閉編輯器即丟棄 `history`（FR-012）。
