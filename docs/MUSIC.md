# BGM

`tools/music/yokai_bgm.py` が numpy だけで作る自作の曲(和の音階・琴/三味線/尺八/太鼓ふうの音)。著作権の心配はない。

| 曲 | 鳴る場所 | 音階 | 速さ | 中身 |
|---|---|---|---|---|
| village | 釣り村・ぬしの湖(どの釣り場からも遠い所も) | 陽音階 | 84 | 琴のアルペジオ・尺八・木魚。のんびり |
| swamp | 沼 | 陰音階(都節) | 66 | 低い持続音・まばらな琴・息の多い尺八・風鈴。少しあやしい |
| river | 川 | 陽音階 | 108 | 流れる三味線・締太鼓。軽快 |
| sea | 海 | 琉球音階 | 96 | 三線ふうの伴奏・波の音・指笛 |
| battle | ふつうのバトル・対戦 | 陰音階 | 152 | 大太鼓・締太鼓・三味線のリフ・尺八 |
| boss | ボス戦(協力のボス・各地のぬし) | 短調(和の音なし) | 168 | ドラム・歪んだギター・金管・弦の刻み・合唱。軽く圧縮して音圧を上げてある |

どの曲も継ぎ目なくループする(最後の残響を曲の頭に重ねてある)。

## 作り直す
```
python tools/music/yokai_bgm.py                       # assets/sounds/bgm/*.ogg と Config/Music.luau
python tools/music/yokai_bgm.py --preview build/bgm   # 試し聞き用 mp3 も
python tools/music/yokai_bgm.py --only battle         # 1曲だけ
```
曲の中身を変えると `audioHash` が変わり、その曲の `soundId` は 0 に戻る(アップロードし直す)。

## Roblox に入れる
1. Creator Hub → 開発アイテム → 音声 で `assets/sounds/bgm/<曲>.ogg` をアップロード(6本)
2. 出た ID を `src/shared/Config/Music.luau` の各曲の `soundId = "rbxassetid://<番号>"` に書く
3. `lune run tools/launch_check.luau` で ✓ になるのを確かめる

`soundId` が 0 の曲は鳴らない(エラーにはならない)。

## しくみ
- `Controllers/Music.luau`: 0.1 秒ごとに、いちばん近い釣り場(中心から 400 スタッド以内)の曲を選ぶ(`Config.Music.areaTrack`)。バトルの画面が出ている間は `battleTrack`。
- 切り替えは `fade` 秒でクロスフェード。音量は `volume`(効果音より小さめ)。
- 設定の「🎵 BGM」で止められる。効果音を消した時(🔇)も止まる。
- 新しい釣り場を足したら `tools/music/yokai_bgm.py` の `AREA_TRACK` と曲を足す(足さなければ village が鳴る)。
