--!strict
-- オンライン対戦(相棒3匹どうしのターン制)。ターンの計算・勝ち負け・強さの点数・ごほうびはすべてサーバー。
-- ・申し込み: 同じサーバーの人へ。相手が「受ける」を押したら始まる。受け取る相手(全員 / 友達だけ / 受け取らない)は各自が選べる
-- ・ランダム対戦: 同じサーバーで待っている人と、強さの近い順に組む。いなければ少し待ってから、
--   ほかのサーバーの釣り人のチームの写し(MemoryStore。コンピューターが動かす)と戦う。写しの持ち主の名前は出さない
-- 1ターンは お互いが選び終わる か 時間切れ(コンピューターが代わりに選ぶ)で進む。続けて選ばない人は降参あつかい。
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local BattleLib = require(Shared.Lib.Battle)
local Rating = require(Shared.Lib.Rating)
local WorldClock = require(Shared.Lib.WorldClock)
local RemoteGuard = require(script.Parent.RemoteGuard)

local O = Config.Online
local B = Config.Battle

local PvpService = {}
local S: any

type Seat = { player: Player?, action: BattleLib.Action?, missed: number, rating: number }
type Match = {
	kind: string, -- "challenge"(申し込み)/ "random"(このサーバーの人と)/ "ghost"(ほかのサーバーのチームと)
	state: BattleLib.State,
	seats: { player: Seat, enemy: Seat },
	deadline: number,
}
type Queued = { since: number, power: number, fetching: boolean, nextGhostTry: number }

local matches: { [Player]: Match } = {}
local challenges: { [Player]: { to: Player, expires: number } } = {} -- 申し込んだ人 → 相手
local lastChallenge: { [string]: number } = {}
local queue: { [Player]: Queued } = {}
local lastGhostWrite: { [Player]: number } = {}
local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local arena: RemoteEvent
local stateRemote: RemoteEvent
local ghostMap: any = nil

local function today(): number
	return WorldClock.dayIndex(os.time(), Config.Tuning.Quests.dayOffsetSeconds)
end

local function otherSide(side: string): string
	return if side == "player" then "enemy" else "player"
end

local function seatOf(m: Match, side: string): Seat
	return if side == "player" then m.seats.player else m.seats.enemy
end

local function sideOf(m: Match, player: Player): string
	return if m.seats.player.player == player then "player" else "enemy"
end

function PvpService.busy(player: Player): boolean
	return matches[player] ~= nil
end

function PvpService.queued(player: Player): boolean
	return queue[player] ~= nil
end

function PvpService.leaveQueue(player: Player)
	if queue[player] then
		queue[player] = nil
		arena:FireClient(player, { kind = "queue", state = "idle" })
	end
end

local function teamOf(player: Player): { BattleLib.Fighter }
	local data = S.Data.get(player)
	if not data then
		return {}
	end
	return S.Battle.fighters(S.Battle.teamFor(data))
end

-- ほかのサーバーの釣り人のチームの置き場所 ---------------------------------------
local function store(): any?
	if ghostMap == nil then
		local ok, m = pcall(function()
			return MemoryStoreService:GetSortedMap(O.GhostStore)
		end)
		ghostMap = if ok then m else false
	end
	return if ghostMap then ghostMap else nil
end

-- 自分のチームの写しを置く(ほかのサーバーのランダム対戦の相手になる)。持ち主は UserId だけで、名前は置かない
function PvpService.publishTeam(player: Player)
	local data = S.Data.get(player)
	local found = store()
	if not data or not found then
		return
	end
	local map: any = found
	local team = S.Battle.teamFor(data)
	if #team == 0 then
		return
	end
	local snap = {}
	for _, p in team do
		table.insert(snap, { f = p.fishId, g = p.grams, m = p.mutation, l = p.level })
	end
	local power = BattleLib.power(S.Battle.fighters(team))
	local value = { team = snap, power = power, rating = data.pvp.rating, title = data.activeTitle }
	lastGhostWrite[player] = os.clock()
	local key = tostring(player.UserId)
	-- 強さで並べて探せるように sortKey を付ける(古い API なら付けずに置く)
	local ok = pcall(function()
		map:SetAsync(key, value, O.GhostTtlSeconds, math.floor(power))
	end)
	if not ok then
		pcall(function()
			map:SetAsync(key, value, O.GhostTtlSeconds)
		end)
	end
