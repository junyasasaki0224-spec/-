--!strict
-- クライアント側の状態: サーバーから届いた自分のデータ(読み取り専用の写し)と、便利関数。
-- ※ここにある値を書き換えてもサーバーのデータは変わらない(表示用)。
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local Roll = require(Shared.Lib.Roll)

local player = Players.LocalPlayer

local State = {}
State.profile = nil :: any
local changed = Instance.new("BindableEvent")
State.Changed = changed.Event

local requestRemote: RemoteEvent? = nil

function State.init()
	requestRemote = Remotes.event("Request")
	Remotes.event("Profile").OnClientEvent:Connect(function(snapshot)
		State.profile = snapshot
		changed:Fire()
	end)
	player:GetAttributeChangedSignal("Passes"):Connect(function()
		changed:Fire()
	end)
end

function State.request(action: string, payload: any?)
	if requestRemote then
		requestRemote:FireServer(action, payload)
	end
end

function State.hasPass(key: string): boolean
	local s = player:GetAttribute("Passes")
	if type(s) ~= "string" then
		return false
	end
	for k in s:gmatch("[^,]+") do
		if k == key then
			return true
		end
	end
	return false
end

function State.creelCapacity(): number
	local I = Config.Tuning.Inventory
	return I.creelBase + (if State.hasPass("bigCreel") then I.creelPassBonus else 0)
end

function State.tankCapacity(): number
	local I = Config.Tuning.Inventory
	return I.tankBase * (if State.hasPass("bigTank") then I.tankPassMultiplier else 1)
end

-- 表示用の運の倍率(投げる強さ 50% として概算)
function State.luck(): number
	local p = State.profile
	if not p then
		return 1
	end
	local rod = Config.RodByTier[p.rodTier] or Config.Rods[1]
	local bait = Config.BaitById[p.equippedBait]
	local mult = {}
	local now = os.time()
	if State.hasPass("luck2x") then
		table.insert(mult, 2)
	end
	if p.boosts.luckUntil > now then
		table.insert(mult, 2)
	end
	if p.boosts.adLuckUntil > now then
		table.insert(mult, 2)
	end
	local serverUntil = workspace:GetAttribute("ServerLuckUntil")
	if type(serverUntil) == "number" and serverUntil > now then
		table.insert(mult, 2)
	end
	return Roll.luck({
		rodLuck = rod.luck,
		baitLuck = if bait then bait.luck else 0,
		power = 0.5,
		distanceBonus = Config.Tuning.Fishing.distanceLuckBonus,
		multipliers = mult,
		maxLuck = Config.Tuning.Fishing.maxLuck,
	})
end

-- 売値の目安(サーバーと同じ式。実際の売値はサーバーが決める)
function State.priceOf(caught: any): number
	local Pricing = require(Shared.Lib.Pricing)
	local fish = Config.FishById[caught.fishId]
	if not fish then
		return 0
	end
	local mut = caught.mutation and Config.MutationById[caught.mutation]
	local spot = Config.SpotById[caught.spot]
	return Pricing.sellPrice(fish, caught.grams, {
		rarityBasePrice = Config.RarityById[fish.rarity].basePrice,
		mutationMultiplier = if mut then mut.multiplier else 1,
		spotMultiplier = if spot then spot.priceMultiplier else 1,
		sellMultiplier = if State.hasPass("vip") then Config.Tuning.Boosts.vipSellMultiplier else 1,
		weightMin = Config.Tuning.Fishing.weightPriceMin,
		weightMax = Config.Tuning.Fishing.weightPriceMax,
	})
end

return State
