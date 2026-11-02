--!strict
-- ぬし釣り: 1時間に1回、村の「ぬしの湖」に巨大なぬしが現れ、5分間サーバー全員で引き上げる。
-- 不正対策: クライアントは「枠の中にいた秒数」を報告するだけ。サーバーは
--   * 湖の近くにいるか
--   * 前回の報告からの経過時間を超えていないか(1秒あたりの上限)
-- を確認して貢献度に加算する。どれだけ改造しても「完璧に操作した人」以上にはならない。
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local WorldClock = require(Shared.Lib.WorldClock)
local FishBuilder = require(Shared.Lib.FishBuilder)
local RemoteGuard = require(script.Parent.RemoteGuard)

local NT = Config.Tuning.Nushi
local LAKE = "nushi_lake"

local NushiService = {}
local S: any

type Participant = { contribution: number, lastReport: number }

local event = {
	active = false,
	cycle = -1,
	progress = 0,
	required = NT.baseRequired,
	endsAt = 0,
	participants = {} :: { [Player]: Participant },
	model = nil :: Model?,
	finished = false,
}

local stateRemote: RemoteEvent

local function lakeCenter(): Vector3
	return S.Fishing.waterCenter(Config.SpotById[LAKE])
end

local function nearLake(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local c = lakeCenter()
	local d = Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z).Magnitude
	return d <= NT.joinRadius
end

local function participantCount(): number
	local n = 0
	for p in event.participants do
		if p.Parent == Players then
			n += 1
		end
	end
	return n
end

local function broadcast()
	local remaining = math.max(0, event.endsAt - workspace:GetServerTimeNow())
	for _, p in Players:GetPlayers() do
		local part = event.participants[p]
		stateRemote:FireClient(p, {
			active = event.active and not event.finished,
			progress = event.progress,
			required = event.required,
			remaining = remaining,
			participants = participantCount(),
			mine = if part then part.contribution else 0,
		})
	end
end

local function spawnModel()
	local def = Config.FishById["numa_mizuchi"] or Config.Fish[1]
	local model = FishBuilder.build(def, { scale = 4.5, anchored = true })
	model.Name = "Nushi"
	local c = lakeCenter()
	model:PivotTo(CFrame.new(c + Vector3.new(0, 1.5, 0)))
	CollectionService:AddTag(model, "Nushi")
	model.Parent = workspace
	event.model = model
end

local function despawn()
	if event.model then
		event.model:Destroy()
		event.model = nil
	end
end

local function finish(success: boolean)
	if event.finished then
		return
	end
	event.finished = true
	if success then
		S.announce("nushi_success", {})
		local ranked = {}
		for p, part in event.participants do
			if p.Parent == Players and part.contribution >= NT.minContribution then
				table.insert(ranked, { player = p, c = part.contribution })
			end
		end
		table.sort(ranked, function(a, b)
			return a.c > b.c
		end)
		local minOrder = (Config.RarityById[NT.rewardMinRarity] :: any).order
		for i, r in ranked do
			local player = r.player
			local data = S.Data.get(player)
			if data then
				data.stats.nushi += 1
				local luck = S.Fishing.luckFor(player, 1, "")
				local fish, grams, mutation = S.Fishing.rollCatch(player, LAKE, luck, minOrder)
				if fish then
					S.Fishing.grantCatch(player, fish, grams, mutation, LAKE, "nushi")
				end
				if i <= NT.topTitleCount and not table.find(data.titles, "nushi_hunter") then
					table.insert(data.titles, "nushi_hunter")
					S.notify(player, "nushi_title_got", { titleKey = "title_nushi_hunter" })
				end
				S.Data.changed(player)
				S.Analytics.custom(player, "NushiReward")
			end
		end
	else
		S.announce("nushi_fail", {})
	end
	task.delay(4, despawn)
	broadcast()
end

local function tick()
	local now = workspace:GetServerTimeNow()
	local active, remaining, cycle = WorldClock.nushi(now, NT)
	if active and cycle ~= event.cycle then
		-- 新しいぬし
		event.cycle = cycle
		event.active = true
		event.finished = false
		event.progress = 0
		event.participants = {}
		event.endsAt = now + remaining
		event.required = NT.baseRequired
		despawn()
		spawnModel()
		S.announce("nushi_appear", {})
	elseif event.active and not active then
		event.active = false
		if not event.finished then
			finish(false)
		end
	end
	if event.active and not event.finished then
		event.required = NT.baseRequired + NT.perPlayerRequired * math.max(0, participantCount() - 1)
		if event.progress >= event.required then
			finish(true)
		end
	end
	broadcast()
end

function NushiService.init(registry: any)
	S = registry
end

function NushiService.start()
	stateRemote = Remotes.event("NushiState")
	RemoteGuard.connect(Remotes.event("NushiReel"), 3, 4, function(player, inZone)
		if not event.active or event.finished then
			return
		end
		if not RemoteGuard.isNumber(inZone, 0, 5) or not nearLake(player) then
			return
		end
		local now = os.clock()
		local part = event.participants[player]
		if not part then
			part = { contribution = 0, lastReport = now - 1 }
			event.participants[player] = part
		end
		local elapsed = math.min(5, now - part.lastReport)
		part.lastReport = now
		local credited = math.min(inZone, elapsed * NT.contributionPerSecondCap + 0.1)
		part.contribution += credited
		event.progress += credited
	end)
	Players.PlayerRemoving:Connect(function(p)
		event.participants[p] = nil
	end)
	task.spawn(function()
		while true do
			pcall(tick)
			task.wait(1)
		end
	end)
end

return NushiService
