--!strict
-- ゲームパス・開発者アイテム・報酬型広告。
--  * ProcessReceipt は「付与 → 購入IDを記録 → 保存成功」を確認してから PurchaseGranted を返す。
--    同じ購入が二重に届いても購入IDで判定して二重付与しない。
--  * 価格や効果はすべてサーバー側の Config で決め、クライアントの値は信用しない。
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Products = Config.Products
local B = Config.Tuning.Boosts

local MonetizationService = {}
local S: any

local owned: { [Player]: { [string]: boolean } } = {}
local passKeyById: { [number]: string } = {}
local productKeyById: { [number]: string } = {}
local serverLuckUntil = 0

for _, gp in Products.GamePasses do
	if gp.id ~= 0 then
		passKeyById[gp.id] = gp.key
	end
end
for _, dp in Products.DevProducts do
	if dp.id ~= 0 then
		productKeyById[dp.id] = dp.key
	end
end
if Products.RewardedAd.devProductId ~= 0 then
	productKeyById[Products.RewardedAd.devProductId] = Products.RewardedAd.devProductKey
end

function MonetizationService.hasPass(player: Player, key: string): boolean
	local o = owned[player]
	return o ~= nil and o[key] == true
end

function MonetizationService.ownedPasses(player: Player): { [string]: boolean }
	return owned[player] or {}
end

function MonetizationService.serverLuckUntil(): number
	return serverLuckUntil
end

-- 掛け算の運ブーストの一覧
function MonetizationService.luckMultipliers(player: Player): { number }
	local list = {}
	local now = os.time()
	if MonetizationService.hasPass(player, "luck2x") then
		table.insert(list, B.luckPassMultiplier)
	end
	local data = S.Data.get(player)
	if data then
		if data.boosts.luckUntil > now then
			table.insert(list, 2)
		end
		if data.boosts.adLuckUntil > now then
			table.insert(list, 2)
		end
	end
	if serverLuckUntil > now then
		table.insert(list, 2)
	end
	return list
end

function MonetizationService.sellMultiplier(player: Player): number
	return if MonetizationService.hasPass(player, "vip") then B.vipSellMultiplier else 1
end

function MonetizationService.creelCapacity(player: Player): number
	local I = Config.Tuning.Inventory
	return I.creelBase + (if MonetizationService.hasPass(player, "bigCreel") then I.creelPassBonus else 0)
end

function MonetizationService.tankCapacity(player: Player): number
	local I = Config.Tuning.Inventory
	return I.tankBase * (if MonetizationService.hasPass(player, "bigTank") then I.tankPassMultiplier else 1)
end

local function pushState(player: Player)
	player:SetAttribute(
		"Passes",
		table.concat(
			(function()
				local keys = {}
				for k in MonetizationService.ownedPasses(player) do
					table.insert(keys, k)
				end
				table.sort(keys)
				return keys
			end)(),
			","
		)
	)
	workspace:SetAttribute("ServerLuckUntil", serverLuckUntil)
end

local function grantPass(player: Player, key: string)
	owned[player] = owned[player] or {}
	owned[player][key] = true
	if key == "vip" then
		local data = S.Data.get(player)
		if data and not table.find(data.titles, "vip") then
			table.insert(data.titles, "vip")
			if data.activeTitle == "" then
				data.activeTitle = "vip"
			end
			S.Data.changed(player)
		end
	end
	pushState(player)
	S.Data.replicate(player)
end

local function loadPasses(player: Player)
	owned[player] = owned[player] or {}
	for _, gp in Products.GamePasses do
		if gp.id ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gp.id)
			end)
			if ok and has then
				grantPass(player, gp.key)
			end
		end
	end
	pushState(player)
end

-- 開発者アイテムの効果。true を返したら付与済み
local function applyProduct(player: Player, key: string): boolean
	local data = S.Data.get(player)
	if not data then
		return false
	end
	local now = os.time()
	if key == "luckCharm" then
		data.boosts.luckUntil = math.max(now, data.boosts.luckUntil) + B.luckCharmMinutes * 60
		S.notify(player, "notify_luck_charm")
	elseif key == "serverLuck" then
		serverLuckUntil = math.max(now, serverLuckUntil) + B.serverLuckMinutes * 60
		-- 表示名は Roblox 側でフィルタ済みの公開情報
		S.announce("notify_server_luck", { name = player.DisplayName })
		pushState(player)
	elseif key == "premiumBait10" then
		data.bait.premium = (data.bait.premium or 0) + B.premiumBaitPerPurchase
	elseif key == "questReroll" then
		S.Quest.rerollPending(player)
	elseif key == Products.RewardedAd.devProductKey then
		data.boosts.adLuckUntil = math.max(now, data.boosts.adLuckUntil)
			+ Products.RewardedAd.luckMinutes * 60
		S.notify(player, "notify_ad_luck")
	else
		return false
	end
	S.Data.changed(player)
	return true
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = S.Data.get(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	if table.find(data.purchases, purchaseId) then
		-- 付与済み。保存できていれば完了
		return if S.Data.saveNow(player)
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = productKeyById[info.ProductId]
	if not key then
		warn("[Monetization] unknown product " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not applyProduct(player, key) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.purchases, purchaseId)
	while #data.purchases > Config.Tuning.Data.maxPurchaseHistory do
		table.remove(data.purchases, 1)
	end
	S.Data.changed(player)
	S.Analytics.custom(player, "Purchase_" .. key, info.CurrencySpent)
	if S.Data.saveNow(player) then
		S.notify(player, "notify_purchase_thanks")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- 依頼の入れ替えの前に、どの依頼を入れ替えるかを受け取る
function MonetizationService.handleRequest(player: Player, action: string, payload: any): boolean
	if action == "prepareReroll" then
		if type(payload) == "number" then
			S.Quest.setPendingReroll(player, payload)
		end
		return true
	elseif action == "watchAd" then
		MonetizationService.showRewardedAd(player)
		return true
	end
	return false
end

-- 報酬型動画広告(使えない環境では何もしない)
function MonetizationService.showRewardedAd(player: Player)
	local ad = Products.RewardedAd
	if not ad.enabled or ad.devProductId == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local AdService = game:GetService("AdService") :: any
			local reward = AdService:CreateAdRewardFromDevProductId(ad.devProductId)
			AdService:ShowRewardedVideoAdAsync(player, reward)
		end)
		if not ok then
			warn("[Monetization] rewarded ad unavailable: " .. tostring(err))
		end
	end)
end

function MonetizationService.init(registry: any)
	S = registry
end

function MonetizationService.start()
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passKeyById[passId] then
			grantPass(player, passKeyById[passId])
			S.notify(player, "notify_purchase_thanks")
		end
	end)
	S.Data.Loaded:Connect(function(player)
		task.spawn(loadPasses, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
	end)
	workspace:SetAttribute("ServerLuckUntil", 0)
end

return MonetizationService
