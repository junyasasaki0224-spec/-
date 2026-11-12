# Roblox 試作版

このディレクトリは Rojo プロジェクトです。物理・AI・レース判定はメートル単位で計算し、描画座標は１メートルを3.5 studsに換算します。Roblox Studio での動作確認はまだ行っていません。

レースを計算だけで確認する場合、プロジェクトの親ディレクトリで以下を実行します。

```sh
python3 roblox/tools/run_sim.py 60
```

公式 Luau CLI `luau` をインストールして PATH に追加してください。Windows で `python3` が動かない場合は `python` を使います。計算テストは Studio でのオンライン対戦や描画を検証するものではありません。

`assets/engine-loop.wav` は合成したエンジン音です。Roblox Studio に取り込み、利用できるアセットIDを得たら `src/AudioConfig.lua` の `engineAssetId` に `rbxassetid://...` 形式で設定します。初期値は空で、そのままでは音は再生されません。元の Blender の艇・会場のモデルと実況は未移植です。
