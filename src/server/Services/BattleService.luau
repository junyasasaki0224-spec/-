--!strict
-- 妖怪退治(相棒バトル)の進行。ターンの計算・勝ち負け・報酬はすべてサーバーで行う。
-- クライアントから来るのは「どの相手に挑むか」と「毎ターンの行動(技の番号・交代先・逃げる)」だけで、
-- 能力値・ダメージ・経験値はクライアントの値を一切使わない。
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local BattleLib = require(Shared.Lib.Battle)
local WorldClock = require(Shared.Lib.WorldClock)
local RemoteGuard = require(script.Parent.RemoteGuard)

local B = Config.Battle

local BattleService = {}
local S: any

type Session = {
	state: BattleLib.State,
	trainerId: string,
	lastAction: number,
	participants: { [string]: boolean },
}

local sessions: { [Player]: Session } = {}
local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local stateRemote: RemoteEvent

-- 何かの戦い(妖怪退治・対戦・ボス戦)の最中か。釣り・相棒の入れ替えはこの間できない
function BattleService.inBattle(player: Player): boolean
	return sessions[player] ~= nil
		or (S ~= nil and S.Pvp ~= nil and S.Pvp.busy(player))
		or (S ~= nil and S.Raid ~= nil and S.Raid.fighting(player))
end

-- 挑戦できるか(上から順番に。前の相手に勝っていれば次に挑める)
function BattleService.canChallenge(data: any, trainerId: string): boolean
	for i, t in Config.Trainers do
		if t.id == trainerId then
			return i == 1 or data.battle.cleared[Config.Trainers[i - 1].id] == true
		end
	end
	return false
end

