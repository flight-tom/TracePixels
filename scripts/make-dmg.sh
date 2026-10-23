#!/bin/bash
# 把建置好的 TracePixels.app 包成 DMG：`scripts/make-dmg.sh <TracePixels.app> <版本> <輸出資料夾>`
# 只用 macOS 內建的 ditto／hdiutil／shasum；CI 與本機用同一份腳本。
# 輸出：<輸出資料夾>/TracePixels-<版本>.dmg 與同名的 .sha256
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "用法：$0 <TracePixels.app> <版本> <輸出資料夾>" >&2
    exit 2
fi
app=$1 version=$2 out=$3
[[ -d $app ]] || { echo "找不到 $app" >&2; exit 1; }

name="TracePixels-$version"
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

mkdir -p "$out"
# ditto 保留簽章、延伸屬性與符號連結；DMG 內附 Applications 捷徑，方便拖曳安裝
ditto "$app" "$stage/TracePixels.app"
ln -s /Applications "$stage/Applications"

rm -f "$out/$name.dmg"
# hdiutil 偶爾在 CI 上回報 "Resource busy"，重試幾次
for attempt in 1 2 3; do
    if hdiutil create -volname "TracePixels" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$out/$name.dmg"; then
        break
    fi
    [[ $attempt -lt 3 ]] || { echo "hdiutil 連續失敗" >&2; exit 1; }
    sleep 5
done

(cd "$out" && shasum -a 256 "$name.dmg" > "$name.dmg.sha256")
echo "已輸出 $out/$name.dmg"
