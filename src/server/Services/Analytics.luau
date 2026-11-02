--!strict
-- Roblox 標準の AnalyticsService への記録(個人情報は送らない。プレイヤーは Roblox 側で匿名集計される)。
-- 失敗してもゲームに影響しないよう、すべて pcall で包む。
local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

-- 最初の30秒の離脱を見るためのファネル
Analytics.Onboarding = {
	Joined = 1,
	FirstCast = 2,
	FirstHook = 3,
	FirstCatch = 4,
	FirstSell = 5,
	FirstRod = 6,
}
local ONBOARDING_NAMES = { "Joined", "FirstCast", "FirstHook", "FirstCatch", "FirstSell", "FirstRod" }

local function safe(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		-- Studio などでは失敗することがある。うるさくならないよう1行だけ
		warn("[Analytics] " .. tostring(err))
	end
end

function Analytics.onboarding(player: Player, step: number)
	safe(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, ONBOARDING_NAMES[step] or tostring(step))
	end)
end

-- 小判の入出: source = 入手, sink = 消費
function Analytics.economy(
	player: Player,
	isSource: boolean,
	amount: number,
	balance: number,
	kind: string,
	sku: string?
)
	if amount <= 0 then
		return
	end
	safe(function()
		AnalyticsService:LogEconomyEvent(
			player,
			if isSource then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			"Koban",
			amount,
			balance,
			kind,
			sku
		)
	end)
end

function Analytics.custom(player: Player, name: string, value: number?)
	safe(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1)
	end)
end

function Analytics.init(_S: any) end
function Analytics.start() end

return Analytics
