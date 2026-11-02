--!strict
-- レア度の表。行の順番 = 低い→高い。数値はすべて初期値(公開後のデータで調整する)。
-- chance        : 基本の出現率(合計 1.0)
-- basePrice     : 基本の売値(小判)。魚ごとに上書き可
-- reelSeconds   : 完璧に枠へ入れ続けた場合の引き上げ時間
-- fishSpeed     : 引き上げゲージ内で魚アイコンが動く速さ(ゲージ高さ/秒)
-- jitter        : 魚が向きを変える頻度(回/秒)
-- tensionRate   : 枠から外れている間に糸の張りがたまる速さ(/秒)
-- autoSuccess   : 自動釣りでの成功率(手動の方が得になるよう低め)
-- color         : UI表示色

export type Rarity = {
	id: string,
	order: number,
	chance: number,
	basePrice: number,
	reelSeconds: number,
	fishSpeed: number,
	jitter: number,
	tensionRate: number,
	autoSuccess: number,
	color: string,
	luckAffected: boolean,
}

local Rarities: { Rarity } = {
	{
		id = "common",
		order = 1,
		chance = 0.60,
		basePrice = 10,
		reelSeconds = 3,
		fishSpeed = 0.30,
		jitter = 0.8,
		tensionRate = 0.22,
		autoSuccess = 1.00,
		color = "#C9CED6",
		luckAffected = false,
	},
	{
		id = "uncommon",
		order = 2,
		chance = 0.25,
		basePrice = 40,
		reelSeconds = 4,
		fishSpeed = 0.40,
		jitter = 1.0,
		tensionRate = 0.25,
		autoSuccess = 0.95,
		color = "#6FD08C",
		luckAffected = false,
	},
	{
		id = "rare",
		order = 3,
		chance = 0.10,
		basePrice = 150,
		reelSeconds = 5,
		fishSpeed = 0.52,
		jitter = 1.2,
		tensionRate = 0.28,
		autoSuccess = 0.85,
		color = "#4FA8FF",
		luckAffected = true,
	},
	{
		id = "epic",
		order = 4,
		chance = 0.04,
		basePrice = 600,
		reelSeconds = 7,
		fishSpeed = 0.62,
		jitter = 1.4,
		tensionRate = 0.30,
		autoSuccess = 0.70,
		color = "#B377FF",
		luckAffected = true,
	},
	{
		id = "legendary",
		order = 5,
		chance = 0.009,
		basePrice = 3000,
		reelSeconds = 9,
		fishSpeed = 0.72,
		jitter = 1.6,
		tensionRate = 0.32,
		autoSuccess = 0.50,
		color = "#FFB547",
		luckAffected = true,
	},
	{
		id = "mythic",
		order = 6,
		chance = 0.0009,
		basePrice = 20000,
		reelSeconds = 10,
		fishSpeed = 0.82,
		jitter = 1.8,
		tensionRate = 0.34,
		autoSuccess = 0.35,
		color = "#FF5E7E",
		luckAffected = true,
	},
	{
		id = "secret",
		order = 7,
		chance = 0.0001,
		basePrice = 150000,
		reelSeconds = 12,
		fishSpeed = 0.92,
		jitter = 2.0,
		tensionRate = 0.36,
		autoSuccess = 0.20,
		color = "#7DF9FF",
		luckAffected = true,
	},
}

return Rarities