end

function PvpService.eraseUser(userId: number)
	local map: any = store()
	if map ~= nil then
		pcall(function()
			map:RemoveAsync(tostring(userId))
		end)
	end
end

-- 写しを戦う魚に戻す(壊れた値は使わない)
local function ghostFighters(v: any): { BattleLib.Fighter }
	local list = {}
	if type(v) ~= "table" or type(v.team) ~= "table" then
		return list
	end
	for i, t in v.team do
		if i > B.TeamSize or type(t) ~= "table" then
			break
		end
		local def = Config.FishById[t.f]
		local level = t.l
		local grams = t.g
		if
			def
			and type(level) == "number"
			and level == math.floor(level)
			and level >= 1
			and level <= B.MaxLevel
			and type(grams) == "number"
			and grams > 0
			and grams < 1e7
			and (t.m == nil or Config.MutationById[t.m] ~= nil)
		then
			table.insert(list, BattleLib.fighter(def, grams, t.m, level))
		end
	end
	return list
end

local function fetchGhost(power: number): any?
	local found = store()
	if not found then
		return nil
	end
	local map: any = found
	local lo, hi = power * (1 - O.PowerWindow), power * (1 + O.PowerWindow)
	local ok, items = pcall(function()
		return map:GetRangeAsync(
			Enum.SortDirection.Ascending,
			50,
			{ sortKey = math.floor(lo) },
			{ sortKey = math.ceil(hi) }
		)
	end)
	if not ok then
		ok, items = pcall(function()
			return map:GetRangeAsync(Enum.SortDirection.Ascending, 100)
		end)
	end
	if not ok or type(items) ~= "table" then
		return nil
	end
	local here = {}
	for _, p in Players:GetPlayers() do
		here[tostring(p.UserId)] = true
	end
	local candidates = {}
	for _, it in items do
		local v = it.value
		if
			type(v) == "table"
			and not here[it.key]
			and type(v.power) == "number"
			and v.power >= lo
			and v.power <= hi
			and #ghostFighters(v) > 0
		then
			table.insert(candidates, v)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

-- 試合 -----------------------------------------------------------------------
local function opponentInfo(m: Match, side: string, ghost: any?): any
	local other = seatOf(m, otherSide(side))
	if other.player then
		local d = S.Data.get(other.player)
		return {
			name = other.player.DisplayName,
			title = if d then d.activeTitle else "",
			rating = other.rating,
		}
	end
	return {
		ghost = true,
		title = if ghost and type(ghost.title) == "string" then ghost.title else "",
		rating = other.rating,
	}
end

local function startMatch(a: Player, b: Player?, kind: string, ghost: any?): boolean
	local da = S.Data.get(a)
	local db = if b then S.Data.get(b) else nil
	if not da or (b and not db) then
		return false
	end
	local teamA = teamOf(a)
	local teamB = if b then teamOf(b) else ghostFighters(ghost)
	if #teamA == 0 or #teamB == 0 then
		return false
	end
	local m: Match = {
		kind = kind,
		state = BattleLib.new(teamA, teamB),
		seats = {
			player = { player = a, action = nil, missed = 0, rating = da.pvp.rating },
			enemy = {
				player = b,
				action = nil,
				missed = 0,
				rating = if db
					then db.pvp.rating
					elseif ghost and type(ghost.rating) == "number" then ghost.rating
					else O.RatingStart,
			},
		},
		deadline = os.clock() + O.FirstTurnSeconds,
	}
	for _, side in { "player", "enemy" } do
		local p = seatOf(m, side).player
		if p then
			queue[p] = nil
			challenges[p] = nil
			S.Fishing.cancel(p)
			S.Raid.leaveRoom(p)
			matches[p] = m
			arena:FireClient(p, { kind = "queue", state = "idle" })
			stateRemote:FireClient(p, {
				kind = "start",
				mode = "pvp",
				pvpKind = kind,
				opponent = opponentInfo(m, side, ghost),
				state = BattleLib.publicState(m.state, side),
				seconds = O.FirstTurnSeconds,
			})
			S.Analytics.custom(p, "PvpStart_" .. kind)
		end
	end
	return true
