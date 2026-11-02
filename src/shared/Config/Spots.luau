--!strict
-- 釣り場の表。available=false の釣り場は「近日公開」として鳥居に表示されるだけ。
-- 新しい釣り場は: 1) この表に行を追加 2) Fish/ に魚の表を追加 3) World/ に地形ビルダーを追加
-- origin  : 釣り場の中心(ワールド座標)。釣り場同士は離して配置し、鳥居でワープする
-- water   : 水面の範囲(中心からの相対, x/z は半径)。投げた仕掛けはこの範囲内に着水する
-- spawn   : 到着地点(中心からの相対)

export type Spot = {
	id: string,
	order: number,
	available: boolean,
	unlockCoins: number,
	unlockRodTier: number,
	priceMultiplier: number,
	mutations: { string },
	fishPool: string?, -- 別の釣り場の魚表を流用する場合
	origin: { x: number, y: number, z: number },
	water: { x: number, z: number, rx: number, rz: number, y: number },
	spawn: { x: number, y: number, z: number },
	completionReward: number,
}

local Spots: { Spot } = {
	{
		id = "swamp",
		order = 1,
		available = true,
		unlockCoins = 0,
		unlockRodTier = 1,
		priceMultiplier = 1,
		mutations = { "onibi" },
		origin = { x = 0, y = 0, z = 0 },
		water = { x = 0, z = -10, rx = 46, rz = 38, y = 0 },
		spawn = { x = 0, y = 4, z = 46 },
		completionReward = 25000,
	},
	{
		id = "nushi_lake",
		order = 0, -- 村の中央。解放不要
		available = true,
		unlockCoins = 0,
		unlockRodTier = 1,
		priceMultiplier = 1.5,
		mutations = { "onibi" },
		fishPool = "swamp",
		origin = { x = 0, y = 0, z = 600 },
		water = { x = 0, z = 0, rx = 34, rz = 34, y = 0 },
		spawn = { x = 0, y = 4, z = 62 },
		completionReward = 0,
	},
	{
		id = "river",
		order = 2,
		available = false,
		unlockCoins = 2000,
		unlockRodTier = 2,
		priceMultiplier = 2,
		mutations = {},
		origin = { x = 600, y = 0, z = 0 },
		water = { x = 0, z = 0, rx = 20, rz = 60, y = 0 },
		spawn = { x = 30, y = 4, z = 0 },
		completionReward = 100000,
	},
	{
		id = "waterfall",
		order = 3,
		available = false,
		unlockCoins = 25000,
		unlockRodTier = 4,
		priceMultiplier = 4,
		mutations = { "crystal" },
		origin = { x = 1200, y = 0, z = 0 },
		water = { x = 0, z = 0, rx = 30, rz = 30, y = 0 },
		spawn = { x = 0, y = 4, z = 40 },
		completionReward = 500000,
	},
	{
		id = "night_lake",
		order = 4,
		available = false,
		unlockCoins = 300000,
		unlockRodTier = 6,
		priceMultiplier = 8,
		mutations = {},
		origin = { x = 1800, y = 0, z = 0 },
		water = { x = 0, z = 0, rx = 50, rz = 50, y = 0 },
		spawn = { x = 0, y = 4, z = 60 },
		completionReward = 3000000,
	},
	{
		id = "sea",
		order = 5,
		available = false,
		unlockCoins = 4000000,
		unlockRodTier = 8,
		priceMultiplier = 20,
		mutations = {},
		origin = { x = 2400, y = 0, z = 0 },
		water = { x = 0, z = -30, rx = 70, rz = 40, y = 0 },
		spawn = { x = 0, y = 4, z = 40 },
		completionReward = 30000000,
	},
	{
		id = "ryugu",
		order = 6,
		available = false,
		unlockCoins = 50000000,
		unlockRodTier = 10,
		priceMultiplier = 50,
		mutations = { "pearl" },
		origin = { x = 3000, y = 0, z = 0 },
		water = { x = 0, z = 0, rx = 50, rz = 50, y = 0 },
		spawn = { x = 0, y = 4, z = 60 },
		completionReward = 300000000,
	},
}

return Spots
