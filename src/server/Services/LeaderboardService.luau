--!strict
-- ランキング(全世界: OrderedDataStore / このサーバー: 参加中のプレイヤー)。
--  * 総釣果 と「今日の大物」(毎日変わる1種類の最重量)の2つ。
--  * 保存するのは UserId と数値だけ。表示名は Roblox の公開ユーザー名を読み込み時に取得する。
--  * 書き込みは間引いて DataStore の制限を守る。
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local WorldClock = require(Shared.Lib.WorldClock)
local Types = require(Shared.Lib.Types)
local RemoteGuard = require(script.Parent.RemoteGuard)

local LT = Config.Tuning.Leaderboard

local LeaderboardService = {}
local S: any

local function getStore(name: string): OrderedDataStore?
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	return if ok then store else nil
end

local totalStore = getStore("TotalCaught_v1")
local heavyStores: { [string]: OrderedDataStore } = {}
local function heavyStore(fishId: string): OrderedDataStore?
	if not heavyStores[fishId] then
		local s = getStore("Heaviest_v1_" .. fishId)
		if s then
			heavyStores[fishId] = s
		end
	end
	return heavyStores[fishId]
end

-- 今日の大物(秘伝以外・遊べる釣り場の魚から決定的に選ぶ)
function LeaderboardService.featuredFish(): string
	local pool = {}
	for _, f in Config.Fish do
		local spot = Config.SpotById[f.spot]
		if f.rarity ~= "secret" and spot and spot.available then
			table.insert(pool, f.id)
		end
	end
	local day = S.Quest.today()
	local idx = math.floor(WorldClock.hash01(day * 977 + 3) * #pool) + 1
	return pool[idx]
end

local nameCache: { [number]: string } = {}
local function nameOf(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		nameCache[userId] = p.Name
		return p.Name
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else "???"
	nameCache[userId] = result
	return result
end

local function readTop(store: OrderedDataStore?): { { name: string, value: number } }
	if not store then
		return {}
	end
	local ok, page = pcall(function()
		return store:GetSortedAsync(false, LT.topCount):GetCurrentPage()
	end)
	if not ok then
		return {}
	end
	local out = {}
	for _, entry in page :: any do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(out, { name = nameOf(userId), value = entry.value })
		end
	end
	return out
end

local cache = { featured = "", world = { total = {}, heaviest = {} }, at = 0 }

local function refreshWorld()
	local featured = LeaderboardService.featuredFish()
	cache.featured = featured
	cache.world.total = readTop(totalStore)
	cache.world.heaviest = readTop(heavyStore(featured))
	cache.at = os.time()
end

local function serverBoard(): any
	local featured = cache.featured
	local total, heaviest = {}, {}
	for _, p in Players:GetPlayers() do
		local data = S.Data.get(p)
		if data then
			table.insert(total, { name = p.Name, value = data.stats.caught })
			local entry = data.codex[featured]
			if entry and entry.best > 0 then
				table.insert(heaviest, { name = p.Name, value = entry.best })
			end
		end
	end
	local function sortDesc(a, b)
		return a.value > b.value
	end
	table.sort(total, sortDesc)
	table.sort(heaviest, sortDesc)
	return { total = total, heaviest = heaviest }
end

-- 書き込みの間引き
local pendingHeavy: { [Player]: { fishId: string, grams: number } } = {}
local lastTotalWrite: { [Player]: number } = {}

function LeaderboardService.onCatch(player: Player, fish: Types.FishDef, grams: number)
	if fish.id == cache.featured then
		local cur = pendingHeavy[player]
		if not cur or cur.fishId ~= fish.id or grams > cur.grams then
			pendingHeavy[player] = { fishId = fish.id, grams = grams }
		end
	end
end

local function flush(player: Player, force: boolean)
	local now = os.clock()
	local data = S.Data.get(player)
	if not data then
		return
	end
	local userKey = tostring(player.UserId)
	if force or now - (lastTotalWrite[player] or 0) >= LT.writeMinIntervalSeconds * 4 then
		lastTotalWrite[player] = now
		local caught = data.stats.caught
		if totalStore and caught > 0 then
			pcall(function()
				(totalStore :: OrderedDataStore):SetAsync(userKey, caught)
			end)
		end
	end
	local h = pendingHeavy[player]
	if h then
		pendingHeavy[player] = nil
		local store = heavyStore(h.fishId)
		if store then
			pcall(function()
				store:UpdateAsync(userKey, function(old)
					if type(old) == "number" and old >= h.grams then
						return nil
					end
					return h.grams
				end)
			end)
		end
	end
end

-- 個人データ削除(DataService.eraseUser から呼ばれる)
function LeaderboardService.eraseUser(userId: number)
	local key = tostring(userId)
	if totalStore then
		pcall(function()
			(totalStore :: OrderedDataStore):RemoveAsync(key)
		end)
	end
	for _, f in Config.Fish do
		local store = heavyStore(f.id)
		if store then
			pcall(function()
				store:RemoveAsync(key)
			end)
		end
	end
end

local function setupLeaderstats(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local fish = Instance.new("IntValue")
	fish.Name = "Fish"
	fish.Parent = ls
	local coins = Instance.new("IntValue")
	coins.Name = "Koban"
	coins.Parent = ls
	ls.Parent = player
end

function LeaderboardService.init(registry: any)
	S = registry
end

function LeaderboardService.start()
	Players.PlayerAdded:Connect(setupLeaderstats)
	for _, p in Players:GetPlayers() do
		setupLeaderstats(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		flush(player, true)
		pendingHeavy[player] = nil
		lastTotalWrite[player] = nil
	end)

	Remotes.func("Query").OnServerInvoke = function(player: Player, what: any)
		if not RemoteGuard.allow(player, "Query", 0.5, 3) then
			return nil
		end
		if what == "leaderboard" then
			return { featured = cache.featured, world = cache.world, server = serverBoard() }
		end
		return nil
	end

	task.spawn(function()
		while true do
			pcall(refreshWorld)
			task.wait(LT.refreshSeconds)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(LT.writeMinIntervalSeconds)
			for _, p in Players:GetPlayers() do
				task.spawn(flush, p, false)
			end
		end
	end)
	-- leaderstats(プレイヤー一覧の数字)
	task.spawn(function()
		while true do
			task.wait(2)
			for _, p in Players:GetPlayers() do
				local data = S.Data.get(p)
				local ls = p:FindFirstChild("leaderstats")
				if data and ls then
					(ls:FindFirstChild("Fish") :: IntValue).Value = data.stats.caught;
					(ls:FindFirstChild("Koban") :: IntValue).Value = math.min(data.coins, 2 ^ 53)
				end
			end
		end
	end)
end

return LeaderboardService
