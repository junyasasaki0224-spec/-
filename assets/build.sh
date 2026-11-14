#!/bin/sh
# 3Dモデルを作り直す: Blender (bpy) でモデルを生成 → gltf-transform で頂点データを量子化
#   BLENDER_PY=<bpy を入れた python> sh assets/build.sh
set -e
cd "$(dirname "$0")"
PY="${BLENDER_PY:-${PY:-python3}}"
TMP="${TMPDIR:-/tmp}/minato-assets"
mkdir -p "$TMP" models
# 艇は関節(ハンドル・モーター・上半身)を回すので量子化しない
"$PY" blender/build_boat.py models/boat.glb
"$PY" blender/build_venue.py "$TMP/venue.glb"
npx --yes @gltf-transform/cli weld "$TMP/venue.glb" "$TMP/venue.w.glb"
npx --yes @gltf-transform/cli quantize "$TMP/venue.w.glb" "$TMP/venue.q.glb" --pattern "{POSITION,NORMAL,COLOR_0}" --quantize-color 8 --quantize-normal 8 --quantize-position 16
# meshopt で圧縮(読み込み側は src/gfx/boat.js の loadGLB が展開する)。約3分の1になる
npx --yes @gltf-transform/cli meshopt "$TMP/venue.q.glb" models/venue.glb
ls -la models
