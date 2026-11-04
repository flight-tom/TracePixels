# 契約：資料庫磁碟格式（增補）

延伸[功能 001 的磁碟格式](../../001-screenshot-capture-annotation/contracts/library-format.md)。目錄結構、`schemaVersion`（維持 1）、原子寫入與不可變 `image.png` 規則全部不變。

## 新增：`source` 的 `imported` 型別

```json
"source": { "type": "imported", "fileName": "IMG_0042.HEIC" }
```

- `fileName` 只含檔名與副檔名，不含目錄路徑（不洩漏使用者的資料夾結構）。
- `image.png` 為匯入時解碼出的影像（已套用方向、保留 alpha 與色彩描述檔）的無損 PNG；之後永不修改。
- 舊版程式讀到 `imported` 會當作 `region`（既有的未知型別回落規則），仍可開啟與編輯；舊版重新保存會把來源寫回 `region`。

## 新增：暫存目錄

```text
Library/
├── <UUID>.tracepixelscapture/     # 完整項目（唯一被列出的型別）
└── <UUID>.importing/              # 建立中的暫存，完成後改名；永遠不被列出
```

規則：

1. 新項目一律先在 `<UUID>.importing/` 寫齊 `image.png`、`document.json`、`thumbnail.jpg`，再以一次目錄改名成為正式項目。
2. 列表、總容量以外的任何功能都忽略 `*.importing`；總容量計算包含它們（它們確實佔用磁碟）。
3. App 啟動時刪除殘留的 `*.importing`。這是唯一會自動刪除資料庫內容的動作，且只針對從未成為項目的半成品。
