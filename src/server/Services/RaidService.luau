--!strict
-- ボス戦(協力)。同じサーバーの最大4人で、巨大な妖怪に相棒で挑む。
-- ・部屋: 「部屋を作る」→ ほかの人が「参加」→ ホストが始める(または一定時間で自動で始まる)
-- ・戦い方: 一人ずつ自分の画面でボスと戦い(ボスは全員を攻撃する)、与えたダメージはみんなで1本の体力から減る。
--   体力は人数が多いほど多い。半分を切るとボスが怒って攻撃が上がる。制限時間内に倒せば全員の勝ち
-- ・ごほうび: 経験値は毎回。小判とエサはボスごとに1日1回。初めて倒すと称号(あるボスだけ)
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local BattleLib = require(Shared.Lib.Battle)
local WorldClock = require(Shared.Lib.WorldClock)
local RemoteGuard = require(script.Parent.RemoteGuard)

local O = Config.Online
local B = Config.Battle

local RaidService = {}
local S: any

type Room = {
	id: number,
	bossId: string,
	host: Player,
	members: { Player },
	state: string, -- "open" / "running" / "done"
	startsAt: number,
}
type Fight = {
	state: BattleLib.State,
	participants: { [string]: boolean },
	out: boolean,
	dealt: number,
}
type Raid = {
	room: Room,
	boss: any,
	pool: number,
	max: number,
	endsAt: number,
	fights: { [Player]: Fight },
	enraged: boolean,
	over: boolean,
}

local rooms: { Room } = {}
local raidOf: { [Player]: Raid } = {}
local nextId = 0
local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local arena: RemoteEvent
local stateRemote: RemoteEvent

local function today(): number
	return WorldClock.dayIndex(os.time(), Config.Tuning.Quests.dayOffsetSeconds)
end

local function roomOf(player: Player): Room?
	for _, r in rooms do
		if r.state == "open" and table.find(r.members, player) then
			return r
		end
	end
	return nil
end

function RaidService.inRoom(player: Player): boolean
	return roomOf(player) ~= nil
end

function RaidService.fighting(player: Player): boolean
	return raidOf[player] ~= nil
end

-- 部屋の一覧をサーバーの全員へ(名前は Roblox の表示名だけ)
local function roomList(): { any }
	local list = {}
	for _, r in rooms do
		if r.state == "open" then
			local members = {}
			for _, m in r.members do
				table.insert(members, { userId = m.UserId, name = m.DisplayName })
			end
			table.insert(list, {
				id = r.id,
				bossId = r.bossId,
				hostId = r.host.UserId,
				members = members,
				max = O.RaidPartyMax,
				startsIn = math.max(0, math.ceil(r.startsAt - os.clock())),
			})
		end
	end
	return list
end

local function broadcastRooms()
	arena:FireAllClients({ kind = "rooms", rooms = roomList() })
end

local function removeRoom(room: Room)
	local i = table.find(rooms, room)
	if i then
		table.remove(rooms, i)
	end
end

function RaidService.leaveRoom(player: Player)
	local found = roomOf(player)
	if not found then
		return
	end
	local room = found :: Room
	table.remove(room.members, table.find(room.members, player) :: number)
	if #room.members == 0 then
		removeRoom(room)
	elseif room.host == player then
		room.host = room.members[1]
	end
	broadcastRooms()
end

local function canFight(player: Player, data: any): boolean
	if S.Battle.inBattle(player) then
		S.notify(player, "pvp_you_busy")
		return false
	end
	if #S.Battle.teamFor(data) == 0 then
		S.notify(player, "battle_need_partner")
		return false
	end
	return true
end

-- 戦い ------------------------------------------------------------------------
local function info(raid: Raid): any
	local members = {}
	for _, m in raid.room.members do
		local f = raid.fights[m]
		table.insert(members, {
			userId = m.UserId,
			name = m.DisplayName,
			alive = f ~= nil and not f.out,
			dealt = if f then f.dealt else 0,
		})
	end
	return {
		bossId = raid.boss.id,
		hp = raid.pool,
		max = raid.max,
		seconds = math.max(0, math.ceil(raid.endsAt - os.clock())),
		enraged = raid.enraged,
		members = members,
	}
end

local function broadcastRaid(raid: Raid)
	local msg = { kind = "raid", raid = info(raid) }
	for p in raid.fights do
		stateRemote:FireClient(p, msg)
	end
end

local function markParticipant(f: Fight)
	local a = BattleLib.active(f.state.sides.player)
	if a.uid then
		f.participants[a.uid] = true
	end
end

