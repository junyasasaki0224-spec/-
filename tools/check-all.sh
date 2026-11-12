#!/bin/sh
# 全部の確認を1回で回して、短い結果だけを出す(Claude が受け取り時に使う。GPT も Node の部分は手元で回せる)
#   sh tools/check-all.sh            ブラウザ版 + Roblox 版
#   LUAU_DIR=<luau のフォルダ> sh tools/check-all.sh
cd "$(dirname "$0")/.." || exit 1
[ -n "$LUAU_DIR" ] && PATH="$LUAU_DIR:$PATH"
fail=0
say() { printf '%s\n' "$*"; }

say "== ブラウザ版"
if npm run build >/tmp/check-build.log 2>&1; then say "ビルド: OK"; else say "ビルド: 失敗"; tail -5 /tmp/check-build.log; fail=1; fi
r=$(node tools/sim-test.mjs 60 1 2>&1 | tail -1) && say "AI 60レース: $r" || { say "AI レース: 失敗"; fail=1; }
r=$(node tools/guide-bot.mjs 2>&1) && say "$r" || { say "ガイドボット: 失敗"; fail=1; }

say "== Roblox 版"
if command -v luau-compile >/dev/null 2>&1; then
  bad=0; n=0
  for f in roblox/src/*.lua roblox/tests/*.luau roblox/tools/simulation.lua; do
    n=$((n+1)); luau-compile --text "$f" >/dev/null 2>/tmp/check-luau.log || { say "文法エラー: $f"; head -3 /tmp/check-luau.log; bad=1; }
  done
  [ $bad = 0 ] && say "文法: $n ファイル OK" || fail=1
  for t in roblox/tests/*.luau; do
    luau "$t" >/tmp/check-spec.log 2>&1 && say "テスト OK: $(basename "$t")" || { say "テスト失敗: $t"; tail -4 /tmp/check-spec.log; fail=1; }
  done
  python3 -I roblox/tools/run_sim.py 60 2>&1 | grep -E "Lane|Finished|contacts" | tr '\n' ' ' | sed 's/^/60レース: /'; echo
else
  say "luau / luau-compile が見つからないため Roblox 版は未確認"
fi
[ $fail = 0 ] && say "== 結果: すべて OK" || say "== 結果: 失敗あり"
exit $fail
