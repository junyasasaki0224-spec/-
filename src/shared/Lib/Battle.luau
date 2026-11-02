--!strict
-- 相棒バトルの計算(純粋関数。乱数は rng() で外から渡すのでテストできる)。
-- ポケモンのような1対1の交代制ターンバトル:
--   * 素早さの高い方が先に動く(「先制」の技は必ず先)
--   * ダメージ = レベル・威力・攻撃/防御・属性の相性・同じ属性の技(1.25倍)・急所(1.5倍)・乱数(0.85〜1)
--   * 倒れたら次の魚が自動で出る。全員倒れたら負け
-- 結果を決めるのはサーバーだけ。クライアントは表示用の状態(publicState)を受け取る。

local Config = require(script.Parent.Parent.Config)
local Pricing = require(script.Parent.Pricing)
local Types = require(script.Parent.Types)

local B = Config.Battle

type Rng = () -> number

local BattleLib = {}

export type Fighter = {
	fishId: string,
	uid: string?,
	element: string,
	shape: string,
	rarity: string,
	mutation: string?,
	level: number,
	maxHp: number,
	hp: number,
	atk: number,
	def: number,
	spd: number,
	moves: { string },
	stages: { atk: number, def: number },
	stunned: boolean,
}

export type Side = { team: { Fighter }, active: number }

export type State = {
	sides: { player: Side, enemy: Side },
	turn: number,
	over: boolean,
	winner: string?,
}

export type Action = { kind: string, index: number?, slot: number? }

-- 能力値 -------------------------------------------------------------------
function BattleLib.stats(def: Types.FishDef, grams: number, mutation: string?, level: number)
	local base = B.ShapeStats[def.shape] or B.ShapeStats.koi
	local rp = B.RarityPower[def.rarity] or 1
	local growth = 1 + (math.clamp(level, 1, B.MaxLevel) - 1) * B.Growth
	local t = Pricing.weightT(def, grams)
	local weight = B.WeightBonus[1] + (B.WeightBonus[2] - B.WeightBonus[1]) * t
	local mut = mutation and Config.MutationById[mutation]
	local mutBonus = if mut then 1 + (mut.multiplier - 1) * B.MutationBonus else 1
	local k = rp * growth * weight * mutBonus
	return {
		hp = math.floor(base.hp * k + 10 + level),
		atk = math.floor(base.atk * k),
		def = math.floor(base.def * k),
		spd = math.floor(base.spd * k),
	}
end

-- 覚えている技(最大4つ。新しく覚えた順に残る)
function BattleLib.movesFor(def: Types.FishDef, level: number): { string }
	local L = B.LearnLevels
	local learned: { { id: string, at: number } } = {}
	local em = B.ElementMoves[def.element] or B.ElementMoves.water
	table.insert(learned, { id = em[1], at = L.elementBasic })
	table.insert(learned, { id = B.ShapeMove[def.shape] or "leap", at = L.shape })
	table.insert(learned, { id = "rest", at = L.rest })
	table.insert(learned, { id = em[2], at = L.elementStrong })
	local rarity = Config.RarityById[def.rarity]
	if rarity and rarity.order >= L.specialMinRarityOrder then
		table.insert(learned, { id = "yoki_burst", at = L.special })
	end
	local out = {}
	for _, m in learned do
		if level >= m.at then
			table.insert(out, m.id)
		end
	end
	while #out > 4 do
		table.remove(out, 1)
	end
	return out
end

function BattleLib.fighter(
	def: Types.FishDef,
	grams: number,
	mutation: string?,
	level: number,
	uid: string?
): Fighter
	local st = BattleLib.stats(def, grams, mutation, level)
	return {
		fishId = def.id,
		uid = uid,
		element = def.element,
		shape = def.shape,
		rarity = def.rarity,
		mutation = mutation,
		level = level,
		maxHp = st.hp,
		hp = st.hp,
		atk = st.atk,
		def = st.def,
		spd = st.spd,
		moves = BattleLib.movesFor(def, level),
		stages = { atk = 0, def = 0 },
		stunned = false,
	}
end

-- 経験値 -------------------------------------------------------------------
-- 経験値を足してレベルを上げる。戻り値: 新しいレベル, 残りの経験値, 上がったレベル数
-- rarity: 育てる魚のレア度(レアほど次のレベルまでの経験値が多い)
function BattleLib.addXp(level: number, xp: number, gain: number, rarity: string?): (number, number, number)
	local gained = 0
	xp += math.max(0, math.floor(gain))
	while level < B.MaxLevel and xp >= B.xpToNext(level, rarity) do
		xp -= B.xpToNext(level, rarity)
		level += 1
		gained += 1
	end
	if level >= B.MaxLevel then
		xp = 0
	end
	return level, xp, gained
end