end

local function finish(m: Match)
	local winner = m.state.winner
	local ranked = m.kind ~= "challenge"
	local a, b = m.seats.player, m.seats.enemy
	local newA, newB = a.rating, b.rating
	if ranked then
		newA, newB = Rating.update(a.rating, b.rating, if winner == "player" then 1 else 0, O.RatingK)
	end
	for _, side in { "player", "enemy" } do
		local seat = seatOf(m, side)
		local p = seat.player
		if p and matches[p] == m then
			matches[p] = nil
			local data = S.Data.get(p)
			if data then
				local win = winner == side
				local coins = 0
				if win then
					data.pvp.wins += 1
				else
					data.pvp.losses += 1
				end
				if ranked then
					data.pvp.rating = math.max(0, if side == "player" then newA else newB)
				end
				-- ランダム対戦の1日の最初の勝利だけ小判(申し込み対戦は練習・遊び用で小判なし)
				if win and ranked and data.pvp.dailyWinDay ~= today() then
					data.pvp.dailyWinDay = today()
					coins = O.DailyWinCoins
					S.Shop.addCoins(p, coins, "PvpDailyWin")
				end
				S.Data.changed(p)
				stateRemote:FireClient(p, {
					kind = "result",
					mode = "pvp",
					pvpKind = m.kind,
					win = win,
					coins = coins,
					ranked = ranked,
					ratingFrom = seat.rating,
					ratingTo = data.pvp.rating,
				})
				S.Analytics.custom(p, "Pvp_" .. m.kind .. (if win then "_Win" else "_Lose"))
			end
		end
	end
end

local function sendTurn(m: Match, events: { any })
	for _, side in { "player", "enemy" } do
		local p = seatOf(m, side).player
		if p then
			stateRemote:FireClient(p, {
				kind = "turn",
				mode = "pvp",
				events = if side == "player" then events else BattleLib.mirrorEvents(events),
				state = BattleLib.publicState(m.state, side),
				seconds = O.TurnSeconds,
			})
		end
	end
end

local function resolve(m: Match)
	for _, side in { "player", "enemy" } do
		local seat = seatOf(m, side)
		if not seat.action then
			if seat.player then
				seat.missed += 1
			end
			-- 選ばなかった人(と写しのチーム)はコンピューターが選ぶ。続けて選ばない人は降参
			seat.action = if seat.player and seat.missed >= O.MaxMissedTurns
				then { kind = "run" }
				else BattleLib.aiChoose(m.state, rand, side)
		end
	end
	local events = BattleLib.turn(m.state, m.seats.player.action :: any, rand, m.seats.enemy.action)
	m.seats.player.action = nil
	m.seats.enemy.action = nil
	m.deadline = os.clock() + O.TurnSeconds
	sendTurn(m, events)
	if m.state.over then
		finish(m)
	end
end

-- 降参・抜けた人は負け(相手を待たずにすぐ決まる。抜けた人の点数もちゃんと動かす)
local function forfeit(player: Player)
	local m = matches[player]
	if not m or m.state.over then
		return
	end
	local side = sideOf(m, player)
	m.state.over = true
	m.state.winner = otherSide(side)
	sendTurn(m, { { kind = "run", side = side }, { kind = "end", winner = m.state.winner } })
	finish(m)
end

