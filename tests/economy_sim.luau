-- 経済のシミュレーション(設計確認用): lune run tests/economy_sim.luau
-- 手動で遊ぶプレイヤーが「売れる魚はすべて売り、買える竿は買い、行ける釣り場はすぐ解放する」と仮定し、
-- 何分で各段階に届くかを出す。次の釣り場の魚はまだ無いので「沼の魚 × その釣り場の倍率」で近似する。
local H = require("./harness")
local shared = H.root("src/shared")
local Config = H.require(shared.Config)
local Roll = H.require(shared.Lib.Roll)
local Pricing = H.require(shared.Lib.Pricing)

math.randomseed(7)
local rng = function()
	return math.random()
end
local FT = Config.Tuning.Fishing

local function simulate(label: string, multipliers: { number }, runs: number)
	local results = {}
	for _ = 1, runs do
		local t, coins, rodTier = 0, 0, 1
		local spotIndex = 1
		local order = { "swamp", "river", "waterfall", "night_lake", "sea", "ryugu" }
		local reached = { rod = {}, spot = {} }
		while t < 60 * 60 * 40 and spotIndex < #order do
			local spot = Config.SpotById[order[spotIndex]]
			local rod = Config.RodByTier[rodTier]
			local luck = Roll.luck({
				rodLuck = rod.luck,
				baitLuck = 0,
				power = 0.8,
				distanceBonus = FT.distanceLuckBonus,
				multipliers = multipliers,
				maxLuck = FT.maxLuck,
			})
			local rarityId = Roll.rarity(rng, Config.Rarities, luck)
			local rarity = Config.RarityById[rarityId]
			local cond = {
				spot = "swamp",
				time = ({ "morning", "day", "night" })[math.random(1, 3)],
				weather = ({ "sunny", "rain", "fog", "thunder" })[math.random(1, 4)],
			}
			local fish = Roll.fish(rng, Config.Fish, Config.Rarities, "swamp", cond, rarityId)
			local grams = Roll.grams(rng, fish, FT.weightSkew)
			local mut = Roll.mutation(rng, Config.Mutations, spot.mutations)
			local mutMult = if mut then Config.MutationById[mut].multiplier else 1
			-- 1回の釣り: 待ち(3〜15秒) + 引き上げ + 投げ・結果の操作 約8秒。手動の失敗率はレアほど上がる
			t += (FT.biteMinSeconds + FT.biteMaxSeconds) / 2 + rarity.reelSeconds / rod.reelSpeed + 8
			local success = math.random() < (1 - (rarity.order - 1) * 0.06)
			if success then
				coins += Pricing.sellPrice(fish, grams, {
					rarityBasePrice = rarity.basePrice,
					mutationMultiplier = mutMult,
					spotMultiplier = spot.priceMultiplier,
					sellMultiplier = 1,
					weightMin = FT.weightPriceMin,
					weightMax = FT.weightPriceMax,
				})
			end
			-- 買い物: 次の釣り場の条件 → 竿 の順
			local nextSpot = Config.SpotById[order[spotIndex + 1]]
			if rodTier >= nextSpot.unlockRodTier and coins >= nextSpot.unlockCoins then
				coins -= nextSpot.unlockCoins
				spotIndex += 1
				reached.spot[nextSpot.id] = t
			elseif
				rodTier < 10
				and coins >= Config.RodByTier[rodTier + 1].price
				and rodTier < nextSpot.unlockRodTier + 1
			then
				coins -= Config.RodByTier[rodTier + 1].price
				rodTier += 1
				reached.rod[rodTier] = t
			end
		end
		table.insert(results, reached)
	end
	local function median(list: { number }): number?
		if #list == 0 then
			return nil
		end
		table.sort(list)
		return list[math.ceil(#list / 2)]
	end
	print(("\n[%s] %d回の中央値"):format(label, runs))
	for _, id in { "river", "waterfall", "night_lake", "sea", "ryugu" } do
		local times = {}
		for _, r in results do
			if r.spot[id] then
				table.insert(times, r.spot[id])
			end
		end
		local m = median(times)
		print(
			("  %-11s 解放まで: %s"):format(
				id,
				if m then ("%.0f分 (%.1f時間)"):format(m / 60, m / 3600) else "40時間以内に届かず"
			)
		)
	end
end

simulate("無課金", {}, 40)
simulate("2倍の運パス", { 2 }, 40)
