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

	RarityById = index(Rarities, "id"),
	MutationById = index(Mutations, "id"),
	SpotById = index(Spots, "id"),
	RodByTier = index(Rods, "tier"),
	BaitById = index(Baits, "id"),
	QuestById = index(Quests, "id"),
	FishById = index(Fish, "id"),
}

local SHAPES = { koi = true, catfish = true, puffer = true, eel = true, angler = true, ray = true }
local PATTERNS = { plain = true, stripes = true, spots = true, belly = true }
local DECOS = {
	horns = true,
	lantern = true,
	whiskers = true,
	third_eye = true,
	big_eye = true,
	crown = true,
	flame = true,
	long_tail = true,
	noface = true,
	glow = true,
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
		for _, c in { f.c1, f.c2 } do
			if type(c) ~= "string" or not c:match("^#%x%x%x%x%x%x$") then
				bad(where .. ": 色は #RRGGBB 形式")
			end
		end
		if type(f.ja) ~= "string" or type(f.en) ~= "string" or f.ja == "" or f.en == "" then
			bad(where .. ": 名前(ja/en)が必要です")
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
	return problems
end

return Config
