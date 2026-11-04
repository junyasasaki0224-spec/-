--!strict
-- 百鬼の祠(ガチャ)の抽選。乱数は外から渡す(テストできるように Roblox のサービスは使わない)。
-- 天井: ★4以上が (Pity.star4 - 1) 回続けて出なければ次は必ず★4以上、★5が (Pity.star5 - 1) 回出なければ次は必ず★5。
local Gacha = {}

export type State = { pity4: number, pity5: number } -- 前の★4以上・★5から何回祈ったか
export type Result = {
	star: number,
	kind: string, -- fish / coins / bait / luck
	fishId: string?,
	grams: number?,
	amount: number?,
	id: string?,
	minutes: number?,
}

local function pickWeighted(rng: () -> number, list: { any }): any
	local total = 0
	for _, e in list do
		total += e.weight
	end
	local r = rng() * total
	for _, e in list do
		r -= e.weight
		if r < 0 then
			return e
		end
	end
	return list[#list]
end

-- 星を決める(天井を含む)。state はこの関数では変えない
function Gacha.rollStar(rng: () -> number, cfg: any, state: State): number
	if state.pity5 + 1 >= cfg.Pity.star5 then
		return 5
	end
	local star = pickWeighted(rng, cfg.Stars).star
	if star < 4 and state.pity4 + 1 >= cfg.Pity.star4 then
		-- ★4以上の天井: ★4と★5の重みの割合で選ぶ
		local top = {}
		for _, s in cfg.Stars do
			if s.star >= 4 then
				table.insert(top, s)
			end
		end
		star = pickWeighted(rng, top).star
	end
	return star
end

-- 天井の数え方を進める
function Gacha.advance(state: State, star: number): State
	return {
		pity4 = if star >= 4 then 0 else state.pity4 + 1,
		pity5 = if star >= 5 then 0 else state.pity5 + 1,
	}
end

-- 1回祈る。fishById は Config.FishById(重さの範囲を使う)。戻り値: 授かった物, 次の state
function Gacha.pull(
	rng: () -> number,
	cfg: any,
	state: State,
	rodTier: number,
	fishById: { [string]: any }
): (Result, State)
	local star = Gacha.rollStar(rng, cfg, state)
	local result: Result
	local ids = cfg.Fish[star]
	if ids and #ids > 0 then
		local id = ids[math.min(#ids, math.floor(rng() * #ids) + 1)]
		local def = fishById[id]
		local lo, hi = def.kg[1], def.kg[2]
		-- 重さ: 軽めが多く、たまに大物(釣りと同じ感じ)
		local kg = lo + (hi - lo) * rng() ^ 2
		result = { star = star, kind = "fish", fishId = id, grams = math.max(1, math.floor(kg * 1000)) }
	else
		local it = pickWeighted(rng, cfg.Items[star])
		result = { star = star, kind = it.kind, id = it.id, minutes = it.minutes, amount = it.amount }
		if it.kind == "coins" then
			result.amount = cfg.coinsFor(it.amount, rodTier)
		end
	end
	return result, Gacha.advance(state, star)
end

-- n 回の支払い: 祈願札を先に使い、足りない分を勾玉で払う。払えなければ nil
function Gacha.cost(n: number, tickets: number, magatama: number, price: number): (number?, number?)
	local useTickets = math.min(n, math.max(0, tickets))
	local need = (n - useTickets) * price
	if need > magatama then
		return nil, nil
	end
	return useTickets, need
end

-- 星ごとの確率(%)。画面に出す表
function Gacha.rates(cfg: any): { { star: number, percent: number } }
	local total = 0
	for _, s in cfg.Stars do
		total += s.weight
	end
	local out = {}
	for _, s in cfg.Stars do
		table.insert(out, { star = s.star, percent = s.weight / total * 100 })
	end
	return out
end

return Gacha
