--!strict
-- 百鬼の祠(ガチャ)。勾玉と祈願札をためて、祈ると限定の魚や道具を授かる。
--  * 何が出るかはサーバーが決める(Lib/Gacha の抽選)。クライアントから来るのは「何回祈るか」(1 か 10)だけ
--  * 払う → 抽選 → 渡す → 天井を進める、を1つの処理で行う(途中で失敗して二重取りにならないように)
--  * 授かった限定の魚は魚籠に入り、最初からお気に入り(売れない・まとめて売るにも入らない)。魚籠がいっぱいでも入れる
--  * ★5は、サーバーの全員に知らせる
--  * 勾玉は Robux でも買える(MonetizationService)。確率はいつも画面に出す
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local Lib = require(Shared.Lib.Gacha)
local RemoteGuard = require(script.Parent.RemoteGuard)

local G = Config.Gacha
local GachaService = {}
local S: any
local resultRemote: RemoteEvent

-- テストで乱数を差し替えられるように
local rng: () -> number = function()
	return math.random()
end
function GachaService.setRng(fn: () -> number)
	rng = fn
end

-- 勾玉・祈願札を渡す(reason は分析用)
function GachaService.give(player: Player, magatama: number, tickets: number?, reason: string)
	local data = S.Data.get(player)
	if not data then
		return
	end
	local m = math.max(0, math.floor(magatama))
	local t = math.max(0, math.floor(tickets or 0))
	if m == 0 and t == 0 then
		return
	end
	data.gacha.magatama += m
	data.gacha.tickets += t
	S.Data.changed(player)
	S.Analytics.custom(player, "Magatama_" .. reason, m)
	S.notify(player, "notify_magatama", { n = m, t = t })
end

local function grant(player: Player, data: any, r: Lib.Result)
	if r.kind == "fish" then
		local def = Config.FishById[r.fishId :: string]
		local fish = {
			uid = S.Data.nextUid(player),
			fishId = def.id,
			grams = r.grams,
			spot = "shrine",
			at = os.time(),
			locked = true, -- 限定の魚は最初からお気に入り(うっかり売らない)
		}
		table.insert(data.creel, fish)
		-- 図鑑(祠の欄)
		local entry = data.codex[def.id]
		if not entry then
			entry = { n = 0, best = 0, muts = {} }
			data.codex[def.id] = entry
		end
		entry.n += 1
		entry.best = math.max(entry.best, r.grams or 0)
		return fish.uid
	elseif r.kind == "coins" then
		S.Shop.addCoins(player, r.amount or 0, "Gacha")
	elseif r.kind == "bait" and r.id and Config.BaitById[r.id] then
		data.bait[r.id] = (data.bait[r.id] or 0) + (r.amount or 0)
	elseif r.kind == "luck" then
		local now = os.time()
		data.boosts.luckUntil = math.max(now, data.boosts.luckUntil) + (r.minutes or 0) * 60
	end
	return nil
end

-- n 回祈る(n は 1 か 10)
local function pull(player: Player, n: any)
	if not RemoteGuard.isInt(n, 1, G.MaxPulls) or (n ~= 1 and n ~= G.MaxPulls) then
		return
	end
	local data = S.Data.get(player)
	if not data then
		return
	end
	local g = data.gacha
	local useTickets, useMagatama = Lib.cost(n, g.tickets, g.magatama, G.Cost)
	if not useTickets or not useMagatama then
		S.notify(player, "gacha_not_enough", {})
		return
	end
	g.tickets -= useTickets
	g.magatama -= useMagatama
	local state = { pity4 = g.pity4, pity5 = g.pity5 }
	local results = {}
	local best = 0
	for _ = 1, n do
		local r
		r, state = Lib.pull(rng, G, state, data.rodTier, Config.FishById)
		local uid = grant(player, data, r)
		table.insert(results, {
			star = r.star,
			kind = r.kind,
			fishId = r.fishId,
			grams = r.grams,
			amount = r.amount,
			id = r.id,
			minutes = r.minutes,
			uid = uid,
		})
		best = math.max(best, r.star)
		if r.kind == "fish" and r.star >= G.AnnounceStar then
			S.announce("gacha_announce", { name = player.DisplayName, fishId = r.fishId })
		end
	end
	g.pity4, g.pity5 = state.pity4, state.pity5
	g.pulls += n
	S.Data.changed(player)
	S.Analytics.custom(player, "GachaPull" .. n, best)
	resultRemote:FireClient(player, { results = results, pity4 = g.pity4, pity5 = g.pity5 })
end

function GachaService.handleRequest(player: Player, action: string, payload: any): boolean
	if action == "gachaPull" then
		pull(player, payload)
		return true
	end
	return false
end

function GachaService.init(registry: any)
	S = registry
end

function GachaService.start()
	resultRemote = Remotes.event("GachaResult")
end

return GachaService
