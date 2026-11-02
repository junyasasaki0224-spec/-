--!strict
-- 竿の表(10段階)。1段目は最初から持っている。
-- luck        : 運のボーナス(加算, 0.1 = +10%)
-- reelSpeed   : 巻き取り速度の倍率
-- netSize     : 網の枠の大きさの倍率
-- 価格は 500 から約3.16倍ずつ(最上段 500万)

export type Rod = {
	tier: number,
	id: string,
	price: number,
	luck: number,
	reelSpeed: number,
	netSize: number,
	color: string,
	accent: string,
}

local Rods: { Rod } = {}

local PRICES = { 0, 500, 1600, 5000, 16000, 50000, 160000, 500000, 1600000, 5000000 }
local COLORS = {
	{ "#8B6A43", "#C9A36B" }, -- 竹
	{ "#7A4F2A", "#D9B98A" },
	{ "#5C3A21", "#E8C26A" },
	{ "#3E2F2A", "#C24A3A" },
	{ "#2B2B3A", "#7CC6FF" },
	{ "#1F3B2D", "#9BEA9B" },
	{ "#3A1F3B", "#E59BFF" },
	{ "#402010", "#FFB547" },
	{ "#101828", "#7DF9FF" },
	{ "#1A0F05", "#FFE38A" }, -- 竜骨の竿
}

for tier = 1, 10 do
	table.insert(Rods, {
		tier = tier,
		id = "rod" .. tier,
		price = PRICES[tier],
		luck = (tier - 1) * 0.10,
		reelSpeed = 1 + (tier - 1) * 0.05,
		netSize = 1 + (tier - 1) * 0.03,
		color = COLORS[tier][1],
		accent = COLORS[tier][2],
	})
end

return Rods
