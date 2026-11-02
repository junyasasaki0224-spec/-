--!strict
-- 依頼板の依頼テンプレート。毎日この中から3つが選ばれる(全サーバー共通の抽選)。
-- kind:
--   catch_any       : 魚を count 匹釣る
--   catch_rarity    : minRarity 以上の魚を count 匹
--   catch_weather   : weather の天気の時に count 匹
--   catch_time      : time の時間帯に count 匹
--   catch_shape     : shape の形の魚で minWeight kg 以上を count 匹
--   catch_mutation  : 変異つきの魚を count 匹
--   sell_coins      : 合計 count 小判ぶん売る
-- reward: coins = 小判, bait = { id, amount }

export type Quest = {
	id: string,
	kind: string,
	count: number,
	minRarity: string?,
	weather: string?,
	time: string?,
	shape: string?,
	minWeight: number?,
	reward: { coins: number, bait: { id: string, amount: number }? },
}

local Quests: { Quest } = {
	{
		id = "catch10",
		kind = "catch_any",
		count = 10,
		reward = { coins = 300, bait = { id = "worm", amount = 5 } },
	},
	{
		id = "catch25",
		kind = "catch_any",
		count = 25,
		reward = { coins = 900, bait = { id = "dango", amount = 3 } },
	},
	{
		id = "rare3",
		kind = "catch_rarity",
		minRarity = "rare",
		count = 3,
		reward = { coins = 1200, bait = { id = "dango", amount = 5 } },
	},
	{
		id = "epic1",
		kind = "catch_rarity",
		minRarity = "epic",
		count = 1,
		reward = { coins = 2500, bait = { id = "glow_shrimp", amount = 2 } },
	},
	{
		id = "rain3",
		kind = "catch_weather",
		weather = "rain",
		count = 3,
		reward = { coins = 800, bait = { id = "dango", amount = 3 } },
	},
	{
		id = "fog3",
		kind = "catch_weather",
		weather = "fog",
		count = 3,
		reward = { coins = 800, bait = { id = "dango", amount = 3 } },
	},
	{
		id = "night5",
		kind = "catch_time",
		time = "night",
		count = 5,
		reward = { coins = 700, bait = { id = "worm", amount = 8 } },
	},
	{
		id = "day5",
		kind = "catch_time",
		time = "day",
		count = 5,
		reward = { coins = 600, bait = { id = "worm", amount = 8 } },
	},
	{
		id = "koi2kg",
		kind = "catch_shape",
		shape = "koi",
		minWeight = 2,
		count = 1,
		reward = { coins = 1000, bait = { id = "glow_shrimp", amount = 1 } },
	},
	{
		id = "eel3",
		kind = "catch_shape",
		shape = "eel",
		minWeight = 0,
		count = 3,
		reward = { coins = 600, bait = { id = "worm", amount = 6 } },
	},
	{
		id = "mutant1",
		kind = "catch_mutation",
		count = 1,
		reward = { coins = 1500, bait = { id = "glow_shrimp", amount = 2 } },
	},
	{
		id = "sell2000",
		kind = "sell_coins",
		count = 2000,
		reward = { coins = 500, bait = { id = "dango", amount = 2 } },
	},
}

return Quests
