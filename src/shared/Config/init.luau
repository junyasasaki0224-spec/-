--!strict
-- Config: すべてのゲームデータの入り口。
-- 表(配列)と、id から引ける索引(ById)を両方提供する。
-- 起動時に Validate() で表の整合性をチェックし、間違いがあれば Output に出す。

local Types = require(script.Parent.Lib.Types)

local Rarities = require(script.Rarities)
local Mutations = require(script.Mutations)
local Spots = require(script.Spots)
local Rods = require(script.Rods)
local Baits = require(script.Baits)
local Quests = require(script.Quests)
local Products = require(script.Products)
local Tuning = require(script.Tuning)
local Battle = require(script.Battle)
local Trainers = require(script.Trainers)
local Cries = require(script.Cries)
local Music = require(script.Music)
local Online = require(script.Online)
local Bosses = require(script.Bosses)
local Fish: { Types.FishDef } = require(script.Fish) :: any

local function index<T>(list: { T }, key: string): { [any]: T }
	local map = {}
	for _, row in list do
		map[(row :: any)[key]] = row
	end
	return map
end

local Config = {
	Rarities = Rarities,
	Mutations = Mutations,
	Spots = Spots,
	Rods = Rods,
	Baits = Baits,
	Quests = Quests,
	Products = Products,
	Tuning = Tuning,
	Fish = Fish,
	Battle = Battle,
	Trainers = Trainers,
	Cries = Cries,
	Music = Music,
	Online = Online,
	Bosses = Bosses,

	RarityById = index(Rarities, "id"),
	MutationById = index(Mutations, "id"),
	SpotById = index(Spots, "id"),
	RodByTier = index(Rods, "tier"),
	BaitById = index(Baits, "id"),
	QuestById = index(Quests, "id"),
	FishById = index(Fish, "id"),
	MoveById = index(Battle.Moves, "id"),
	ElementById = index(Battle.Elements, "id"),
	TrainerById = index(Trainers, "id"),
	BossById = index(Bosses, "id"),
}

local SHAPES = {
	koi = true,
	catfish = true,
	puffer = true,
	eel = true,
	angler = true,
	ray = true,
	shark = true,
	orca = true,
	salmon = true,
	salamander = true,
	whale = true,
	sturgeon = true,
}
local PATTERNS = {
	plain = true,
	stripes = true,
	spots = true,
	belly = true,
	patches = true,
	saddle = true,
	gradient = true,
	ribs = true,
	dango = true,
	orca = true,
}
local DECOS = {}
for _, d in
	{
		"horns",
		"antlers",
		"lantern",
		"whiskers",
		"beard",
		"third_eye",
		"big_eye",
		"crown",
		"flame",
		"long_tail",
		"noface",
		"glow",
		"ears",
		"leaf",
		"umbrella",
		"hat",
		"okappa",
		"hair",
		"nose",
		"crest",
		"bell",
		"shimenawa",
		"lotus",
		"kanzashi",
		"coin",
		"wind_bag",
		"drums",
		"fire_wheel",
		"sun_disc",
		"moon",
		"orb",
		"mane",
		"plumes",
		"frills",
		"blush",
		"bighead",
		"cloth",
		"smooth",
	}
do
	DECOS[d] = true
end
local EYES = {
	normal = true,
	cute = true,
	angry = true,
	sleepy = true,
	big = true,
	cat = true,
	glow = true,
	dot = true,
	none = true,
}
local MOUTHS = {
	small = true,
	wide = true,
	o = true,
	smile = true,
	frown = true,
	open = true,
	tongue = true,
	fangs = true,
	grin = true,
	geta = true,
	beak = true,
	jaws = true,
	none = true,
}
local TIMES = { any = true, day = true, night = true, morning = true }
local WEATHERS = { any = true, sunny = true, rain = true, fog = true, thunder = true }