function PvpService.act(player: Player, action: any)
	local m = matches[player]
	if not m or m.state.over then
		return
	end
	if type(action) == "table" and action.kind == "run" then
		forfeit(player)
		return
	end
	local side = sideOf(m, player)
	local seat = seatOf(m, side)
	if seat.action or not BattleLib.validAction(m.state, action, side) then
		return
	end
	seat.action = action
	seat.missed = 0
	local other = seatOf(m, otherSide(side))
	if other.player == nil or other.action then
		resolve(m)
	else
		-- 自分は選び終わった。相手には「相手は選び終わった」と知らせる
		stateRemote:FireClient(player, { kind = "waiting" })
		stateRemote:FireClient(other.player, { kind = "foeReady" })
	end
end

-- ランダム対戦の組み合わせ(待った時間が長い人から、強さの近い人と)
local function tryPair()
	local list = {}
	for p, q in queue do
		if not q.fetching then
			table.insert(list, { p = p, q = q })
		end
	end
	table.sort(list, function(x, y)
		return x.q.since < y.q.since
	end)
	local used = {}
	for i, a in list do
		if not used[a.p] then
			local best, bestDiff = nil, math.huge
			local window = O.PowerWindow + (os.clock() - a.q.since) * 0.02 -- 待つほど広げる
			for j = i + 1, #list do
				local b = list[j]
				if not used[b.p] then
					local diff = math.abs(a.q.power - b.q.power) / math.max(1, a.q.power, b.q.power)
					if diff <= window and diff < bestDiff then
						best, bestDiff = b, diff
					end
				end
			end
			if best and startMatch(a.p, best.p, "random") then
				used[a.p] = true
				used[best.p] = true
			end
		end
	end
end

local function tick()
	local now = os.clock()
	-- 申し込みの期限切れ
	for from, c in challenges do
		if c.expires < now then
			challenges[from] = nil
			S.notify(from, "pvp_expired")
			arena:FireClient(from, { kind = "sentGone" })
			arena:FireClient(c.to, { kind = "inviteGone", from = from.UserId })
		end
	end
	tryPair()
	-- このサーバーに相手がいない人は、ほかのサーバーのチームと
	for p, q in queue do
		local waited = now - q.since
		if waited >= O.QueueGiveUpAfter then
			queue[p] = nil
			arena:FireClient(p, { kind = "queue", state = "idle" })
			S.notify(p, "pvp_no_opponent")
		elseif waited >= O.QueueGhostAfter and not q.fetching and now >= q.nextGhostTry then
			q.fetching = true
			arena:FireClient(p, { kind = "queue", state = "ghost" })
			task.spawn(function()
				local g = fetchGhost(q.power)
				if queue[p] ~= q then
					return -- その間にやめた・組めた
				end
				q.fetching = false
				q.nextGhostTry = os.clock() + 8
				if g then
					startMatch(p, nil, "ghost", g)
				end
			end)
		end
	end
	-- ターンの時間切れ
	local seen = {}
	for _, m in matches do
		if not seen[m] then
			seen[m] = true
			if not m.state.over and now >= m.deadline then
				resolve(m)
			end
		end
	end
	-- 自分のチームの写しをときどき置き直す
	for _, p in Players:GetPlayers() do
		if (lastGhostWrite[p] or -math.huge) + O.GhostWriteEverySeconds < now and S.Data.get(p) then
			lastGhostWrite[p] = now
			task.spawn(PvpService.publishTeam, p)
		end
	end
end

-- 操作 -----------------------------------------------------------------------
local handlers: { [string]: (Player, any, any) -> () } = {}