local function finishRaid(raid: Raid, win: boolean)
	if raid.over then
		return
	end
	raid.over = true
	raid.room.state = "done"
	removeRoom(raid.room)
	local boss = raid.boss
	for player, f in raid.fights do
		raidOf[player] = nil
		local data = S.Data.get(player)
		if data then
			-- 経験値: 勝てば ボスのレベル × 2倍、負けても 1/4(出た相棒だけ)
			local xp = math.floor(boss.level * B.WinXpPerEnemyLevel * 2 * (if win then 1 else 0.25))
			local gains = {}
			for _, p in data.partners do
				if f.participants[p.uid] then
					local before = p.level
					local levels = S.Partner.giveXp(player, p, xp)
					table.insert(
						gains,
						{ fishId = p.fishId, xp = xp, level = p.level, from = before, levels = levels }
					)
				end
			end
			local coins, bait, title = 0, nil, nil
			local paidToday = false
			if win then
				data.raid.clears[boss.id] = (data.raid.clears[boss.id] or 0) + 1
				local E = Config.Gacha.Earn
				if data.raid.clears[boss.id] == 1 then
					S.Gacha.give(player, E.raidFirst, E.raidFirstTickets, "RaidFirst")
				end
				if data.raid.paid[boss.id] ~= today() then
					data.raid.paid[boss.id] = today()
					S.Gacha.give(player, E.raidDaily, 0, "RaidDaily")
					coins = boss.reward.coins
					S.Shop.addCoins(player, coins, "RaidWin", boss.id)
					if boss.reward.bait then
						bait = boss.reward.bait
						data.bait[bait.id] = (data.bait[bait.id] or 0) + bait.amount
					end
				else
					paidToday = true
				end
				if boss.title and not table.find(data.titles, boss.title) then
					table.insert(data.titles, boss.title)
					title = boss.title
				end
				S.Quest.onBattleWin(player)
			end
			S.Data.changed(player)
			stateRemote:FireClient(player, {
				kind = "result",
				mode = "raid",
				bossId = boss.id,
				win = win,
				coins = coins,
				bait = bait,
				title = title,
				gains = gains,
				dealt = f.dealt,
				rewardPaidToday = paidToday,
			})
			S.Analytics.custom(player, (if win then "RaidWin_" else "RaidLose_") .. boss.id)
		end
	end
	broadcastRooms()
end