-- 魚を食べさせた時の経験値
function BattleLib.feedXp(food: Types.FishDef, foodGrams: number, partner: Types.FishDef): number
	local base = B.FeedXp[food.rarity] or 0
	local same = if food.element == partner.element then B.FeedSameElement else 1
	local weight = 0.75 + 0.5 * Pricing.weightT(food, foodGrams)
	return math.floor(base * same * weight)
end

-- 相性 ---------------------------------------------------------------------
function BattleLib.moveElement(move: any, attacker: Fighter): string
	return if move.element == "self" then attacker.element else move.element
end

function BattleLib.effectiveness(moveElement: string, defenderElement: string): number
	local row = B.Chart[moveElement]
	return if row and row[defenderElement] then row[defenderElement] else 1
end

local function stageMult(stage: number): number
	if stage >= 0 then
		return 1 + B.StageStep * stage
	end
	return 1 / (1 + B.StageStep * -stage)
end

-- ダメージ(命中の判定は別)
function BattleLib.damage(
	attacker: Fighter,
	defender: Fighter,
	move: any,
	rng: Rng
): (number, number, boolean)
	if move.power <= 0 then
		return 0, 1, false
	end
	local el = BattleLib.moveElement(move, attacker)
	local eff = BattleLib.effectiveness(el, defender.element)
	local stab = if el == attacker.element then 1.25 else 1
	local atk = attacker.atk * stageMult(attacker.stages.atk)
	local def = math.max(1, defender.def * stageMult(defender.stages.def))
	local base = ((0.4 * attacker.level + 2) * move.power * atk / def) / 16 + 2
	local crit = rng() < B.CritChance
	local dmg = base * stab * eff * (0.85 + rng() * 0.15) * (if crit then 1.5 else 1)
	return math.max(1, math.floor(dmg)), eff, crit
end

-- 状態 ---------------------------------------------------------------------
function BattleLib.new(player: { Fighter }, enemy: { Fighter }): State
	return {
		sides = { player = { team = player, active = 1 }, enemy = { team = enemy, active = 1 } },
		turn = 0,
		over = false,
		winner = nil,
	}
end

local function active(side: Side): Fighter
	return side.team[side.active]
end
BattleLib.active = active

local function nextAlive(side: Side): number?
	for i, f in side.team do
		if f.hp > 0 then
			return i
		end
	end
	return nil
end

