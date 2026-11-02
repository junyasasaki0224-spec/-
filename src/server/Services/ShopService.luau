--!strict
-- 小判の出し入れと、お店・釣り場・設定の操作。
-- 値段・必要条件はすべてサーバーの Config から計算し、クライアントから来るのは「何をしたいか」だけ。
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Pricing = require(Shared.Lib.Pricing)
local Types = require(Shared.Lib.Types)
local RemoteGuard = require(script.Parent.RemoteGuard)

local FT = Config.Tuning.Fishing
local MERCHANT_RANGE = 24

local ShopService = {}
local S: any

function ShopService.priceOf(player: Player, caught: Types.CaughtFish): number
	local fish = Config.FishById[caught.fishId]
	if not fish then
		return 0
	end
	local rarity = Config.RarityById[fish.rarity]
	local mut = caught.mutation and Config.MutationById[caught.mutation]
	local spot = Config.SpotById[caught.spot]
	return Pricing.sellPrice(fish, caught.grams, {
		rarityBasePrice = rarity.basePrice,
		mutationMultiplier = if mut then mut.multiplier else 1,
		spotMultiplier = if spot then spot.priceMultiplier else 1,
		sellMultiplier = S.Monetization.sellMultiplier(player),
		weightMin = FT.weightPriceMin,
		weightMax = FT.weightPriceMax,
	})
end

function ShopService.addCoins(player: Player, amount: number, kind: string, sku: string?)
	local data = S.Data.get(player)
	if not data or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	data.coins += amount
	data.stats.earned += amount
	S.Data.changed(player)
	S.Analytics.economy(player, true, amount, data.coins, kind, sku)
end

function ShopService.spendCoins(player: Player, amount: number, kind: string, sku: string?): boolean
	local data = S.Data.get(player)
	if not data or amount < 0 or data.coins < amount then
		return false
	end
	data.coins -= amount
	S.Data.changed(player)
	S.Analytics.economy(player, false, amount, data.coins, kind, sku)
	return true
end

local function nearMerchant(player: Player): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, m in CollectionService:GetTagged("Merchant") do
		if m:IsA("BasePart") and (m.Position - root.Position).Magnitude <= MERCHANT_RANGE then
			return true
		end
	end
	return false
end
ShopService.nearMerchant = nearMerchant

local function findCreel(data: any, uid: any): number?
	if type(uid) ~= "string" or #uid > 16 then
		return nil
	end
	for i, f in data.creel do
		if f.uid == uid then
			return i
		end
	end
	return nil
end

local function sellIndices(player: Player, indices: { number })
	local data = S.Data.get(player)
	table.sort(indices, function(a, b)
		return a > b
	end)
	local total = 0
	for _, i in indices do
		local f = data.creel[i]
		if f then
			total += ShopService.priceOf(player, f)
			table.remove(data.creel, i)
		end
	end
	if total > 0 then
		ShopService.addCoins(player, total, "SellFish")
		S.Quest.onSell(player, total)
		S.notify(player, "notify_coins", { coins = total })
		if data.tutorial < 5 then
			S.Analytics.onboarding(player, S.Analytics.Onboarding.FirstSell)
		end
	end
end

-- 図鑑の完成報酬(釣り場ごと)
function ShopService.checkCodexCompletion(player: Player, poolSpot: string)
	local data = S.Data.get(player)
	if not data or data.codexRewards[poolSpot] then
		return
	end
	for _, f in Config.Fish do
		if f.spot == poolSpot and not data.codex[f.id] then
			return
		end
	end
	local spot = Config.SpotById[poolSpot]
	data.codexRewards[poolSpot] = true
	local reward = spot and spot.completionReward or 0
	ShopService.addCoins(player, reward, "CodexComplete", poolSpot)
	if poolSpot == "swamp" and not table.find(data.titles, "swamp_master") then
		table.insert(data.titles, "swamp_master")
	end
	S.Data.changed(player)
	S.notify(player, "notify_codex_complete", { spotKey = "spot_" .. poolSpot, coins = reward })
end

local function teleportTo(player: Player, spot: any)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	S.Fishing.cancel(player)
	local o, sp = spot.origin, spot.spawn
	local c = S.Fishing.waterCenter(spot)
	local pos = Vector3.new(o.x + sp.x, o.y + sp.y, o.z + sp.z)
	-- 地形の高さは場所によって違うので、真上から地面を探して少し上に立たせる
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = workspace:Raycast(pos + Vector3.new(0, 120, 0), Vector3.new(0, -240, 0), params)
	if hit then
		pos = Vector3.new(pos.X, hit.Position.Y + 3.5, pos.Z)
	end
	char:PivotTo(CFrame.lookAt(pos, Vector3.new(c.X, pos.Y, c.Z)))
end
ShopService.teleportTo = teleportTo

local handlers: { [string]: (Player, any, any) -> () } = {}

handlers.sell = function(player, data, payload)
	if not nearMerchant(player) then
		return
	end
	local i = findCreel(data, payload)
	if i then
		sellIndices(player, { i })
	end
end

