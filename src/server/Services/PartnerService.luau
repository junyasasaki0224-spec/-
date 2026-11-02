--!strict
-- 相棒(釣った魚を育てて戦わせる)。
--   addPartner    : 魚籠の魚を相棒にする(最大 Battle.MaxPartners 匹)
--   removePartner : 相棒を魚籠へ戻す(レベルは残る)
--   feed          : 魚籠の魚を相棒に食べさせて経験値にする(食べた魚は無くなる)
--   setTeam       : 戦いに出す順番(最大 Battle.TeamSize 匹)
--   toggleLock    : お気に入り(売れない・食べさせられない)
-- 経験値・レベルの計算はすべてサーバー。クライアントは「どれに何をしたいか」を送るだけ。
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local BattleLib = require(Shared.Lib.Battle)

local B = Config.Battle

local PartnerService = {}
local S: any

local function findIn(list: { any }, uid: any): number?
	if type(uid) ~= "string" or #uid > 16 then
		return nil
	end
	for i, f in list do
		if f.uid == uid then
			return i
		end
	end
	return nil
end
PartnerService.findIn = findIn

local function removeFromTeam(data: any, uid: string)
	local i = table.find(data.team, uid)
	if i then
		table.remove(data.team, i)
	end
end

-- 経験値を与える。上がったレベル数を返す(バトルの報酬でも使う)
function PartnerService.giveXp(player: Player, partner: any, xp: number): number
	local def = Config.FishById[partner.fishId]
	if not def or xp <= 0 then
		return 0
	end
	local level, rest, gained = BattleLib.addXp(partner.level, partner.xp, xp, def.rarity)
	partner.level = level
	partner.xp = rest
	if gained > 0 then
		S.notify(player, "partner_level_up", { fishId = partner.fishId, level = level })
	end
	return gained
end

local handlers: { [string]: (Player, any, any) -> () } = {}

handlers.addPartner = function(player, data, uid)
	local i = findIn(data.creel, uid)
	if not i then
		return
	end
	if #data.partners >= B.MaxPartners then
		S.notify(player, "partner_full")
		return
	end
	local fish = table.remove(data.creel, i)
	-- 一度育てた魚はレベルを覚えている
	fish.level = fish.level or 1
	fish.xp = fish.xp or 0
	table.insert(data.partners, fish)
	if #data.team < B.TeamSize then
		table.insert(data.team, fish.uid)
	end
	S.Data.changed(player)
	S.Analytics.custom(player, "PartnerAdd")
end

handlers.removePartner = function(player, data, uid)
	local i = findIn(data.partners, uid)
	if not i then
		return
	end
	if #data.creel >= S.Monetization.creelCapacity(player) then
		S.notify(player, "fish_creel_full")
		return
	end
	local fish = table.remove(data.partners, i)
	-- レベルは保存しておく(もう一度相棒にした時のため、魚の情報として残す)
	table.insert(data.creel, fish)
	removeFromTeam(data, fish.uid)
	S.Data.changed(player)
end

handlers.feed = function(player, data, payload)
	if type(payload) ~= "table" then
		return
	end
	local pi = findIn(data.partners, payload.partner)
	local fi = findIn(data.creel, payload.food)
	if not pi or not fi then
		return
	end
	local partner = data.partners[pi]
	local food = data.creel[fi]
	if food.locked then
		S.notify(player, "fish_locked")
		return
	end
	if partner.level >= B.MaxLevel then
		S.notify(player, "partner_max_level")
		return
	end
	local partnerDef = Config.FishById[partner.fishId]
	local foodDef = Config.FishById[food.fishId]
	if not partnerDef or not foodDef then
		return
	end
	table.remove(data.creel, fi)
	local xp = BattleLib.feedXp(foodDef, food.grams, partnerDef)
	PartnerService.giveXp(player, partner, xp)
	S.Quest.onFeed(player)
	S.Data.changed(player)
	S.notify(player, "partner_fed", { fishId = partner.fishId, xp = xp })
end

handlers.setTeam = function(player, data, payload)
	if type(payload) ~= "table" or #payload > B.TeamSize then
		return
	end
	local team = {}
	for _, uid in payload do
		if not findIn(data.partners, uid) or table.find(team, uid) then
			return
		end
		table.insert(team, uid)
	end
	data.team = team
	S.Data.changed(player)
end

handlers.toggleLock = function(player, data, uid)
	for _, list in { data.creel, data.tank, data.partners } do
		local i = findIn(list, uid)
		if i then
			list[i].locked = if list[i].locked then nil else true
			S.Data.changed(player)
			return
		end
	end
end

function PartnerService.handleRequest(player: Player, action: string, payload: any): boolean
	local h = handlers[action]
	if not h then
		return false
	end
	local data = S.Data.get(player)
	if not data then
		return true
	end
	-- 戦っている間は相棒をいじれない
	if S.Battle.inBattle(player) and action ~= "toggleLock" then
		return true
	end
	h(player, data, payload)
	return true
end

-- 古いデータや壊れたデータの掃除(チームに存在しない相棒が残らないように)
local function sanitize(player: Player)
	local data = S.Data.get(player)
	if not data then
		return
	end
	local team = {}
	for _, uid in data.team do
		if findIn(data.partners, uid) and not table.find(team, uid) and #team < B.TeamSize then
			table.insert(team, uid)
		end
	end
	data.team = team
end

function PartnerService.init(registry: any)
	S = registry
end

function PartnerService.start()
	S.Data.Loaded:Connect(sanitize)
end

return PartnerService
