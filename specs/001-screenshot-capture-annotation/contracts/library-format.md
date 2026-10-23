# 契約：資料庫磁碟格式

位置：`~/Library/Application Support/SnagItForever/Library/`

## 目錄結構

```text
Library/
└── <UUID>.snagitcapture/
    ├── image.png          # 原始擷取，建立後永不修改
    ├── document.json      # 標註與中繼資料
    └── thumbnail.jpg      # 最長邊 320 px 的縮圖，可由 image.png 重建
```

## 規則

1. `image.png` 一旦寫入就不得被任何編輯操作修改（憲章原則 III）。
2. 所有寫入使用「寫入暫存檔 → 原子取代」，避免半寫入。
3. `thumbnail.jpg` 遺失時由 `image.png` 重建；`image.png` 或 `document.json` 無法讀取時，該項目視為不可用，但不得影響其他項目，也不得被自動刪除。
4. `document.json` 的 `schemaVersion` 高於程式支援的版本時，項目以唯讀「不可用」狀態列出，不嘗試覆寫。

## document.json（schemaVersion 1）

```json
{
  "schemaVersion": 1,
  "id": "5F1C2B7E-0000-0000-0000-000000000000",
  "createdAt": "2026-10-23T05:30:05Z",
  "modifiedAt": "2026-10-23T05:32:41Z",
  "source": { "type": "region" },
  "pixelSize": { "width": 1600, "height": 900 },
  "scale": 2.0,
  "crop": null,
  "outputScale": 1.0,
  "finish": { "border": null, "shadow": null, "cornerRadius": 0 },
  "annotations": [
    {
      "id": "A1000000-0000-0000-0000-000000000000",
      "zIndex": 0,
      "kind": { "type": "arrow", "start": { "x": 100, "y": 120 }, "end": { "x": 420, "y": 260 } },
      "style": {
        "color": { "r": 1, "g": 0, "b": 0, "a": 1 },
        "fillColor": null,
        "lineWidth": 4,
        "fontName": ".AppleSystemUIFont",
        "fontSize": 24
      }
    }
  ]
}
```

- 日期使用 ISO 8601（UTC）。
- `kind.type` 取值：`arrow`、`line`、`rectangle`、`ellipse`、`pen`、`highlighter`、`text`、`step`、`blur`、`pixelate`。欄位依類型不同，定義見 [data-model.md](../data-model.md)。
- 讀取時遇到未知的 `kind.type`：該標註被略過並保留原始 JSON 不丟失（向前相容），其餘標註正常載入。
