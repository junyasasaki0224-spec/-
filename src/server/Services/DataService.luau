--!strict
-- プレイヤーデータの保存と読み込み。
--  * 保存するのは「ゲームの進行データ」だけ。キーは UserId のみで、名前・チャット・端末情報などの
--    個人情報は一切保存しない。
--  * セッションロック: 同じプレイヤーが別サーバーへ素早く移動しても、古いサーバーの保存で
--    新しい進行が上書きされないようにする(データ消失・増殖バグの防止)。
--  * UpdateAsync に UserId を渡して、Roblox の「データ削除リクエスト(忘れられる権利)」の対象として
--    紐付ける。削除依頼が来たら DataService.eraseUser(userId) を Studio のコマンドバーで実行する。
--  * Studio で API アクセスが無効なら、保存しない一時データで遊べる。

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)

local T = Config.Tuning.Data
local SCHEMA_VERSION = 1

local DataService = {}

export type Profile = {
	data: any,
	userId: number,
	temporary: boolean,
	lockLost: boolean,
	dirty: boolean,
	saving: boolean,
	lastSave: number,
}

local profiles: { [Player]: Profile } = {}
local loadedSignal = Instance.new("BindableEvent")
DataService.Loaded = loadedSignal.Event -- (player)

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(T.storeName)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable: " .. tostring(result))
	end
end

-- 新規プレイヤーのデータ
local function template(): any
	return {
		v = SCHEMA_VERSION,
		coins = 0,
		rodTier = 1,
		bait = {},
		equippedBait = "",
		spots = { swamp = true, nushi_lake = true },
		creel = {},
		tank = {},
		codex = {},
		codexRewards = {},
		quests = { day = -1, list = {}, pendingReroll = 0 },
		daily = { lastDay = -1, streak = 0, pending = false },
		stats = { caught = 0, earned = 0, nushi = 0 },
		titles = {},
		activeTitle = "",
		boosts = { luckUntil = 0, adLuckUntil = 0 },
		settings = { autoSell = 0, lang = "" },
		tutorial = 0,
		firstCatch = false,
		uidCounter = 0,
		purchases = {},
	}
end

-- 足りない項目を補う(データの形を変えた時に古いデータを壊さない)
local function reconcile(data: any, tmpl: any)
	for k, v in tmpl do
		if data[k] == nil then
			data[k] = if type(v) == "table" then table.clone(v) else v
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil and #v == 0 then
			reconcile(data[k], v)
		end
	end
end

local function migrate(data: any)
	-- 将来のデータ移行はここに書く: if data.v < 2 then ... data.v = 2 end
	data.v = SCHEMA_VERSION
end

local function keyFor(userId: number): string
	return "u_" .. userId
end

local function isLockActive(lock: any): boolean
	return type(lock) == "table"
		and lock.job ~= game.JobId
		and (os.time() - (lock.t or 0)) < T.sessionLockStaleSeconds
end

local function loadFromStore(player: Player): (boolean, any)
	local s = store
	if not s then
		return false, nil
	end
	local key = keyFor(player.UserId)
	local userIds = { player.UserId }
	-- Studio で API アクセスが無効だと毎回失敗するので、待たずに一時データへ切り替える
	local retries = if RunService:IsStudio() then 1 else T.loadRetries
	for attempt = 1, retries do
		local blocked = false
		local loaded = nil
		local steal = attempt == retries
		local ok, err = pcall(function()
			s:UpdateAsync(key, function(old)
				local data = old or template()
				if isLockActive(data._lock) and not steal then
					blocked = true
					return nil -- 書き込みをキャンセル
				end
				data._lock = { job = game.JobId, t = os.time() }
				loaded = data
				return data, userIds
			end)
		end)
		if ok and loaded then
			return true, loaded
		end
		if not ok then
			warn(
				("[DataService] load attempt %d failed for %d: %s"):format(
					attempt,
					player.UserId,
					tostring(err)
				)
			)
		end
		if player.Parent ~= Players or attempt == retries then
			return false, nil
		end
		task.wait(if blocked then 5 else 2 ^ attempt)
	end
	return false, nil
end

-- 送信用のデータ(内部情報や購入履歴は送らない)
local HIDDEN = { _lock = true, purchases = true, uidCounter = true }
local function snapshot(data: any): any
	local out = {}
	for k, v in data do
		if not HIDDEN[k] then
			out[k] = v
		end
	end
	return out
end

local profileRemote: RemoteEvent? = nil
local pendingReplicate: { [Player]: boolean } = {}

function DataService.replicate(player: Player)
	if pendingReplicate[player] then
		return
	end
	pendingReplicate[player] = true
	task.defer(function()
		pendingReplicate[player] = nil
		local p = profiles[player]
		if p and player.Parent == Players and profileRemote then
			profileRemote:FireClient(player, snapshot(p.data))
		end
	end)
