--!strict
-- エサの表(使い捨て。1回投げるごとに1個使う)
-- biteTime : 待ち時間の倍率(0.7 = 30%短い)
-- luck     : 運のボーナス(加算)
-- price    : 小判での値段(0 = 店では売らない。課金や報酬でのみ入手)

export type Bait = {
	id: string,
	order: number,
	price: number,
	biteTime: number,
	luck: number,
	color: string,
}

local Baits: { Bait } = {
	{ id = "worm", order = 1, price = 15, biteTime = 0.85, luck = 0.05, color = "#C97B63" },
	{ id = "dango", order = 2, price = 80, biteTime = 0.70, luck = 0.10, color = "#F2E6C9" },
	{ id = "glow_shrimp", order = 3, price = 400, biteTime = 0.60, luck = 0.20, color = "#7DF9FF" },
	{ id = "aburaage", order = 4, price = 3000, biteTime = 0.75, luck = 0.60, color = "#E8B04A" },
	{ id = "premium", order = 5, price = 0, biteTime = 0.50, luck = 0.30, color = "#FFD34D" },
}

return Baits