-- 敵の行動(期待ダメージの高い技を選ぶ。2割はランダムで、たまに補助技も使う)
function BattleLib.aiChoose(state: State, rng: Rng): Action
	local me = active(state.sides.enemy)
	local foe = active(state.sides.player)
	if rng() < 0.2 then
		return { kind = "move", index = math.floor(rng() * #me.moves) + 1 }
	end
	local best, bestScore = 1, -math.huge
	for i, id in me.moves do
		local move = Config.MoveById[id]
		local score
		if move.power > 0 then
			local el = BattleLib.moveElement(move, me)
			score = move.power
				* BattleLib.effectiveness(el, foe.element)
				* (if el == me.element then 1.25 else 1)
				* move.acc
				/ 100
		elseif move.effect == "heal" then
			score = if me.hp < me.maxHp * 0.35 then 120 else -1
		else
			score = if state.turn < 2 then 35 else 10
		end
		if score > bestScore then
			best, bestScore = i, score
		end
	end
	return { kind = "move", index = best }
end

-- 行動が正しいか(プレイヤーの入力の検証)
function BattleLib.validAction(state: State, action: any): boolean
	if type(action) ~= "table" or state.over then
		return false
	end
	local side = state.sides.player
	if action.kind == "move" then
		local f = active(side)
		return type(action.index) == "number" and f.moves[action.index] ~= nil
	elseif action.kind == "switch" then
		local slot = action.slot
		return type(slot) == "number"
			and slot ~= side.active
			and side.team[slot] ~= nil
			and side.team[slot].hp > 0
	elseif action.kind == "run" then
		return true
	end
	return false
end

-- 1ターン進める。表示用のイベントの列を返す
function BattleLib.turn(state: State, playerAction: Action, rng: Rng): { any }
	local events = {}
	local function push(e: any)
		table.insert(events, e)
	end
	if state.over then
		return events
	end
	if playerAction.kind == "run" then
		state.over = true
		state.winner = "enemy"
		push({ kind = "run" })
		push({ kind = "end", winner = "enemy" })
		return events
	end
	state.turn += 1
	local sides = state.sides
	local enemyAction = BattleLib.aiChoose(state, rng)

	-- 交代は技より先
	if playerAction.kind == "switch" then
		sides.player.active = playerAction.slot :: number
		local f = active(sides.player)
		f.stages = { atk = 0, def = 0 }
		push({ kind = "switch", side = "player", slot = sides.player.active, fishId = f.fishId })
	end

	type Planned = { sideName: string, actor: Fighter, move: any }
	local plans: { Planned } = {}
	if playerAction.kind == "move" then
		local f = active(sides.player)
		table.insert(
			plans,
			{ sideName = "player", actor = f, move = Config.MoveById[f.moves[playerAction.index :: number]] }
		)
	end
	do
		local f = active(sides.enemy)
		table.insert(
			plans,
			{ sideName = "enemy", actor = f, move = Config.MoveById[f.moves[enemyAction.index :: number]] }
		)
	end
	table.sort(plans, function(a, b)
		local fa = if a.move.effect == "first" then 1 else 0
		local fb = if b.move.effect == "first" then 1 else 0
		if fa ~= fb then
			return fa > fb
		end
		if a.actor.spd ~= b.actor.spd then
			return a.actor.spd > b.actor.spd
		end
		return a.sideName == "player"
	end)
	-- 同速のときは乱数で(並び替えの比較関数の中では乱数を使わない)
	if
		#plans == 2
		and plans[1].actor.spd == plans[2].actor.spd
		and plans[1].move.effect ~= "first"
		and plans[2].move.effect ~= "first"
	then
		if rng() < 0.5 then
			plans[1], plans[2] = plans[2], plans[1]
		end
	end

	for _, plan in plans do
		if state.over then
			break
		end
		local mySide = sides[plan.sideName]
		local foeName = if plan.sideName == "player" then "enemy" else "player"
		local foeSide = sides[foeName]
		local actor = plan.actor
		-- 倒れた・交代した魚は動かない
		if actor.hp <= 0 or active(mySide) ~= actor then
			continue
		end
		if actor.stunned then
			actor.stunned = false
			push({ kind = "stunned", side = plan.sideName })
			continue
		end
		local move = plan.move
		local target = active(foeSide)
		push({ kind = "move", side = plan.sideName, move = move.id })
		if rng() * 100 >= move.acc then
			push({ kind = "miss", side = plan.sideName })
			continue
		end
		if move.power > 0 then
			local dmg, eff, crit = BattleLib.damage(actor, target, move, rng)
			target.hp = math.max(0, target.hp - dmg)
			push({ kind = "damage", side = foeName, amount = dmg, eff = eff, crit = crit, hp = target.hp })
		end
		local effect = move.effect
		if effect and effect ~= "first" and (move.chance == nil or rng() < move.chance) then
			if effect == "heal" then
				local before = actor.hp
				actor.hp = math.min(actor.maxHp, actor.hp + math.floor(actor.maxHp * (move.amount or 0.3)))
				push({ kind = "heal", side = plan.sideName, amount = actor.hp - before, hp = actor.hp })
			elseif effect == "atk_up" or effect == "def_up" then
				local stat = if effect == "atk_up" then "atk" else "def"
				actor.stages[stat] = math.min(3, actor.stages[stat] + 1)
				push({ kind = "stat", side = plan.sideName, stat = stat, delta = 1 })
			elseif (effect == "atk_down" or effect == "def_down") and target.hp > 0 then
				local stat = if effect == "atk_down" then "atk" else "def"
				target.stages[stat] = math.max(-3, target.stages[stat] - 1)
				push({ kind = "stat", side = foeName, stat = stat, delta = -1 })
			elseif effect == "stun" and target.hp > 0 then
				target.stunned = true
				push({ kind = "stun", side = foeName })
			end
		end
		if target.hp <= 0 then
			push({ kind = "faint", side = foeName, fishId = target.fishId })
			local nextIndex = nextAlive(foeSide)
			if nextIndex then
				foeSide.active = nextIndex
				push({ kind = "switch", side = foeName, slot = nextIndex, fishId = active(foeSide).fishId })
			else
				state.over = true
				state.winner = plan.sideName
			end
		end
	end

	if not state.over and state.turn >= B.MaxTurns then
		state.over = true
		state.winner = "enemy"
	end
	if state.over then
		push({ kind = "end", winner = state.winner })
	end
	return events
end

-- クライアントに送る状態(相手の技の中身などは送らない)
function BattleLib.publicState(state: State): any
	local function sideInfo(side: Side, withMoves: boolean)
		local team = {}
		for _, f in side.team do
			table.insert(team, {
				fishId = f.fishId,
				level = f.level,
				hp = f.hp,
				maxHp = f.maxHp,
				element = f.element,
				mutation = f.mutation,
				stages = f.stages,
			})
		end
		return {
			team = team,
			active = side.active,
			moves = if withMoves then table.clone(active(side).moves) else nil,
		}
	end
	return {
		player = sideInfo(state.sides.player, true),
		enemy = sideInfo(state.sides.enemy, false),
		turn = state.turn,
		over = state.over,
		winner = state.winner,
	}
end

return BattleLib