-- 表の整合性チェック。問題のリストを返す(空なら OK)
function Config.Validate(): { string }
	local problems = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end

	local total = 0
	for _, r in Rarities do
		total += r.chance
	end
	if math.abs(total - 1) > 1e-6 then
		bad(("Rarities: chance の合計が 1 ではありません (%f)"):format(total))
	end

	local seen = {}
	for _, f in Fish do
		local where = "Fish[" .. tostring(f.id) .. "]"
		if seen[f.id] then
			bad(where .. ": id が重複しています")
		end
		seen[f.id] = true
		if type(f.id) ~= "string" or not f.id:match("^[%w_]+$") then
			bad(where .. ": id は英数字と _ のみ")
		end
		if not Config.RarityById[f.rarity] then
			bad(where .. ": 不明なレア度 " .. tostring(f.rarity))
		end
		if not Config.SpotById[f.spot] then
			bad(where .. ": 不明な釣り場 " .. tostring(f.spot))
		end
		if not TIMES[f.time] then
			bad(where .. ": 不明な時間 " .. tostring(f.time))
		end
		if not WEATHERS[f.weather] then
			bad(where .. ": 不明な天気 " .. tostring(f.weather))
		end
		if not SHAPES[f.shape] then
			bad(where .. ": 不明な形 " .. tostring(f.shape))
		end
		if not PATTERNS[f.pattern] then
			bad(where .. ": 不明な模様 " .. tostring(f.pattern))
		end
		for _, d in f.deco do
			if not DECOS[d] then
				bad(where .. ": 不明な飾り " .. tostring(d))
			end
		end
		if type(f.kg) ~= "table" or #f.kg ~= 2 or f.kg[1] <= 0 or f.kg[2] < f.kg[1] then
			bad(where .. ": kg は { 最小, 最大 } (0 < 最小 <= 最大)")
		end
		for _, c in { f.c1, f.c2, f.c3 or "#000000" } do
			if type(c) ~= "string" or not c:match("^#%x%x%x%x%x%x$") then
				bad(where .. ": 色は #RRGGBB 形式")
			end
		end
		if f.eyes and not EYES[f.eyes] then
			bad(where .. ": 不明な目 " .. tostring(f.eyes))
		end
		if f.mouth and not MOUTHS[f.mouth] then
			bad(where .. ": 不明な口 " .. tostring(f.mouth))
		end
		if f.body and (#f.body ~= 3 or f.body[1] <= 0 or f.body[2] <= 0 or f.body[3] <= 0) then
			bad(where .. ": body は { 幅, 高さ, 長さ } の正の数")
		end
		if f.tails and (f.tails < 1 or f.tails > 9) then
			bad(where .. ": tails は 1〜9")
		end
		if type(f.ja) ~= "string" or type(f.en) ~= "string" or f.ja == "" or f.en == "" then
			bad(where .. ": 名前(ja/en)が必要です")
		end
		for _, k in { "kindJa", "kindEn" } do
			local v = (f :: any)[k]
			if v ~= nil and (type(v) ~= "string" or v == "") then
				bad(where .. ": " .. k .. " は文字で")
			end
		end
	end

	-- 遊べる釣り場には、並〜神話の各レア度に「いつでも・どんな天気でも」釣れる魚が最低1匹必要
	for _, spot in Spots do
		if spot.available then
			local poolId = spot.fishPool or spot.id
			for _, r in Rarities do
				if r.id ~= "secret" then
					local ok = false
					for _, f in Fish do
						if
							f.spot == poolId
							and f.rarity == r.id
							and f.time == "any"
							and f.weather == "any"
						then
							ok = true
							break
						end
					end
					if not ok then
						bad(
							("Spot[%s]: レア度 %s に time=any, weather=any の魚がいません"):format(
								spot.id,
								r.id
							)
						)
					end
				end
			end
		end
		for _, m in spot.mutations do
			if not Config.MutationById[m] then
				bad(("Spot[%s]: 不明な変異 %s"):format(spot.id, m))
			end
		end
	end

	for _, q in Quests do
		if q.reward.bait and not Config.BaitById[q.reward.bait.id] then
			bad(("Quest[%s]: 不明なエサ %s"):format(q.id, q.reward.bait.id))
		end
		if q.minRarity and not Config.RarityById[q.minRarity] then
			bad(("Quest[%s]: 不明なレア度 %s"):format(q.id, q.minRarity))
		end
	end
	for i, d in Tuning.DailyRewards do
		if d.bait and not Config.BaitById[d.bait.id] then
			bad(("DailyRewards[%d]: 不明なエサ %s"):format(i, d.bait.id))
		end
	end
	if #Rods ~= 10 then
		bad("Rods: 竿は10段階のはず")
	end

	-- 相棒バトル
	for _, f in Fish do
		if not Battle.ElementMoves[f.element] then
			bad(("Fish[%s]: 不明な属性 %s"):format(f.id, tostring(f.element)))
		end
		if not Battle.ShapeStats[f.shape] then
			bad(("Fish[%s]: Battle.ShapeStats に形 %s がありません"):format(f.id, f.shape))
		end
	end
	for _, r in Rarities do
		if not Battle.RarityPower[r.id] or not Battle.FeedXp[r.id] then
			bad("Battle: レア度 " .. r.id .. " の RarityPower / FeedXp がありません")
		end
	end
	local function checkMove(id: string, where: string)
		if not Config.MoveById[id] then
			bad(where .. ": 不明な技 " .. id)
		end
	end
	for shape, id in Battle.ShapeMove do
		checkMove(id, "Battle.ShapeMove." .. shape)
	end
	for el, ids in Battle.ElementMoves do
		for _, id in ids do
			checkMove(id, "Battle.ElementMoves." .. el)
		end
	end
	local seenTrainer = {}
	for _, t in Trainers do
		local where = "Trainer[" .. t.id .. "]"
		if seenTrainer[t.id] then
			bad(where .. ": id が重複しています")
		end
		seenTrainer[t.id] = true
		if #t.team < 1 or #t.team > Battle.TeamSize then
			bad(where .. ": 魚は1〜" .. Battle.TeamSize .. "匹")
		end
		for _, m in t.team do
			if not Config.FishById[m.fish] then
				bad(where .. ": 不明な魚 " .. m.fish)
			end
			if m.level < 1 or m.level > Battle.MaxLevel then
				bad(where .. ": レベルが範囲外")
			end
			if m.mutation and not Config.MutationById[m.mutation] then
				bad(where .. ": 不明な変異 " .. m.mutation)
			end
		end
		if t.reward.bait and not Config.BaitById[t.reward.bait.id] then
			bad(where .. ": 不明なエサ " .. t.reward.bait.id)
		end
		if t.title and not table.find(Tuning.Titles, t.title) then
			bad(where .. ": 称号 " .. t.title .. " が Tuning.Titles にありません")
		end
	end

	-- ボス戦
	local seenBoss = {}
	for _, b in Bosses do
		local where = "Boss[" .. b.id .. "]"
		if seenBoss[b.id] then
			bad(where .. ": id が重複しています")
		end
		seenBoss[b.id] = true
		if not Config.FishById[b.fish] then
			bad(where .. ": 不明な魚 " .. b.fish)
		end
		if b.level < 1 or b.hpMult <= 0 or b.atkMult <= 0 then
			bad(where .. ": レベル・倍率が不正")
		end
		if b.reward.bait and not Config.BaitById[b.reward.bait.id] then
			bad(where .. ": 不明なエサ " .. b.reward.bait.id)
		end
		if b.title and not table.find(Tuning.Titles, b.title) then
			bad(where .. ": 称号 " .. b.title .. " が Tuning.Titles にありません")
		end
	end
	if Online.MaxPlayers < 2 or Online.RaidPartyMax < 1 or Online.RaidPartyMax > Online.MaxPlayers then
		bad("Online: 人数の設定が不正")
	end
	if #Online.Stamps == 0 or #Online.Stamps > 12 then
		bad("Online: スタンプは1〜12個")
	end

	if not Config.FishById[Tuning.Nushi.fishId] then
		bad("Tuning.Nushi.fishId: 不明な魚 " .. tostring(Tuning.Nushi.fishId))
	end

	-- 鳴き声(無い魚は鳴かないだけ。あるものは区間と文字を確かめる)
	-- BGM: 場所の曲・バトルの曲が表にあり、soundId は rbxassetid://<数字>
	for name, t in Music.tracks do
		if type(t.soundId) ~= "string" or not t.soundId:match("^rbxassetid://%d+$") then
			bad("Music: " .. name .. " の soundId は rbxassetid://<数字> の形にしてください")
		end
		if type(t.length) ~= "number" or t.length < 10 then
			bad("Music: " .. name .. " の長さが短すぎる")
		end
	end
	for spotId, name in Music.areaTrack do
		if not Config.SpotById[spotId] then
			bad("Music.areaTrack: 知らない釣り場 " .. spotId)
		end
		if not Music.tracks[name] then
			bad("Music.areaTrack: 知らない曲 " .. name)
		end
	end
	if
		not Music.tracks[Music.battleTrack]
		or not Music.tracks[Music.bossTrack]
		or not Music.tracks.village
	then
		bad("Music: battle・boss・village の曲が必要")
	end
	if type(Cries.soundId) ~= "string" or not Cries.soundId:match("^rbxassetid://%d+$") then
		bad("Cries: soundId は rbxassetid://<数字> の形にしてください")
	end
	local spans = {}
	for id, c in Cries.cries do
		local where = "Cries[" .. id .. "]"
		if not Config.FishById[id] then
			bad(where .. ": 不明な魚")
		end
		if type(c.start) ~= "number" or type(c.length) ~= "number" or c.start < 0 or c.length <= 0 then
			bad(where .. ": start / length が不正")
		elseif c.start + c.length > Cries.length + 1e-3 then
			bad(where .. ": 音のファイルの長さを超えています")
		else
			table.insert(spans, { id = id, a = c.start, b = c.start + c.length })
		end
		for _, lang in { "ja", "en" } do
			local text = (c :: any)[lang]
			if
				type(text) ~= "string"
				or #text == 0
				or utf8.len(text) == nil
				or (utf8.len(text) :: number) > 30
			then
				bad(where .. ": " .. lang .. " の文字は1〜30文字")
			end
		end
	end
	table.sort(spans, function(x, y)
		return x.a < y.a
	end)
	for i = 2, #spans do
		if spans[i].a < spans[i - 1].b then
			bad(
				"Cries: " .. spans[i - 1].id .. " と " .. spans[i].id .. " の区間が重なっています"
			)
		end
	end
	return problems
end

return Config
