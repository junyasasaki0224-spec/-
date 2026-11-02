-- テストの実行: lune run tests/run.luau  (リポジトリの一番上で実行)
local process = require("@lune/process")
local H = require("./harness")

local shared = H.root("src/shared")
local Config = H.require(shared.Config)
local Roll = H.require(shared.Lib.Roll)
local Pricing = H.require(shared.Lib.Pricing)
local WorldClock = H.require(shared.Lib.WorldClock)
local Format = H.require(shared.Lib.Format)
local Locale = H.require(shared.Locale)

math.randomseed(20261101)
local rng = function()
	return math.random()
end

print("Config")
H.test("Config.Validate() に問題がない", function()
	local problems = Config.Validate()
	H.assert(#problems == 0, table.concat(problems, "\n      "))
end)
H.test("沼の魚は30種、レア度の内訳が揃っている", function()
	local n, by = 0, {}
	for _, f in Config.Fish do
		if f.spot == "swamp" then
			n += 1
			by[f.rarity] = (by[f.rarity] or 0) + 1
		end
	end
	H.assertEq(n, 30, "swamp fish")
	for _, r in Config.Rarities do
		H.assert((by[r.id] or 0) >= 1, "rarity without fish: " .. r.id)
	end
end)
H.test("竿の価格は増え続け、最上段は約500万", function()
	for i = 2, #Config.Rods do
		H.assert(Config.Rods[i].price > Config.Rods[i - 1].price, "rod price not increasing at " .. i)
	end
	H.assertEq(Config.Rods[10].price, 5000000)
end)

print("Roll (抽選)")
H.test("運1の確率表は基本の出現率そのもの", function()
	local t = Roll.rarityTable(Config.Rarities, 1)
	for i, r in Config.Rarities do
		H.assertNear(t[i].p, r.chance, 1e-9, r.id)
	end
end)
H.test("運+50% で特上以上が1.5倍、増えた分だけ並が減る", function()
	local t = Roll.rarityTable(Config.Rarities, 1.5)
	local sum = 0
	for i, r in Config.Rarities do
		sum += t[i].p
		if r.luckAffected then
			H.assertNear(t[i].p, r.chance * 1.5, 1e-9, r.id)
		end
	end
	H.assertNear(sum, 1, 1e-9, "sum")
	H.assertNear(t[2].p, 0.25, 1e-9, "uncommon unchanged")
	H.assertNear(t[1].p, 0.60 - (0.15 * 0.5), 1e-6, "common reduced")
end)
H.test("運が極端に高くても確率の合計は1で、マイナスにならない", function()
	for _, luck in { 1, 2, 5, 8, 20, 1000 } do
		local t = Roll.rarityTable(Config.Rarities, luck)
		local sum = 0
		for _, row in t do
			H.assert(row.p >= 0, "negative")
			sum += row.p
		end
		H.assertNear(sum, 1, 1e-9, "sum luck=" .. luck)
	end
end)
H.test("出現率の実測(20万回)が表どおり", function()
	local counts = {}
	local N = 200000
	for _ = 1, N do
		local id = Roll.rarity(rng, Config.Rarities, 1)
		counts[id] = (counts[id] or 0) + 1
	end
	H.assertNear((counts.common or 0) / N, 0.60, 0.006, "common")
	H.assertNear((counts.uncommon or 0) / N, 0.25, 0.005, "uncommon")
	H.assertNear((counts.rare or 0) / N, 0.10, 0.004, "rare")
	H.assertNear((counts.epic or 0) / N, 0.04, 0.003, "epic")
	H.assertNear((counts.legendary or 0) / N, 0.009, 0.0015, "legendary")
end)
H.test("最低保証(上以上)では並が出ない", function()
	for _ = 1, 5000 do
		H.assert(Roll.rarity(rng, Config.Rarities, 1, 2) ~= "common", "common with minOrder=2")
	end
end)
H.test(
	"どの時間・天気・レア度でも沼で必ず魚が選ばれ、条件に合っている",
	function()
		for _, time in { "morning", "day", "night" } do
			for _, weather in { "sunny", "rain", "fog", "thunder" } do
				local cond = { spot = "swamp", time = time, weather = weather }
				for _, r in Config.Rarities do
					for _ = 1, 20 do
						local f = Roll.fish(rng, Config.Fish, Config.Rarities, "swamp", cond, r.id)
						H.assert(f ~= nil, ("no fish %s/%s/%s"):format(time, weather, r.id))
						H.assert(Roll.isEligible(f, "swamp", cond), "ineligible " .. f.id)
					end
				end
			end
		end
	end
)
H.test("秘伝「八岐提灯」は雨の夜だけ", function()
	local seen = {}
	for _, time in { "morning", "day", "night" } do
		for _, weather in { "sunny", "rain", "fog", "thunder" } do
			local f = Roll.fish(
				rng,
				Config.Fish,
				Config.Rarities,
				"swamp",
				{ spot = "swamp", time = time, weather = weather },
				"secret"
			)
			if f and f.rarity == "secret" then
				table.insert(seen, time .. "/" .. weather)
			end
		end
	end
	H.assertEq(#seen, 1, "secret windows")
	H.assertEq(seen[1], "night/rain")
end)
H.test("変異の出現率(全釣り場共通 + 沼の鬼火)", function()
	local counts = {}
	local N = 400000
	for _ = 1, N do
		local m = Roll.mutation(rng, Config.Mutations, { "onibi" })
		if m then
			counts[m] = (counts[m] or 0) + 1
		end
	end
	H.assertNear((counts.gold or 0) / N, 0.04 * (1 - 0.0172), 0.002, "gold")
	H.assertNear((counts.sakura or 0) / N, 0.01, 0.001, "sakura")
	H.assertNear((counts.onibi or 0) / N, 0.005, 0.0007, "onibi")
	H.assert(counts.crystal == nil and counts.pearl == nil, "foreign spot mutation leaked")
end)
H.test("重さは範囲内、軽い魚の方が多い", function()
	local f = Config.FishById.hasu_koi
	local light = 0
	for _ = 1, 10000 do
		local g = Roll.grams(rng, f, Config.Tuning.Fishing.weightSkew)
		H.assert(g >= f.kg[1] * 1000 - 1 and g <= f.kg[2] * 1000 + 1, "out of range " .. g)
		if g < (f.kg[1] + f.kg[2]) * 500 then
			light += 1
		end
	end
	H.assert(light > 5500, "skew")
end)
H.test("運の合計: 竿10段+エサ+最大飛距離+ブースト、上限で止まる", function()
	local l = Roll.luck({
		rodLuck = 0.9,
		baitLuck = 0.3,
		power = 1,
		distanceBonus = 0.2,
		multipliers = { 2, 2 },
		maxLuck = 20,
	})
	H.assertNear(l, (1 + 0.9 + 0.3 + 0.2) * 4, 1e-9)
	local capped = Roll.luck({
		rodLuck = 0.9,
		baitLuck = 0.6,
		power = 1,
		distanceBonus = 0.2,
		multipliers = { 2, 2, 2, 2 },
		maxLuck = 20,
	})
	H.assertEq(capped, 20)
end)

print("Pricing (売値)")
H.test("基本の売値 × 重さ(0.5〜2倍) × 変異 × 釣り場 × VIP", function()
	local f = Config.FishById.doro_funa
	local ctx = {
		rarityBasePrice = 10,
		mutationMultiplier = 1,
		spotMultiplier = 1,
		sellMultiplier = 1,
		weightMin = 0.5,
		weightMax = 2,
	}
	H.assertEq(Pricing.sellPrice(f, f.kg[1] * 1000, ctx), 5)
	H.assertEq(Pricing.sellPrice(f, f.kg[2] * 1000, ctx), 20)
	ctx.mutationMultiplier = 1.5
	ctx.spotMultiplier = 50
	ctx.sellMultiplier = 1.2
	H.assertEq(Pricing.sellPrice(f, f.kg[2] * 1000, ctx), 1800)
end)

print("WorldClock (昼夜・天気・ぬし)")
local W = Config.Tuning.World
H.test("20分で1日、昼と夜の両方がある", function()
	local phases = {}
	for t = 0, W.dayLengthSeconds, 10 do
		phases[WorldClock.phase(WorldClock.clockTime(1700000000 + t, W), W)] = true
	end
	H.assert(phases.morning and phases.day and phases.night, "missing phase")
end)
H.test("天気は10分ごとに変わり、割合は設定どおり(決定的)", function()
	local counts, total = {}, 20000
	for i = 0, total - 1 do
		local w = WorldClock.weatherAt(i * W.weatherPeriodSeconds + 5, W)
		counts[w] = (counts[w] or 0) + 1
		H.assertEq(w, WorldClock.weatherAt(i * W.weatherPeriodSeconds + 300, W), "same slot")
	end
	H.assertNear(counts.sunny / total, 0.45, 0.02, "sunny")
	H.assertNear(counts.rain / total, 0.25, 0.02, "rain")
	H.assertNear(counts.fog / total, 0.20, 0.02, "fog")
	H.assertNear(counts.thunder / total, 0.10, 0.015, "thunder")
end)
H.test("ぬしは1時間に1回、5分間", function()
	local N = Config.Tuning.Nushi
	local activeSeconds = 0
	for t = 0, 3599 do
		if WorldClock.nushi(1700000000 + t, N) then
			activeSeconds += 1
		end
	end
	H.assertEq(activeSeconds, 300)
end)

print("Format / Locale")
H.test("小判の表示(日本語は万・億、英語は K/M)", function()
	H.assertEq(Format.coins(9999, "ja"), "9999")
	H.assertEq(Format.coins(25000, "ja"), "2.5万")
	H.assertEq(Format.coins(50000000, "ja"), "5000万")
	H.assertEq(Format.coins(300000000, "ja"), "3億")
	H.assertEq(Format.coins(25000, "en"), "25K")
	H.assertEq(Format.coins(4000000, "en"), "4M")
	H.assertEq(Format.kg(1234), "1.23kg")
end)
H.test("日本語と英語の文言キーが一致している", function()
	local missing = Locale.missingKeys()
	H.assert(#missing == 0, table.concat(missing, ", "))
end)
H.test(
	"データから組み立てる文言キー(レア度・変異・釣り場・エサ…)がすべてある",
	function()
		local keys = {}
		for _, r in Config.Rarities do
			table.insert(keys, "rarity_" .. r.id)
		end
		for _, m in Config.Mutations do
			table.insert(keys, "mutation_" .. m.id)
		end
		for _, s in Config.Spots do
			table.insert(keys, "spot_" .. s.id)
		end
		for _, b in Config.Baits do
			table.insert(keys, "bait_" .. b.id)
		end
		for _, t in Config.Tuning.Titles do
			table.insert(keys, "title_" .. t)
		end
		for _, gp in Config.Products.GamePasses do
			table.insert(keys, "pass_" .. gp.key)
			table.insert(keys, "pass_" .. gp.key .. "_desc")
		end
		for _, dp in Config.Products.DevProducts do
			table.insert(keys, "product_" .. dp.key)
			table.insert(keys, "product_" .. dp.key .. "_desc")
		end
		for _, x in { "koi", "catfish", "puffer", "eel", "angler", "ray" } do
			table.insert(keys, "shape_" .. x)
		end
		for _, x in { "any", "day", "night", "morning" } do
			table.insert(keys, "time_" .. x)
		end
		for _, x in { "any", "sunny", "rain", "fog", "thunder" } do
			table.insert(keys, "weather_" .. x)
		end
		local missing = {}
		for _, k in keys do
			for _, lang in { "ja", "en" } do
				if Locale.t(k, nil, lang) == k then
					table.insert(missing, lang .. ":" .. k)
				end
			end
		end
		H.assert(#missing == 0, table.concat(missing, ", "))
	end
)

print("FishBuilder (見た目の生成)")
H.test("全30種 × 全変異 × シルエット で魚のモデルを組み立てられる", function()
	local FishBuilder = H.require(shared.Lib.FishBuilder)
	local count = 0
	for _, def in Config.Fish do
		local variants = { {}, { silhouette = true } }
		for _, m in Config.Mutations do
			table.insert(variants, { mutation = m.id, scale = 1.3, anchored = true })
		end
		for _, opts in variants do
			local model = FishBuilder.build(def, opts)
			H.assert(model.PrimaryPart ~= nil and model.PrimaryPart.Name == "Body", def.id .. ": no Body")
			local parts = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
					H.assert(
						d.Size.X > 0 and d.Size.Y > 0 and d.Size.Z > 0,
						def.id .. ": zero-size part " .. d.Name
					)
				end
			end
			H.assert(parts >= 4 and parts <= 60, def.id .. ": part count " .. parts)
			count += 1
		end
	end
	H.assert(count == #Config.Fish * (2 + #Config.Mutations), "count")
end)

local ok = H.summary()
process.exit(if ok then 0 else 1)