local function startRaid(room: Room)
	if room.state ~= "open" then
		return
	end
	local boss = Config.BossById[room.bossId]
	local def = boss and Config.FishById[boss.fish]
	if not def then
		removeRoom(room)
		broadcastRooms()
		return
	end
	-- まだいて、戦える人だけ
	local members = {}
	for _, m in room.members do
		local data = S.Data.get(m)
		if m.Parent == Players and data and not S.Battle.inBattle(m) and #S.Battle.teamFor(data) > 0 then
			table.insert(members, m)
		end
	end
	if #members == 0 then
		removeRoom(room)
		broadcastRooms()
		return
	end
	room.members = members
	room.state = "running"
	local grams = math.floor((def.kg[1] + def.kg[2]) * 500)
	local base = BattleLib.fighter(def, grams, nil, boss.level)
	local max = math.floor(base.maxHp * boss.hpMult * #members)
	local raid: Raid = {
		room = room,
		boss = boss,
		pool = max,
		max = max,
		endsAt = os.clock() + O.RaidSeconds,
		fights = {},
		enraged = false,
		over = false,
	}
	for _, m in members do
		local data = S.Data.get(m)
		local foe = table.clone(base)
		foe.maxHp = max
		foe.hp = max
		foe.atk = math.floor(base.atk * boss.atkMult)
		foe.moves = table.clone(base.moves)
		foe.stages = { atk = 0, def = 0 }
		local f: Fight = {
			state = BattleLib.new(S.Battle.fighters(S.Battle.teamFor(data)), { foe }),
			participants = {},
			out = false,
			dealt = 0,
		}
		markParticipant(f)
		raid.fights[m] = f
		raidOf[m] = raid
		S.Fishing.cancel(m)
		S.Pvp.leaveQueue(m)
	end
	for m, f in raid.fights do
		stateRemote:FireClient(m, {
			kind = "start",
			mode = "raid",
			bossId = boss.id,
			state = BattleLib.publicState(f.state),
			raid = info(raid),
		})
		S.Analytics.custom(m, "RaidStart_" .. boss.id)
	end
	broadcastRooms()
end

local function checkAllOut(raid: Raid)
	for _, f in raid.fights do
		if not f.out then
			return
		end
	end
	finishRaid(raid, false)
end

function RaidService.act(player: Player, action: any)
	local raid = raidOf[player]
	local f = raid and raid.fights[player]
	if not raid or not f or raid.over then
		return
	end
	if action.kind == "run" then
		-- 抜ける(ごほうびは無し)。ほかの人は続けられる
		f.out = true
		raid.fights[player] = nil
		raidOf[player] = nil
		stateRemote:FireClient(player, {
			kind = "result",
			mode = "raid",
			bossId = raid.boss.id,
			win = false,
			retreated = true,
			gains = {},
		})
		broadcastRaid(raid)
		checkAllOut(raid)
		return
	end
	-- 相棒が全員倒れた人は、抜ける以外できない
	if f.out or not BattleLib.validAction(f.state, action) then
		return
	end
	local foe = f.state.sides.enemy.team[1]
	local before = foe.hp
	local events = BattleLib.turn(f.state, action, rand)
	markParticipant(f)
	local dealt = math.max(0, before - foe.hp)
	f.dealt += dealt
	raid.pool = math.max(0, raid.pool - dealt)
	-- みんなの画面のボスの体力をそろえる
	for _, other in raid.fights do
		local b = other.state.sides.enemy.team[1]
		b.hp = raid.pool
		if raid.pool <= 0 then
			other.state.over = true
			other.state.winner = "player"
		end
	end
	-- 半分を切ったら怒る(攻撃が1段上がる)
	if not raid.enraged and raid.pool > 0 and raid.pool <= raid.max / 2 then
		raid.enraged = true
		for _, other in raid.fights do
			local b = other.state.sides.enemy.team[1]
			b.stages.atk = math.min(3, b.stages.atk + 1)
		end
	end
	if f.state.over and f.state.winner == "enemy" and raid.pool > 0 then
		f.out = true -- 相棒が全員倒れた。ほかの人の戦いを見守る
	end
	stateRemote:FireClient(
		player,
		{ kind = "turn", mode = "raid", events = events, state = BattleLib.publicState(f.state) }
	)
	broadcastRaid(raid)
	if raid.pool <= 0 then
		finishRaid(raid, true)
	else
		checkAllOut(raid)
	end
end

-- 操作 -----------------------------------------------------------------------
local handlers: { [string]: (Player, any, any) -> () } = {}

handlers.raidCreate = function(player, data, payload)
	if not RemoteGuard.isId(payload) or not Config.BossById[payload] then
		return
	end
	if roomOf(player) or not canFight(player, data) then
		return
	end
	local open = 0
	for _, r in rooms do
		if r.state ~= "done" then
			open += 1
		end
	end
	if open >= O.RaidRoomsMax then
		S.notify(player, "raid_rooms_full")
		return
	end
	S.Pvp.leaveQueue(player)
	nextId += 1
	local room: Room = {
		id = nextId,
		bossId = payload,
		host = player,
		members = { player },
		state = "open",
		startsAt = os.clock() + O.RaidLobbySeconds,
	}
	table.insert(rooms, room)
	broadcastRooms()
	-- ほかの人へ「仲間を募集中」
	arena:FireAllClients({
		kind = "recruit",
		roomId = room.id,
		bossId = room.bossId,
		hostId = player.UserId,
		name = player.DisplayName,
	})
	S.Analytics.custom(player, "RaidRoom_" .. payload)
end

handlers.raidJoin = function(player, data, payload)
	if not RemoteGuard.isInt(payload, 1, 1e9) or roomOf(player) then
		return
	end
	local room = nil
	for _, r in rooms do
		if r.id == payload and r.state == "open" then
			room = r
		end
	end
	if not room then
		S.notify(player, "raid_room_gone")
		return
	end
	if #room.members >= O.RaidPartyMax then
		S.notify(player, "raid_room_full")
		return
	end
	if not canFight(player, data) then
		return
	end
	S.Pvp.leaveQueue(player)
	table.insert(room.members, player)
	broadcastRooms()
	if #room.members >= O.RaidPartyMax then
		startRaid(room)
	end
end

handlers.raidLeave = function(player)
	RaidService.leaveRoom(player)
end

handlers.raidStart = function(player)
	local room = roomOf(player)
	if room and room.host == player then
		startRaid(room)
	end
end

function RaidService.handleRequest(player: Player, action: string, payload: any): boolean
	local h = handlers[action]
	if not h then
		return false
	end
	local data = S.Data.get(player)
	if data then
		h(player, data, payload)
	end
	return true
end

function RaidService.init(registry: any)
	S = registry
end

function RaidService.start()
	arena = Remotes.event("Arena")
	stateRemote = Remotes.event("BattleState")
	S.Data.Loaded:Connect(function(player: Player)
		arena:FireClient(player, { kind = "rooms", rooms = roomList() })
	end)
	Players.PlayerRemoving:Connect(function(player)
		RaidService.leaveRoom(player)
		local raid = raidOf[player]
		if raid then
			raidOf[player] = nil
			raid.fights[player] = nil
			if not raid.over then
				broadcastRaid(raid)
				checkAllOut(raid)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				local now = os.clock()
				for _, r in table.clone(rooms) do
					if r.state == "open" and now >= r.startsAt then
						startRaid(r)
					end
				end
				local seen = {}
				for _, raid in raidOf do
					if not seen[raid] then
						seen[raid] = true
						if not raid.over and now >= raid.endsAt then
							finishRaid(raid, false)
						end
					end
				end
			end)
			if not ok then
				warn("[Raid] " .. tostring(err))
			end
		end
	end)
end

return RaidService
