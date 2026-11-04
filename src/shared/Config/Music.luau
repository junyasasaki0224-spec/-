--!strict
-- BGM(tools/music/yokai_bgm.py が作る表。手で書き換えるのは各曲の soundId だけ)
-- assets/sounds/bgm/<曲>.ogg を Roblox にアップロードして soundId を "rbxassetid://<番号>" にする(0 なら鳴らない)。
-- audioHash は音の中身の印。曲を作り直すと変わり、その曲の soundId は 0 に戻る
return {
	tracks = {
		village = { soundId = "rbxassetid://0", audioHash = "c5daca08c40c", length = 45.714 },
		swamp = { soundId = "rbxassetid://0", audioHash = "4f29a34769fc", length = 58.182 },
		river = { soundId = "rbxassetid://0", audioHash = "610108874d42", length = 35.556 },
		sea = { soundId = "rbxassetid://0", audioHash = "13fb58d6fdb4", length = 40.000 },
		battle = { soundId = "rbxassetid://0", audioHash = "5209d5d124bf", length = 25.263 },
	} :: { [string]: { soundId: string, audioHash: string, length: number } },
	-- 釣り場 → 曲(ここにない場所は village)
	areaTrack = {
		nushi_lake = "village",
		swamp = "swamp",
		river = "river",
		sea = "sea",
	} :: { [string]: string },
	battleTrack = "battle",
	volume = 0.35, -- 曲の音量(効果音より小さく)
	fade = 1.5, -- 曲を切り替える時のフェード(秒)
}
