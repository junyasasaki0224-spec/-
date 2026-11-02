--!strict
-- 抽選ロジック(純粋関数。乱数は rng() で外から渡すのでテスト可能)。
-- レア度と変異の確率は招き猫と同じ値。運は「特上以上」の確率に掛け算で効き、増えた分だけ「並」が減る。

local Types = require(script.Parent.Types)

type Rng = () -> number

local Roll = {}

-- 運を適用したレア度ごとの確率表を返す
function Roll.rarityTable(rarities: { any }, luck: number): { { id: string, p: number } }
	luck = math.max(1, luck)
	local out = {}
	local boostedSum, fixedSum = 0, 0
	for _, r in rarities do
		if r.luckAffected then
			boostedSum += r.chance * luck
		elseif r.order ~= 1 then
			fixedSum += r.chance
		end
	end
	-- 「並」がマイナスにならないよう、あふれた分は運の効く層を縮める
	local room = math.max(0, 1 - fixedSum)
	local scale = if boostedSum > room then room / boostedSum else 1
	local used = 0
	for _, r in rarities do
		local p
		if r.luckAffected then
			p = r.chance * luck * scale
		elseif r.order ~= 1 then
			p = r.chance
		else
			p = 0 -- 後で埋める
		end
		used += p
		table.insert(out, { id = r.id, p = p })
	end
	for i, r in rarities do
		if r.order == 1 then
			out[i].p = math.max(0, 1 - used)
		end
	end
	return out
end

-- レア度を1つ選ぶ。minOrder を指定するとそれ未満は出ない(確率を詰めて再配分)
function Roll.rarity(rng: Rng, rarities: { any }, luck: number, minOrder: number?): string
	local tbl = Roll.rarityTable(rarities, luck)
	local minO = minOrder or 1
	local total = 0
	for i, row in tbl do
		if rarities[i].order >= minO then
			total += row.p
		end
	end
	if total <= 0 then
		return rarities[#rarities].id
	end
	local x = rng() * total
	-- 珍しい方から判定すると浮動小数の端数で並に寄る問題を避けられる
	for i = #tbl, 1, -1 do
		if rarities[i].order >= minO then
			x -= tbl[i].p
			if x < 0 then
				return tbl[i].id
			end
		end
	end
	for i = 1, #tbl do
		if rarities[i].order >= minO then
			return tbl[i].id
		end
	end
	return tbl[1].id
end

-- 時間帯の判定。morning は day にも含まれる
function Roll.timeMatches(fishTime: string, nowTime: string): boolean
	if fishTime == "any" then
		return true
	end
	if fishTime == nowTime then
		return true
	end
	if fishTime == "day" and nowTime == "morning" then
		return true
	end
	return false
end

function Roll.isEligible(fish: Types.FishDef, poolSpot: string, cond: Types.Conditions): boolean
	if fish.spot ~= poolSpot then
		return false
	end
	if not Roll.timeMatches(fish.time, cond.time) then
		return false
	end
	if fish.weather ~= "any" and fish.weather ~= cond.weather then
		return false
	end
	return true
end

-- 条件に合う魚を選ぶ。そのレア度に候補がなければ1つ下、それもなければ上を探す
function Roll.fish(
	rng: Rng,
	fishList: { Types.FishDef },
	rarities: { any },
	poolSpot: string,
	cond: Types.Conditions,
	rarityId: string
): Types.FishDef?
	local orderOf = {}
	for _, r in rarities do
		orderOf[r.id] = r.order
	end
	local start = orderOf[rarityId] or 1
	local tryOrders = {}
	for o = start, 1, -1 do
		table.insert(tryOrders, o)
	end
	for o = start + 1, #rarities do
		table.insert(tryOrders, o)
	end
	for _, o in tryOrders do
		local candidates = {}
		for _, f in fishList do
			if orderOf[f.rarity] == o and Roll.isEligible(f, poolSpot, cond) then
				table.insert(candidates, f)
			end
		end
		if #candidates > 0 then
			-- 条件つき(時間・天気限定)の魚は、条件が合った時に出やすくする
			local weights, total = {}, 0
			for i, f in candidates do
				local w = 1
				if f.time ~= "any" then
					w += 1
				end
				if f.weather ~= "any" then
					w += 1.5
				end
				weights[i] = w
				total += w
			end
			local x = rng() * total
			for i, f in candidates do
				x -= weights[i]
				if x < 0 then
					return f
				end
			end
			return candidates[#candidates]
		end
	end
	return nil
end

-- 変異の抽選。珍しい順に判定し最初に当たったものを返す
function Roll.mutation(rng: Rng, mutations: { any }, spotMutations: { string }): string?
	local allowed = {}
	for _, id in spotMutations do
		allowed[id] = true
	end
	local list = {}
	for _, m in mutations do
		if m.global or allowed[m.id] then
			table.insert(list, m)
		end
	end
	table.sort(list, function(a, b)
		return a.chance < b.chance
	end)
	for _, m in list do
		if rng() < m.chance then
			return m.id
		end
	end
	return nil
end

-- 重さ(グラム整数)を抽選。skew > 1 で軽い魚が多くなる
function Roll.grams(rng: Rng, fish: Types.FishDef, skew: number): number
	local t = rng() ^ skew
	local kg = fish.kg[1] + (fish.kg[2] - fish.kg[1]) * t
	return math.max(1, math.floor(kg * 1000 + 0.5))
end

-- アタリまでの秒数
function Roll.biteSeconds(rng: Rng, minS: number, maxS: number, baitMult: number): number
	return (minS + (maxS - minS) * rng()) * baitMult
end

-- 運の合計(倍率)。加算ボーナス → 掛け算ブースト の順に計算
export type LuckInput = {
	rodLuck: number,
	baitLuck: number,
	power: number, -- 0..1 投げの強さ
	distanceBonus: number,
	multipliers: { number },
	maxLuck: number,
}
function Roll.luck(input: LuckInput): number
	local power = math.clamp(input.power, 0, 1)
	local additive = 1 + input.rodLuck + input.baitLuck + input.distanceBonus * power
	local mult = 1
	for _, m in input.multipliers do
		mult *= m
	end
	return math.clamp(additive * mult, 1, input.maxLuck)
end

return Roll