end

function DataService.get(player: Player): any?
	local p = profiles[player]
	return if p then p.data else nil
end

function DataService.getProfile(player: Player): Profile?
	return profiles[player]
end

function DataService.isLoaded(player: Player): boolean
	return profiles[player] ~= nil
end

-- データを変えたら必ず呼ぶ(保存予約 + クライアントへ反映)
function DataService.changed(player: Player)
	local p = profiles[player]
	if p then
		p.dirty = true
		DataService.replicate(player)
	end
end

function DataService.nextUid(player: Player): string
	local data = DataService.get(player)
	assert(data, "profile not loaded")
	data.uidCounter += 1
	return ("%x"):format(data.uidCounter)
end

local function save(player: Player, release: boolean): boolean
	local p = profiles[player]
	if not p or p.temporary or p.lockLost then
		return p ~= nil and p.temporary
	end
	local s = store
	if not s then
		return false
	end
	while p.saving do
		task.wait(0.1)
	end
	p.saving = true
	local data = p.data
	local userIds = { p.userId }
	local lost = false
	local ok, err = pcall(function()
		s:UpdateAsync(keyFor(p.userId), function(old)
			if old and type(old._lock) == "table" and old._lock.job ~= game.JobId then
				lost = true -- 別のサーバーがロックを持っている → 上書きしない
				return nil
			end
			data._lock = if release then nil else { job = game.JobId, t = os.time() }
			return data, userIds
		end)
	end)
	p.saving = false
	if lost then
		p.lockLost = true
		warn(("[DataService] session lock lost for %d; stop saving"):format(p.userId))
		if player.Parent == Players then
			player:Kick(
				"Your data was opened in another server. Please rejoin. / 別のサーバーでデータが開かれました。再参加してください。"
			)
		end
		return false
	end
	if ok then
		p.dirty = false
		p.lastSave = os.clock()
	else
		warn(("[DataService] save failed for %d: %s"):format(p.userId, tostring(err)))
	end
	return ok
end

-- 課金などで「今すぐ保存」が必要な時
function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

local function onPlayerAdded(player: Player)
	local ok, data = loadFromStore(player)
	if player.Parent ~= Players then
		if ok then
			-- 読み込み中に抜けた: ロックだけ解放
			profiles[player] = {
				data = data,
				userId = player.UserId,
				temporary = false,
				lockLost = false,
				dirty = false,
				saving = false,
				lastSave = 0,
			}
			save(player, true)
			profiles[player] = nil
		end
		return
	end
	local temporary = false
	if not ok then
		if RunService:IsStudio() then
			warn(
				"[DataService] Studio: using a temporary (unsaved) profile. Enable API access to test saving."
			)
			data = template()
			temporary = true
		else
			player:Kick(
				"Failed to load your data. Please rejoin. / データの読み込みに失敗しました。再参加してください。"
			)
			return
		end
	end
	reconcile(data, template())
	migrate(data)
	profiles[player] = {
		data = data,
		userId = player.UserId,
		temporary = temporary,
		lockLost = false,
		dirty = false,
		saving = false,
		lastSave = os.clock(),
	}
	loadedSignal:Fire(player)
	DataService.replicate(player)
end

local function onPlayerRemoving(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	save(player, true)
	profiles[player] = nil
	pendingReplicate[player] = nil
end

-- 個人データの削除依頼への対応(Studio のコマンドバーから実行):
--   require(game.ServerScriptService.Server.Services.DataService).eraseUser(12345678)
function DataService.eraseUser(userId: number): boolean
	assert(type(userId) == "number" and userId > 0, "userId must be a positive number")
	local s = store
	if not s then
		return false
	end
	local ok, err = pcall(function()
		s:RemoveAsync(keyFor(userId))
	end)
	if not ok then
		warn("[DataService] erase failed: " .. tostring(err))
		return false
	end
	-- ランキング側の記録も消す
	local LeaderboardService = require(script.Parent.LeaderboardService) :: any
	LeaderboardService.eraseUser(userId)
	print(("[DataService] erased data for user %d"):format(userId))
	return true
end

function DataService.init()
	profileRemote = Remotes.event("Profile")
end

function DataService.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	-- 自動保存
	task.spawn(function()
		while true do
			task.wait(T.autosaveSeconds)
			for player, p in profiles do
				if not p.temporary then
					task.spawn(save, player, false)
				end
				task.wait(0.2) -- DataStore の予算を均等に使う
			end
		end
	end)

	game:BindToClose(function()
		local threads = 0
		for player in profiles do
			threads += 1
			task.spawn(function()
				save(player, true)
				threads -= 1
			end)
		end
		local deadline = os.clock() + 25
		while threads > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