handlers.sellAll = function(player, data, payload)
	if not nearMerchant(player) or not RemoteGuard.isInt(payload, 1, #Config.Rarities) then
		return
	end
	local indices = {}
	for i, f in data.creel do
		local fish = Config.FishById[f.fishId]
		-- 変異つきは大事なので一括売却しない(個別には売れる)
		if fish and not f.mutation and Config.RarityById[fish.rarity].order <= payload then
			table.insert(indices, i)
		end
	end
	sellIndices(player, indices)
end

handlers.toTank = function(player, data, payload)
	local i = findCreel(data, payload)
	if not i then
		return
	end
	if #data.tank >= S.Monetization.tankCapacity(player) then
		S.notify(player, "tank_full")
		return
	end
	table.insert(data.tank, table.remove(data.creel, i))
	S.Data.changed(player)
	S.Aquarium.refresh(player)
end

handlers.fromTank = function(player, data, payload)
	if type(payload) ~= "string" then
		return
	end
	if #data.creel >= S.Monetization.creelCapacity(player) then
		S.notify(player, "fish_creel_full")
		return
	end
	for i, f in data.tank do
		if f.uid == payload then
			table.insert(data.creel, table.remove(data.tank, i))
			S.Data.changed(player)
			S.Aquarium.refresh(player)
			return
		end
	end
end

handlers.buyRod = function(player, data, payload)
	if not RemoteGuard.isInt(payload, 2, #Config.Rods) or payload ~= data.rodTier + 1 then
		return
	end
	local rod = Config.RodByTier[payload]
	if not ShopService.spendCoins(player, rod.price, "BuyRod", rod.id) then
		S.notify(player, "shop_not_enough")
		return
	end
	data.rodTier = payload
	S.Data.changed(player)
	S.Fishing.attachRod(player)
	S.notify(player, "notify_bought", { itemKey = "rod_name", tier = payload })
	if payload == 2 then
		S.Analytics.onboarding(player, S.Analytics.Onboarding.FirstRod)
	end
end

handlers.buyBait = function(player, data, payload)
	if type(payload) ~= "table" then
		return
	end
	local id, amount = payload.id, payload.amount
	if not RemoteGuard.isId(id) or not RemoteGuard.isInt(amount, 1, 100) then
		return
	end
	local bait = Config.BaitById[id]
	if not bait or bait.price <= 0 then
		return
	end
	if (data.bait[id] or 0) + amount > 9999 then
		return
	end
	if not ShopService.spendCoins(player, bait.price * amount, "BuyBait", id) then
		S.notify(player, "shop_not_enough")
		return
	end
	data.bait[id] = (data.bait[id] or 0) + amount
	if data.equippedBait == "" then
		data.equippedBait = id
	end
	S.Data.changed(player)
end

handlers.equipBait = function(player, data, payload)
	if payload == "" then
		data.equippedBait = ""
	elseif RemoteGuard.isId(payload) and Config.BaitById[payload] and (data.bait[payload] or 0) > 0 then
		data.equippedBait = payload
	else
		return
	end
	S.Data.changed(player)
end

handlers.unlockSpot = function(player, data, payload)
	if not RemoteGuard.isId(payload) then
		return
	end
	local spot = Config.SpotById[payload]
	if not spot or not spot.available or data.spots[spot.id] then
		return
	end
	if data.rodTier < spot.unlockRodTier then
		return
	end
	if not ShopService.spendCoins(player, spot.unlockCoins, "UnlockSpot", spot.id) then
		S.notify(player, "shop_not_enough")
		return
	end
	data.spots[spot.id] = true
	S.Data.changed(player)
	S.notify(player, "notify_unlocked", { spotKey = "spot_" .. spot.id })
	S.Analytics.custom(player, "Unlock_" .. spot.id)
end

handlers.travel = function(player, data, payload)
	if not RemoteGuard.isId(payload) then
		return
	end
	local spot = Config.SpotById[payload]
	if not spot or not spot.available then
		return
	end
	if not data.spots[spot.id] then
		S.notify(player, "notify_travel_locked")
		return
	end
	teleportTo(player, spot)
end

handlers.setAutoSell = function(player, data, payload)
	if RemoteGuard.isInt(payload, 0, #Config.Rarities - 1) then
		data.settings.autoSell = payload
		S.Data.changed(player)
	end
end

handlers.setLang = function(player, data, payload)
	if payload == "ja" or payload == "en" or payload == "" then
		data.settings.lang = payload
		S.Data.changed(player)
	end
end

handlers.setAuto = function(player, _data, payload)
	if type(payload) == "boolean" then
		S.Fishing.setAuto(player, payload)
	end
end

handlers.setTitle = function(player, data, payload)
	if payload == "" or (RemoteGuard.isId(payload) and table.find(data.titles, payload)) then
		data.activeTitle = payload
		player:SetAttribute("Title", payload)
		S.Data.changed(player)
	end
end

handlers.tutorial = function(player, data, payload)
	-- 案内の進み具合(見た目だけの値。報酬には使わない)
	if RemoteGuard.isInt(payload, 0, 10) and payload > data.tutorial then
		data.tutorial = payload
		S.Data.changed(player)
	end
end

function ShopService.handleRequest(player: Player, action: string, payload: any): boolean
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

function ShopService.init(registry: any)
	S = registry
end

function ShopService.start()
	-- 鳥居のボタン(近づいて押す)で釣り場へ移動。解放済みかはサーバーで確認する
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if not CollectionService:HasTag(prompt, "YokaiPrompt") then
			return
		end
		local action = prompt:GetAttribute("Action")
		if type(action) == "string" and action:sub(1, 7) == "travel:" then
			local data = S.Data.get(player)
			if data then
				handlers.travel(player, data, action:sub(8))
			end
		end
	end)
	S.Data.Loaded:Connect(function(player: Player)
		local data = S.Data.get(player)
		if data then
			player:SetAttribute("Title", data.activeTitle)
		end
	end)
end

return ShopService