handlers.pvpChallenge = function(player, data, payload)
	if not RemoteGuard.isInt(payload, 1, 1e12) then
		return
	end
	local target = Players:GetPlayerByUserId(payload)
	if not target or target == player then
		return
	end
	local tdata = S.Data.get(target)
	if not tdata then
		return
	end
	if S.Battle.inBattle(player) or queue[player] or S.Raid.inRoom(player) then
		S.notify(player, "pvp_you_busy")
		return
	end
	if S.Battle.inBattle(target) or S.Raid.inRoom(target) then
		S.notify(player, "pvp_target_busy")
		return
	end
	if #S.Battle.teamFor(data) == 0 then
		S.notify(player, "battle_need_partner")
		return
	end
	if #S.Battle.teamFor(tdata) == 0 then
		S.notify(player, "pvp_target_no_team")
		return
	end
	local key = player.UserId .. ":" .. target.UserId
	if (lastChallenge[key] or -math.huge) + O.ChallengeCooldown > os.clock() then
		S.notify(player, "pvp_wait")
		return
	end
	local pref = tdata.settings.challenges or "all"
	if pref == "friends" then
		local ok, isFriend = pcall(function()
			return target:IsFriendsWith(player.UserId)
		end)
		if not (ok and isFriend) then
			pref = "off"
		end
	end
	if pref == "off" then
		S.notify(player, "pvp_target_closed")
		return
	end
	lastChallenge[key] = os.clock()
	challenges[player] = { to = target, expires = os.clock() + O.ChallengeSeconds }
	arena:FireClient(target, {
		kind = "invite",
		from = player.UserId,
		name = player.DisplayName,
		rating = data.pvp.rating,
		title = data.activeTitle,
		seconds = O.ChallengeSeconds,
	})
	arena:FireClient(
		player,
		{ kind = "sent", to = target.UserId, name = target.DisplayName, seconds = O.ChallengeSeconds }
	)
end

handlers.pvpRespond = function(player, _data, payload)
	if type(payload) ~= "table" or not RemoteGuard.isInt(payload.from, 1, 1e12) then
		return
	end
	local from = Players:GetPlayerByUserId(payload.from)
	local c = from and challenges[from]
	if not from or not c or c.to ~= player or c.expires < os.clock() then
		return
	end
	challenges[from] = nil
	arena:FireClient(from, { kind = "sentGone" })
	if payload.accept ~= true then
		S.notify(from, "pvp_declined", { name = player.DisplayName })
		return
	end
	if S.Battle.inBattle(from) or S.Battle.inBattle(player) then
		S.notify(player, "pvp_target_busy")
		return
	end
	startMatch(from, player, "challenge")
end

handlers.pvpCancelChallenge = function(player)
	local c = challenges[player]
	if c then
		challenges[player] = nil
		arena:FireClient(player, { kind = "sentGone" })
		arena:FireClient(c.to, { kind = "inviteGone", from = player.UserId })
	end
end

handlers.pvpQueue = function(player, _data)
	if queue[player] or S.Battle.inBattle(player) then
		return
	end
	if S.Raid.inRoom(player) then
		S.notify(player, "pvp_you_busy")
		return
	end
	local team = teamOf(player)
	if #team == 0 then
		S.notify(player, "battle_need_partner")
		return
	end
	queue[player] = { since = os.clock(), power = BattleLib.power(team), fetching = false, nextGhostTry = 0 }
	arena:FireClient(player, { kind = "queue", state = "searching", since = 0 })
	tryPair()
end

handlers.pvpCancel = function(player)
	PvpService.leaveQueue(player)
end

handlers.setChallengePref = function(player, data, payload)
	if payload == "all" or payload == "friends" or payload == "off" then
		data.settings.challenges = payload
		S.Data.changed(player)
		S.Social.publish(player)
	end
end

function PvpService.handleRequest(player: Player, action: string, payload: any): boolean
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

function PvpService.init(registry: any)
	S = registry
end

function PvpService.start()
	arena = Remotes.event("Arena")
	stateRemote = Remotes.event("BattleState")
	-- データを保存する前に負けを付ける(先に保存されると、抜ければ点数が減らない抜け道になる)
	S.Data.onRelease(forfeit)
	Players.PlayerRemoving:Connect(function(player)
		forfeit(player)
		queue[player] = nil
		lastGhostWrite[player] = nil
		local c = challenges[player]
		if c then
			challenges[player] = nil
			arena:FireClient(c.to, { kind = "inviteGone", from = player.UserId })
		end
		for from, cc in challenges do
			if cc.to == player then
				challenges[from] = nil
				arena:FireClient(from, { kind = "sentGone" })
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Pvp] " .. tostring(err))
			end
		end
	end)
end

return PvpService
