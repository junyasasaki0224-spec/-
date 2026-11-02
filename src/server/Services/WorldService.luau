--!strict
-- 昼夜と天気の「今の状態」をサーバー側で計算する(見た目はクライアントが同じ式で計算)。
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldClock = require(Shared.Lib.WorldClock)
local Types = require(Shared.Lib.Types)

local W = Config.Tuning.World

local WorldService = {}

function WorldService.now(): number
	return workspace:GetServerTimeNow()
end

function WorldService.phase(): string
	return WorldClock.phase(WorldClock.clockTime(WorldService.now(), W), W)
end

function WorldService.weather(): string
	return WorldClock.weatherAt(WorldService.now(), W)
end

function WorldService.conditions(spotId: string): Types.Conditions
	return { spot = spotId, time = WorldService.phase(), weather = WorldService.weather() }
end

function WorldService.init(_S: any) end
function WorldService.start() end

return WorldService