local function teamFor(data: any): { any }
	local list = {}
	for _, uid in data.team do
		for _, p in data.partners do
			if p.uid == uid then
				table.insert(list, p)
			end
		end
	end
	if #list == 0 then
		for i = 1, math.min(B.TeamSize, #data.partners) do
			table.insert(list, data.partners[i])
		end
	end
	return list
end

BattleService.teamFor = teamFor

-- 相棒の表から、戦う魚(能力値つき)の表を作る
function BattleService.fighters(team: { any }): { BattleLib.Fighter }
	local list = {}
	for _, p in team do
		local def = Config.FishById[p.fishId]
		if def then
			table.insert(list, BattleLib.fighter(def, p.grams, p.mutation, p.level, p.uid))
		end
	end
	return list
end

local function markParticipant(sess: Session)
	local f = BattleLib.active(sess.state.sides.player)
	if f.uid then
		sess.participants[f.uid] = true
	end
end

local function finish(player: Player, sess: Session)
	sessions[player] = nil
	local data = S.Data.get(player)
	if not data then
		return
	end
	local trainer = Config.TrainerById[sess.trainerId]
	local win = sess.state.winner == "player"
	local enemyLevels = 0
	for _, m in trainer.team do
		enemyLevels += m.level
	end
	-- 経験値: 勝てば満額、負けても 1/4(出場した相棒のみ)
	local xp = math.floor(enemyLevels * B.WinXpPerEnemyLevel * (if win then 1 else 0.25))
	local gains = {}
	for _, p in data.partners do
		if sess.participants[p.uid] then
			local before = p.level
			local levels = S.Partner.giveXp(player, p, xp)
			table.insert(
				gains,
				{ fishId = p.fishId, xp = xp, level = p.level, from = before, levels = levels }
			)
		end
	end
	local coins, firstClear, title = 0, false, nil
	if win then
		firstClear = not data.battle.cleared[trainer.id]
		data.battle.cleared[trainer.id] = true
		data.battle.wins += 1
		-- 2回目以降の小判は、相手ごとに1日1回だけ(経験値は何度でも)。
		-- 何度でも払うと、強い相手の再戦が釣りの十倍以上の稼ぎになり、釣りをする理由が無くなるため
		local today = WorldClock.dayIndex(os.time(), Config.Tuning.Quests.dayOffsetSeconds)
		if firstClear then
			coins = trainer.reward.coins
		elseif data.battle.rematchPaid[trainer.id] ~= today then
			coins = math.floor(trainer.reward.coins * B.RematchCoinRate)
			data.battle.rematchPaid[trainer.id] = today
		else
			coins = 0
		end
		S.Shop.addCoins(player, coins, if firstClear then "BattleFirstWin" else "BattleWin", trainer.id)
		if firstClear and trainer.reward.bait then
			local b = trainer.reward.bait
			data.bait[b.id] = (data.bait[b.id] or 0) + b.amount
		end
		if firstClear and trainer.title and not table.find(data.titles, trainer.title) then
			table.insert(data.titles, trainer.title)
			title = trainer.title
		end
		S.Quest.onBattleWin(player)
		S.Analytics.custom(player, (if firstClear then "BattleClear_" else "BattleRewin_") .. trainer.id)
	else
		S.Analytics.custom(player, "BattleLose_" .. trainer.id)
	end
	S.Data.changed(player)
	stateRemote:FireClient(player, {
		kind = "result",
		win = win,
		trainerId = trainer.id,
		coins = coins,
		firstClear = firstClear,
		rematchPaidToday = win and not firstClear and coins == 0, -- 今日はこの相手の小判をもうもらった
		bait = if win and firstClear then trainer.reward.bait else nil,
		title = title,
		gains = gains,
	})
end

local function start(player: Player, trainerId: any)
	if not RemoteGuard.isId(trainerId) or BattleService.inBattle(player) then
		return
	end
	local data = S.Data.get(player)
	local trainer = Config.TrainerById[trainerId]
	if not data or not trainer then
		return
	end
	if not BattleService.canChallenge(data, trainerId) then
		S.notify(player, "battle_locked")
		return
	end
	local team = teamFor(data)
	if #team == 0 then
		S.notify(player, "battle_need_partner")
		return
	end
	S.Fishing.cancel(player)
	S.Pvp.leaveQueue(player)
	local mine = BattleService.fighters(team)
	local enemies = {}
	for _, m in trainer.team do
		local def = Config.FishById[m.fish]
		local grams = math.floor((def.kg[1] + def.kg[2]) * 500)
		table.insert(enemies, BattleLib.fighter(def, grams, m.mutation, m.level))
	end
	local sess: Session = {
		state = BattleLib.new(mine, enemies),
		trainerId = trainer.id,
		lastAction = os.clock(),
		participants = {},
	}
	sessions[player] = sess
	markParticipant(sess)
	stateRemote:FireClient(
		player,
		{ kind = "start", trainerId = trainer.id, state = BattleLib.publicState(sess.state) }
	)
end

local function act(player: Player, action: any)
	-- 受け取った表から必要な値だけを取り出す(余計なキーは無視)
	if type(action) ~= "table" then
		return
	end
	local clean = { kind = action.kind, index = action.index, slot = action.slot }
	if clean.kind ~= "move" and clean.kind ~= "switch" and clean.kind ~= "run" then
		return
	end
	if clean.index ~= nil and not RemoteGuard.isInt(clean.index, 1, 4) then
		return
	end
	if clean.slot ~= nil and not RemoteGuard.isInt(clean.slot, 1, B.TeamSize) then
		return
	end
	-- 対戦・ボス戦の最中なら、そちらへ
	if S.Pvp.busy(player) then
		S.Pvp.act(player, clean)
		return
	elseif S.Raid.fighting(player) then
		S.Raid.act(player, clean)
		return
	end
	local sess = sessions[player]
	if not sess then
		return
	end
	if not BattleLib.validAction(sess.state, clean) then
		return
	end
	sess.lastAction = os.clock()
	local events = BattleLib.turn(sess.state, clean :: any, rand)
	markParticipant(sess)
	stateRemote:FireClient(
		player,
		{ kind = "turn", events = events, state = BattleLib.publicState(sess.state) }
	)
	if sess.state.over then
		finish(player, sess)
	end
end

function BattleService.handleRequest(player: Player, action: string, payload: any): boolean
	if action == "startBattle" then
		start(player, payload)
		return true
	elseif action == "setBattlePrefs" then
		-- 見た目の好みだけ(勝ち負けには関係しない)。決まった値だけ受け付ける
		local data = S.Data.get(player)
		if data and type(payload) == "table" then
			if payload.speed == 1 or payload.speed == 2 then
				data.settings.battleSpeed = payload.speed
			end
			if type(payload.shake) == "boolean" then
				data.settings.battleShake = payload.shake
			end
			S.Data.changed(player)
		end
		return true
	end
	return false
end

function BattleService.init(registry: any)
	S = registry
end

function BattleService.start()
	stateRemote = Remotes.event("BattleState")
	RemoteGuard.connect(Remotes.event("BattleAction"), 4, 4, act)
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)
	-- 放置されたバトルは負けにする
	task.spawn(function()
		while true do
			task.wait(5)
			for player, sess in sessions do
				if os.clock() - sess.lastAction > B.IdleTimeoutSeconds then
					sess.state.over = true
					sess.state.winner = "enemy"
					finish(player, sess)
				end
			end
		end
	end)
end

return BattleService
