-- 引き上げ(網のゲージ)の手応えを数字で見る: 本物の ReelGame の動きを、人のように操作するボットで何度も遊ぶ。
-- ボットは「少し前の様子を見て」押す/離すを決める(反応の遅れ)。たまに押し間違える(ミス)。
--   lune run tools/sim/reel_sim.luau
local H = require("../../tests/harness")
local F = require("../../tests/fakes")

local shared = H.root("src/shared")
local client = H.root("src/client")
local Config = H.require(shared.Config)
local FT = Config.Tuning.Fishing
local FC = Config.Tuning.FirstCatch

local holding = false
H.override(client.Controllers.Input, {
	isHolding = function()
		return holding
	end,
})
H.globals = {
	game = {
		GetService = function(_, name)
			if name == "ReplicatedStorage" then
				return {
					WaitForChild = function()
						return shared
					end,
				}
			elseif name == "TweenService" then
				return {
					Create = function()
						return { Play = function() end }
					end,
				}
			elseif name == "RunService" then
				return { RenderStepped = F.Signal() }
			end
			return {}
		end,
	},
	task = F.task,
	os = F.os,
	TweenInfo = {
		new = function()
			return {}
		end,
	},
	Instance = { new = F.new },
}
local ReelGame = H.require(client.Controllers.ReelGame)

-- サーバー(FishingService)と同じ式で、引き上げの設定を作る
local function paramsFor(rarityId: string, rodTier: number, easy: boolean, seed: number): any
	local rarity = Config.RarityById[rarityId]
	local rod = Config.RodByTier[rodTier]
	return {
		rarity = rarityId,
		duration = rarity.reelSeconds,
		fishSpeed = rarity.fishSpeed * (if easy then 0.5 else 1),
		jitter = rarity.jitter * (if easy then 0.5 else 1),
		tensionRate = rarity.tensionRate * (if easy then 0.5 else 1),
		tensionDecay = FT.tensionDecay,
		netSize = math.clamp(FT.netBaseSize * rod.netSize * (if easy then 1.5 else 1), 0.1, 0.6),
		reelSpeed = rod.reelSpeed,
		startProgress = FT.startProgress,
		seed = seed,
	}
end

-- 1回遊ぶ。reaction: 反応の遅れ(秒)、mistake: 1回の判断で押し間違える確率
local botRng = H.Random.new(7)
local function play(params: any, reaction: number, mistake: number): (boolean, number)
	local result = nil
	local g = ReelGame.new(F.new("Frame"), params, "normal", {
		onFinish = function(ok)
			result = ok
		end,
	})
	local dt = 1 / 30
	local history = {}
	local delay = math.max(1, math.floor(reaction / dt))
	local t = 0
	local decideEvery = 3 -- 人は毎フレームではなく、ときどき判断する
	local frame = 0
	while result == nil and t < FT.reelTimeoutSeconds do
		table.insert(history, { fish = g.fish, net = g.net, vel = g.netVel })
		local seen = history[math.max(1, #history - delay)]
		frame += 1
		if frame % decideEvery == 0 then
			local center = seen.net + params.netSize / 2 + seen.vel * 0.35
			holding = seen.fish > center
			if botRng:NextNumber() < mistake then
				holding = not holding
			end
		end
		g:step(dt)
		t += dt
	end
	holding = false
	return result == true, t
end

local function rate(
	rarityId: string,
	rodTier: number,
	easy: boolean,
	reaction: number,
	mistake: number,
	n: number
)
	local wins, time = 0, 0
	for i = 1, n do
		local ok, t = play(paramsFor(rarityId, rodTier, easy, i * 7919), reaction, mistake)
		if ok then
			wins += 1
			time += t
		end
	end
	return wins / n, if wins > 0 then time / wins else 0
end

local N = 200
print("引き上げの成功率(本物の ReelGame・人のようなボット・各200回)")
print("  上手な人 = 反応0.2秒・ミス5% / はじめての人 = 反応0.4秒・ミス15%")
print(
	("  %-10s %-6s %-22s %-22s"):format(
		"レア度",
		"竿",
		"上手な人(成功・時間)",
		"はじめての人"
	)
)
local p1, t1 = rate("uncommon", 1, true, 0.2, 0.05, N)
local p2, t2 = rate("uncommon", 1, true, 0.4, 0.15, N)
print(
	("  %-10s %-6s %5.0f%%  %4.1f秒            %5.0f%%  %4.1f秒"):format(
		"最初の1匹",
		"1",
		p1 * 100,
		t1,
		p2 * 100,
		t2
	)
)
for _, r in Config.Rarities do
	for _, tier in { 1, 3, 6 } do
		local a, at = rate(r.id, tier, false, 0.2, 0.05, N)
		local b, bt = rate(r.id, tier, false, 0.4, 0.15, N)
		print(
			("  %-10s %-6d %5.0f%%  %4.1f秒            %5.0f%%  %4.1f秒"):format(
				r.id,
				tier,
				a * 100,
				at,
				b * 100,
				bt
			)
		)
	end
end
