--!strict
-- 技選びの手伝い(お札の「★ おすすめ」と「おまかせ」)。
-- 画面に見えている情報(BattleLib.publicState)だけで選ぶ。決めるのはあくまでサーバーで、これは選ぶ手伝いだけ。
local Config = require(script.Parent.Parent.Config)
local BattleLib = require(script.Parent.Battle)

local BattleAdvice = {}

-- 技ごとの目安の点数(高いほどおすすめ)
function BattleAdvice.score(move: any, me: any, foe: any): number
	if move.power > 0 then
		local el = BattleLib.moveElement(move, me)
		local eff = BattleLib.effectiveness(el, foe.element)
		local stab = if el == me.element then 1.25 else 1
		local score = move.power * eff * stab * (move.acc / 100)
		-- 相手があと少しなら、先に動ける技で仕留める
		if move.effect == "first" and foe.hp <= foe.maxHp * 0.2 then
			score *= 1.6
		end
		return score
	elseif move.effect == "heal" then
		-- 体力が減っている時だけ回復
		local r = me.hp / math.max(1, me.maxHp)
		return if r < 0.35 then 200 elseif r < 0.55 then 40 else 0
	end
	-- 能力を上げ下げする技: 最初の1回だけ少し考える
	local stages = me.stages or { atk = 0, def = 0 }
	if (move.effect == "atk_up" and stages.atk == 0) or (move.effect == "def_up" and stages.def == 0) then
		return if me.hp > me.maxHp * 0.7 then 30 else 5
	end
	return 5
end

-- いちばん良さそうな技の番号(1〜4)。技が無ければ nil
function BattleAdvice.suggest(state: any): number?
	local side = state and state.player
	if not side or not side.moves then
		return nil
	end
	local me = side.team[side.active]
	local foe = state.enemy and state.enemy.team[state.enemy.active]
	if not me or not foe then
		return nil
	end
	local best, bestScore = nil, -1
	for i, id in side.moves do
		local mv = Config.MoveById[id]
		if mv then
			local s = BattleAdvice.score(mv, me, foe)
			if s > bestScore then
				best, bestScore = i, s
			end
		end
	end
	return best
end

return BattleAdvice
