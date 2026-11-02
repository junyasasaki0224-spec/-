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
H.test("全種 × 全変異 × シルエット で魚のモデルを組み立てられる", function()
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
			H.assert(parts >= 4 and parts <= 110, def.id .. ": part count " .. parts)
			count += 1
		end
	end
	H.assert(count == #Config.Fish * (2 + #Config.Mutations), "count")
end)

print("Battle (相棒バトル)")
local BattleLib = H.require(shared.Lib.Battle)
local function fighterOf(id: string, level: number, mutation: string?)
	local def = Config.FishById[id]
	return BattleLib.fighter(def, math.floor((def.kg[1] + def.kg[2]) * 500), mutation, level)
end
H.test("相性: 水→火 2倍、火→水 0.5倍、霊→霊 2倍、無属性は1倍", function()
	H.assertEq(BattleLib.effectiveness("water", "fire"), 2)
	H.assertEq(BattleLib.effectiveness("fire", "water"), 0.5)
	H.assertEq(BattleLib.effectiveness("spirit", "spirit"), 2)
	H.assertEq(BattleLib.effectiveness("none", "fire"), 1)
	H.assertEq(BattleLib.effectiveness("thunder", "water"), 2)
	H.assertEq(BattleLib.effectiveness("earth", "thunder"), 2)
end)
H.test("レベル・レア度・変異で能力が上がる", function()
	local lo = fighterOf("doro_funa", 1)
	local hi = fighterOf("doro_funa", 30)
	H.assert(hi.maxHp > lo.maxHp and hi.atk > lo.atk, "level")
	local rare = fighterOf("kyubi_koi", 1)
	local common = fighterOf("hasu_koi", 1)
	H.assert(rare.atk > common.atk, "rarity")
	local gold = fighterOf("doro_funa", 10, "rainbow")
	H.assert(gold.atk > fighterOf("doro_funa", 10).atk, "mutation")
end)
H.test("技はレベルで増え、最大4つ。極以上は Lv25 で必殺技", function()
	H.assertEq(#BattleLib.movesFor(Config.FishById.doro_funa, 1), 2)
	H.assertEq(#BattleLib.movesFor(Config.FishById.doro_funa, 15), 4)
	H.assertEq(#BattleLib.movesFor(Config.FishById.doro_funa, 50), 4)
	local epic = BattleLib.movesFor(Config.FishById.oni_unagi, 25)
	H.assertEq(#epic, 4)
	H.assert(table.find(epic, "yoki_burst"), "special move")
	H.assert(
		not table.find(BattleLib.movesFor(Config.FishById.doro_funa, 50), "yoki_burst"),
		"common learned special"
	)
end)
H.test("経験値: レベルが上がり、最大レベルで止まる", function()
	local lv, xp, gained = BattleLib.addXp(1, 0, Config.Battle.xpToNext(1))
	H.assertEq(lv, 2)
	H.assertEq(xp, 0)
	H.assertEq(gained, 1)
	lv = BattleLib.addXp(1, 0, 10 ^ 9)
	H.assertEq(lv, Config.Battle.MaxLevel)
end)
H.test("レアな魚ほどレベルが上がりにくい(同じ経験値で比べる)", function()
	local prev = math.huge
	for _, r in Config.Rarities do
		local lv = BattleLib.addXp(1, 0, 20000, r.id)
		H.assert(lv <= prev, r.id .. " levels faster than a commoner rarity")
		prev = lv
	end
	local common = BattleLib.addXp(1, 0, 20000, "common")
	local secret = BattleLib.addXp(1, 0, 20000, "secret")
	H.assert(common - secret >= 8, ("common Lv%d vs secret Lv%d"):format(common, secret))
end)
H.test("魚を食べさせた経験値: レアほど多く、同じ属性は1.5倍", function()
	local partner = Config.FishById.kappa_koi -- 水
	local water = Config.FishById.hasu_koi
	local earth = Config.FishById.doro_funa
	local grams = function(d)
		return math.floor((d.kg[1] + d.kg[2]) * 500)
	end
	local a = BattleLib.feedXp(water, grams(water), partner)
	local b = BattleLib.feedXp(earth, grams(earth), partner)
	H.assert(a > b, "same element bonus")
	H.assert(BattleLib.feedXp(Config.FishById.kyubi_koi, 5000, partner) > a * 20, "rarity")
end)
H.test("同じレベル同士の1対1は数ターン(3〜12)で決着する", function()
	local turns = {}
	for i = 1, 200 do
		-- 水 vs 土(相性なし)
		local p = fighterOf("kappa_koi", 15)
		local e = fighterOf("ko_namazu", 15)
		local st = BattleLib.new({ p }, { e })
		while not st.over do
			BattleLib.turn(st, { kind = "move", index = 1 }, rng)
		end
		table.insert(turns, st.turn)
	end
	table.sort(turns)
	local median = turns[100]
	H.assert(median >= 3 and median <= 12, "median turns " .. median)
end)
H.test("レベルが10高い方がほぼ勝つ / 相性の良い方が勝ちやすい", function()
	local wins = 0
	for _ = 1, 200 do
		local st = BattleLib.new({ fighterOf("hasu_koi", 20) }, { fighterOf("hasu_koi", 10) })
		while not st.over do
			BattleLib.turn(st, { kind = "move", index = 1 }, rng)
		end
		if st.winner == "player" then
			wins += 1
		end
	end
	H.assert(wins > 180, "level advantage wins " .. wins)
	wins = 0
	for _ = 1, 200 do
		-- 水(有利) vs 火、同じレベル・同じ形。プレイヤーは属性技(1番目)を使う
		local st = BattleLib.new({ fighterOf("hasu_koi", 12) }, { fighterOf("kitsunebi_ayu", 12) })
		while not st.over do
			BattleLib.turn(st, { kind = "move", index = 1 }, rng)
		end
		if st.winner == "player" then
			wins += 1
		end
	end
	H.assert(wins > 120, "type advantage wins " .. wins)
end)
H.test("倒れると次の魚が出て、全員倒れたら決着。交代・逃げるも動く", function()
	local st = BattleLib.new(
		{ fighterOf("doro_funa", 1), fighterOf("hasu_koi", 1) },
		{ fighterOf("numa_mizuchi", 40) }
	)
	H.assert(not BattleLib.validAction(st, { kind = "switch", slot = 1 }), "switch to active")
	H.assert(BattleLib.validAction(st, { kind = "switch", slot = 2 }), "switch")
	H.assert(not BattleLib.validAction(st, { kind = "move", index = 9 }), "bad move index")
	local events = BattleLib.turn(st, { kind = "switch", slot = 2 }, rng)
	H.assertEq(events[1].kind, "switch")
	local guard = 0
	while not st.over and guard < 100 do
		guard += 1
		BattleLib.turn(st, { kind = "move", index = 1 }, rng)
	end
	H.assertEq(st.winner, "enemy")
	local st2 = BattleLib.new({ fighterOf("doro_funa", 1) }, { fighterOf("doro_funa", 1) })
	BattleLib.turn(st2, { kind = "run" }, rng)
	H.assert(st2.over and st2.winner == "enemy", "run")
end)
H.test(
	"妖怪退治の相手はだんだん強くなる(一番強い魚のレベルが上がっていく)",
	function()
		local prev = 0
		for _, t in Config.Trainers do
			local top = 0
			for _, m in t.team do
				top = math.max(top, m.level)
			end
			H.assert(top > prev, t.id .. " not stronger than previous")
			prev = top
		end
	end
)

H.test("レア度が上がるほど大きく、派手になる(大きさ・部品の数・光)", function()
	local FishBuilder = H.require(shared.Lib.FishBuilder)
	local prevScale = 0
	for _, r in Config.Rarities do
		local st = FishBuilder.RarityStyle[r.id]
		H.assert(st and st.scale > prevScale, r.id .. " is not bigger than the rarity below")
		prevScale = st.scale
	end
	-- レア度ごとの平均の部品数が下がらない
	local sum, count = {}, {}
	for _, def in Config.Fish do
		local n = 0
		for _, d in FishBuilder.build(def, {}):GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		sum[def.rarity] = (sum[def.rarity] or 0) + n
		count[def.rarity] = (count[def.rarity] or 0) + 1
	end
	local prev = 0
	for _, r in Config.Rarities do
		local avg = sum[r.id] / count[r.id]
		H.assert(avg >= prev, ("%s avg parts %.1f < previous %.1f"):format(r.id, avg, prev))
		prev = avg
	end
	H.assert(
		FishBuilder.sizeOf(Config.FishById.yamata_chochin) > FishBuilder.sizeOf(Config.FishById.doro_funa) * 2,
		"secret vs common size"
	)
end)
H.test("50種そろっていて、釣り場ごとに全レア度がいる", function()
	H.assertEq(#Config.Fish, 50)
	for _, spot in { "swamp", "nushi_lake" } do
		for _, r in Config.Rarities do
			local found = false
			for _, f in Config.Fish do
				if f.spot == spot and f.rarity == r.id then
					found = true
				end
			end
			H.assert(found, spot .. " has no " .. r.id)
		end
	end
end)

print("Anime meshes (アニメ風メッシュ)")
H.test("Blender で作ったメッシュの大きさの表が全50種そろっている", function()
	local M = H.require(shared.Config.FishMeshes)
	for _, f in Config.Fish do
		local info = M.sizes[f.id]
		H.assert(info and info.length > 0 and info.height > 0, "missing mesh size for " .. f.id)
	end
end)
H.test(
	"ReplicatedStorage.FishMeshes があればメッシュで組み立て、なければパーツで組み立てる",
	function()
		local roblox = require("@lune/roblox")
		-- Studio で読み込んだ状態を真似る(MeshPart の代わりに Part)
		local rs = roblox.Instance.new("Folder")
		local folder = roblox.Instance.new("Model")
		folder.Name = "FishMeshes"
		folder.Parent = rs
		local function mesh(name: string, size)
			local p = roblox.Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Parent = folder
		end
		mesh("hasu_koi", roblox.Vector3.new(1.17, 1.22, 2.68))
		mesh("hasu_koi_Outline", roblox.Vector3.new(1.2, 1.26, 2.72))
		-- 読み込み時に色・法線のテクスチャ(SurfaceAppearance)が付く
		for _, n in { "hasu_koi", "hasu_koi_Outline" } do
			roblox.Instance.new("SurfaceAppearance").Parent = folder:FindFirstChild(n)
		end
		H.globals = {
			game = {
				GetService = function(_, name)
					assert(name == "ReplicatedStorage")
					return rs
				end,
			},
		}
		local FB = H.fresh(shared.Lib.FishBuilder)
		H.globals = nil
		local def = Config.FishById.hasu_koi
		local m = FB.build(def, {})
		H.assert(m:GetAttribute("Anime") == true, "did not use the mesh")
		H.assert(m:FindFirstChild("Body") and m:FindFirstChild("Outline"), "body/outline missing")
		local M = H.require(shared.Config.FishMeshes)
		local expected = M.sizes.hasu_koi.height * M.unit * FB.sizeOf(def)
		H.assertNear(m.Body.Size.Y, expected, 0.01, "scaled height")
		H.assert(m.Body:FindFirstChildWhichIsA("SurfaceAppearance") ~= nil, "body keeps its textures")
		H.assert(m.Outline:FindFirstChildWhichIsA("SurfaceAppearance") == nil, "outline is a flat color")
		local gold = FB.build(def, { mutation = "gold" })
		H.assert(gold:FindFirstChild("Tint") ~= nil, "gold tint shell")
		H.assert(gold.Tint:FindFirstChildWhichIsA("SurfaceAppearance") == nil, "tint shell has no texture")
		local sil = FB.build(def, { silhouette = true })
		H.assert(sil.Body.Color.R < 0.15, "silhouette is dark")
		H.assert(sil.Body:FindFirstChildWhichIsA("SurfaceAppearance") == nil, "silhouette drops textures")
		-- 置いていない魚・強制パーツはパーツで組み立てる
		H.assert(
			FB.build(Config.FishById.doro_funa, {}):GetAttribute("Anime") == nil,
			"fallback for missing mesh"
		)
		H.assert(FB.build(def, { forceParts = true }):GetAttribute("Anime") == nil, "forceParts")
	end
)

local ok = H.summary()
process.exit(if ok then 0 else 1)
