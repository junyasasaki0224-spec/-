-- 経済のシミュレーション(設計確認用): lune run tests/economy_sim.luau
-- 手動で遊ぶプレイヤーが「売れる魚はすべて売り、買える竿は買い、行ける釣り場はすぐ解放する」と仮定し、
-- 何分で各段階に届くかを出す。魚の表がある釣り場は本物の魚で、まだ無い釣り場は「沼の魚 × その釣り場の倍率」で近似する。
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

local hasFish: { [string]: boolean } = {}
for _, f in Config.Fish do
	hasFish[f.spot] = true
end

local function simulate(label: string, multipliers: { number }, runs: number)
	local results = {}
	for _ = 1, runs do
		local t, coins, rodTier = 0, 0, 1
		local spotIndex = 1
		local order = { "swamp", "nushi_lake", "river", "sea", "waterfall", "night_lake", "ryugu" }
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
			local pool = if hasFish[spot.fishPool or spot.id] then spot.fishPool or spot.id else "swamp"
			local cond = {
				spot = pool,
				time = ({ "morning", "day", "night" })[math.random(1, 3)],
				weather = ({ "sunny", "rain", "fog", "thunder" })[math.random(1, 4)],
			}
			local fish = Roll.fish(rng, Config.Fish, Config.Rarities, pool, cond, rarityId)
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
	for _, id in { "nushi_lake", "river", "sea", "waterfall", "night_lake", "ryugu" } do
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

-- 今遊べる内容(沼・ぬしの湖)で、1時間の稼ぎと竿を買える時間を見る
local function catchValue(spotId: string, rodTier: number): (number, number)
	local spot = Config.SpotById[spotId]
	local rod = Config.RodByTier[rodTier]
	local luck = Roll.luck({
		rodLuck = rod.luck,
		baitLuck = 0,
		power = 0.8,
		distanceBonus = FT.distanceLuckBonus,
		multipliers = {},
		maxLuck = FT.maxLuck,
	})
	local rarityId = Roll.rarity(rng, Config.Rarities, luck)
	local rarity = Config.RarityById[rarityId]
	local cond = {
		spot = spotId,
		time = ({ "morning", "day", "night", "day" })[math.random(1, 4)],
		weather = ({ "sunny", "sunny", "rain", "fog", "thunder" })[math.random(1, 5)],
	}
	local fish = Roll.fish(rng, Config.Fish, Config.Rarities, spot.fishPool or spotId, cond, rarityId)
	local grams = Roll.grams(rng, fish, FT.weightSkew)
	local mut = Roll.mutation(rng, Config.Mutations, spot.mutations)
	local secs = (FT.biteMinSeconds + FT.biteMaxSeconds) / 2 + rarity.reelSeconds / rod.reelSpeed + 8
	if math.random() >= 1 - (rarity.order - 1) * 0.06 then
		return 0, secs
	end
	return Pricing.sellPrice(fish, grams, {
		rarityBasePrice = rarity.basePrice,
		mutationMultiplier = if mut then Config.MutationById[mut].multiplier else 1,
		spotMultiplier = spot.priceMultiplier,
		sellMultiplier = 1,
		weightMin = FT.weightPriceMin,
		weightMax = FT.weightPriceMax,
	}),
		secs
end

print("\n[今遊べる内容] 1時間の稼ぎ(手動)")
for _, spotId in { "swamp", "nushi_lake", "river", "sea" } do
	local line = "  " .. spotId .. ":"
	for _, tier in { 1, 3, 5, 10 } do
		local coins, t = 0, 0
		for _ = 1, 50000 do
			local p, s = catchValue(spotId, tier)
			coins += p
			t += s
		end
		line ..= ("  竿%d %.0f"):format(tier, coins / t * 3600)
	end
	print(line)
end
print(
	"[今遊べる内容] 竿を買える時間(行ける中でいちばん稼げる釣り場で釣る: 沼 → 湖 → 川 → 海。売れる魚は全部売る、20回の中央値)"
)
local rodTimes = {}
local spotTimes: { [string]: { number } } = {}
for _ = 1, 20 do
	local t, coins, tier = 0, 0, 1
	local open = { swamp = true }
	while tier < 10 and t < 3600 * 200 do
		-- 条件を満たした釣り場を開け(小判を払う)、いちばん倍率の高い釣り場で釣る
		local spotId, best = "swamp", 0
		for _, sp in Config.Spots do
			if sp.available and hasFish[sp.fishPool or sp.id] then
				if not open[sp.id] and tier >= sp.unlockRodTier and coins >= sp.unlockCoins then
					coins -= sp.unlockCoins
					open[sp.id] = true
					spotTimes[sp.id] = spotTimes[sp.id] or {}
					table.insert(spotTimes[sp.id], t / 60)
				end
				if open[sp.id] and sp.priceMultiplier > best then
					spotId, best = sp.id, sp.priceMultiplier
				end
			end
		end
		local p, s = catchValue(spotId, tier)
		t += s
		coins += p
		if coins >= Config.RodByTier[tier + 1].price then
			coins -= Config.RodByTier[tier + 1].price
			tier += 1
			rodTimes[tier] = rodTimes[tier] or {}
			table.insert(rodTimes[tier], t / 60)
		end
	end
end
local line = " "
for tier = 2, 10 do
	local l = rodTimes[tier] or {}
	table.sort(l)
	local m = l[math.ceil(#l / 2)]
	line ..= (" 竿%d=%s"):format(
		tier,
		if not m then "-" elseif m < 120 then ("%.0f分"):format(m) else ("%.1f時間"):format(m / 60)
	)
end
print(line)
local sline = " "
for _, id in { "nushi_lake", "river", "sea" } do
	local l = spotTimes[id] or {}
	table.sort(l)
	local m = l[math.ceil(#l / 2)]
	sline ..= (" %s=%s"):format(
		id,
		if not m then "-" elseif m < 120 then ("%.0f分"):format(m) else ("%.1f時間"):format(m / 60)
	)
end
print("  釣り場を開ける時間:" .. sline)
