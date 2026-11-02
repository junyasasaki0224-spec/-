--!strict
-- 依頼板(毎日3つ)とデイリー報酬。
-- 日付はサーバー時刻から計算し、その日の依頼は全サーバー共通(同じ日なら誰でも同じ3つ)。
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldClock = require(Shared.Lib.WorldClock)
local Roll = require(Shared.Lib.Roll)
local Types = require(Shared.Lib.Types)
local RemoteGuard = require(script.Parent.RemoteGuard)

local QT = Config.Tuning.Quests

local QuestService = {}
local S: any

local function today(): number
	return WorldClock.dayIndex(os.time(), QT.dayOffsetSeconds)
end
QuestService.today = today

-- その日の依頼(決定的に選ぶ)
local function dailyIds(day: number): { string }
	local ids = {}
	local pool = table.clone(Config.Quests)
	local n = 0
	local salt = 0
	while #ids < QT.perDay and #pool > 0 do
		n += 1
		local idx = math.floor(WorldClock.hash01(day * 131 + n * 17 + salt) * #pool) + 1
		local q = table.remove(pool, idx) :: any
		table.insert(ids, q.id)
		salt += 1
	end
	return ids
end
QuestService.dailyIds = dailyIds

local function ensureToday(player: Player): any?
	local data = S.Data.get(player)
	if not data then
		return nil
	end
	local d = today()
	if data.quests.day ~= d then
		data.quests.day = d
		data.quests.list = {}
		data.quests.pendingReroll = 0
		for _, id in dailyIds(d) do
			table.insert(data.quests.list, { id = id, p = 0, done = false, claimed = false })
		end
		S.Data.changed(player)
	end
	return data
end
QuestService.ensureToday = ensureToday

local function progress(player: Player, fn: (q: any) -> number)
	local data = ensureToday(player)
	if not data then
		return
	end
	local changed = false
	for _, entry in data.quests.list do
		if not entry.done then
			local q = Config.QuestById[entry.id]
			if q then
				local add = fn(q)
				if add > 0 then
					entry.p = math.min(q.count, entry.p + add)
					changed = true
					if entry.p >= q.count then
						entry.done = true
						S.notify(player, "notify_quest_done")
					end
				end
			end
		end
	end
	if changed then
		S.Data.changed(player)
	end
end

function QuestService.onCatch(
	player: Player,
	fish: Types.FishDef,
	grams: number,
	mutation: string?,
	cond: Types.Conditions
)
	local order = Config.RarityById[fish.rarity].order
	progress(player, function(q)
		if q.kind == "catch_any" then
			return 1
		elseif q.kind == "catch_rarity" then
			return if order >= Config.RarityById[q.minRarity].order then 1 else 0
		elseif q.kind == "catch_weather" then
			return if cond.weather == q.weather then 1 else 0
		elseif q.kind == "catch_time" then
			return if Roll.timeMatches(q.time, cond.time) then 1 else 0
		elseif q.kind == "catch_shape" then
			return if fish.shape == q.shape and grams >= (q.minWeight or 0) * 1000 then 1 else 0
		elseif q.kind == "catch_mutation" then
			return if mutation then 1 else 0
		end
		return 0
	end)
end

function QuestService.onSell(player: Player, coins: number)
	progress(player, function(q)
		return if q.kind == "sell_coins" then coins else 0
	end)
end

function QuestService.setPendingReroll(player: Player, index: number)
	local data = ensureToday(player)
	if data and RemoteGuard.isInt(index, 1, #data.quests.list) then
		data.quests.pendingReroll = index
	end
end

-- 課金「依頼の入れ替え」が成功した時に呼ばれる
function QuestService.rerollPending(player: Player)
	local data = ensureToday(player)
	if not data then
		return
	end
	local list = data.quests.list
	local idx = data.quests.pendingReroll
	if not list[idx] or list[idx].claimed then
		idx = 0
		for i, e in list do
			if not e.done then
				idx = i
				break
			end
		end
	end
	if idx == 0 then
		idx = 1
	end
	local used = {}
	for _, e in list do
		used[e.id] = true
	end
	local candidates = {}
	for _, q in Config.Quests do
		if not used[q.id] then
			table.insert(candidates, q.id)
		end
	end
	if #candidates == 0 then
		return
	end
	local pick = candidates[math.random(1, #candidates)]
	list[idx] = { id = pick, p = 0, done = false, claimed = false }
	data.quests.pendingReroll = 0
	S.Data.changed(player)
end

local function grantReward(player: Player, data: any, reward: any, kind: string)
	if reward.coins and reward.coins > 0 then
		S.Shop.addCoins(player, reward.coins, kind)
	end
	if reward.bait and Config.BaitById[reward.bait.id] then
		data.bait[reward.bait.id] = (data.bait[reward.bait.id] or 0) + reward.bait.amount
	end
	S.Data.changed(player)
end

local function claimQuest(player: Player, index: any)
	local data = ensureToday(player)
	if not data or not RemoteGuard.isInt(index, 1, #data.quests.list) then
		return
	end
	local entry = data.quests.list[index]
	if not entry.done or entry.claimed then
		return
	end
	local q = Config.QuestById[entry.id]
	if not q then
		return
	end
	entry.claimed = true
	grantReward(player, data, q.reward, "Quest")
	S.Analytics.custom(player, "QuestClaim")
end

-- デイリー報酬
local function checkDaily(player: Player)
	local data = S.Data.get(player)
	if not data then
		return
	end
	local d = today()
	if data.daily.lastDay == d then
		return
	end
	if not data.daily.pending then
		data.daily.streak = if data.daily.lastDay == d - 1 then data.daily.streak + 1 else 1
		data.daily.pending = true
		S.Data.changed(player)
	end
end

local function claimDaily(player: Player)
	local data = S.Data.get(player)
	if not data or not data.daily.pending then
		return
	end
	local rewards = Config.Tuning.DailyRewards
	local reward = rewards[((data.daily.streak - 1) % #rewards) + 1]
	data.daily.pending = false
	data.daily.lastDay = today()
	grantReward(player, data, reward, "Daily")
	S.notify(player, "daily_got", { coins = reward.coins })
end

function QuestService.handleRequest(player: Player, action: string, payload: any): boolean
	if action == "claimQuest" then
		claimQuest(player, payload)
	elseif action == "claimDaily" then
		claimDaily(player)
	else
		return false
	end
	return true
end

function QuestService.init(registry: any)
	S = registry
end

function QuestService.start()
	S.Data.Loaded:Connect(function(player)
		ensureToday(player)
		checkDaily(player)
	end)
	-- 日付が変わった時のため、ときどき確認
	task.spawn(function()
		while true do
			task.wait(60)
			for _, player in game:GetService("Players"):GetPlayers() do
				if S.Data.isLoaded(player) then
					ensureToday(player)
					checkDaily(player)
				end
			end
		end
	end)
end

return QuestService
