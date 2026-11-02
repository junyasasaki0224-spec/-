--!strict
-- 変異の表。抽選は「珍しい順」に判定し、最初に当たったものを採用する。
-- 全釣り場共通の変異 + 釣り場ごとの特別な変異(Spots.luau の mutations に id を書く)。
-- visual: クライアントの見た目(FishBuilder が解釈)

export type Mutation = {
	id: string,
	chance: number,
	multiplier: number,
	color: string,
	visual: string,
	global: boolean,
}

local Mutations: { Mutation } = {
	{ id = "rainbow", chance = 0.0002, multiplier = 5, color = "#FF8BF0", visual = "rainbow", global = true },
	{ id = "thunder", chance = 0.002, multiplier = 3, color = "#FFE34D", visual = "thunder", global = true },
	{ id = "sakura", chance = 0.01, multiplier = 2, color = "#FFB7D5", visual = "sakura", global = true },
	{ id = "gold", chance = 0.04, multiplier = 1.5, color = "#FFD34D", visual = "gold", global = true },
	-- 釣り場ごとの特別な変異
	{ id = "onibi", chance = 0.005, multiplier = 2.5, color = "#6BE3FF", visual = "onibi", global = false }, -- 沼: 鬼火
	{ id = "crystal", chance = 0.005, multiplier = 3, color = "#BDF4FF", visual = "crystal", global = false }, -- 滝つぼ: 水晶
	{ id = "pearl", chance = 0.005, multiplier = 4, color = "#FFF4E8", visual = "pearl", global = false }, -- 竜宮: 真珠
}

return Mutations
