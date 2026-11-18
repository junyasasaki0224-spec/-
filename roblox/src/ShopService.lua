-- ロビーのサーバー: Robux の購入を受け取って品を渡す(ショップの品は開発者製品、VIP はゲームパス)。
-- 守ること:
--   ・品を渡すのはサーバーだけ。プレイヤー側からの「買った」という知らせは信じない(Roblox の ProcessReceipt だけで渡す)
--   ・保存できた時だけ PurchaseGranted を返す。できなければ NotProcessedYet(Roblox があとでもう一度届ける)
--   ・同じ購入番号は1回だけ渡す(Meta.grantPurchase が購入番号を覚えている)
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local Meta = require(ReplicatedStorage:WaitForChild("Meta"))
local Service = require(script.Parent:WaitForChild("MetaService"))

local Shop = {}
-- 製品の番号 → 品(番号が 0 の物は入れない)
Shop.byProduct = {}
for _, entry in Config.products do
	local item = Meta.item(entry.item)
	if entry.product > 0 and item and item.shop then
		Shop.byProduct[entry.product] = entry
	end
end

-- 品が届いたことを本人の画面に知らせる合図(すでにあれば使い回す)
local event = ReplicatedStorage:FindFirstChild("MinatoShop")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "MinatoShop"
	event.Parent = ReplicatedStorage
end
Shop.event = event

-- 品を渡して保存する。保存できたら true と "granted" / "already"
function Shop.grant(userId, purchaseId, ids)
	local ok, meta, result = pcall(Service.grant, userId, purchaseId, ids)
	if not ok or meta == nil then
		warn("[Shop] 保存できませんでした。あとでもう一度受け取ります")
		return false
	end
	-- 届いたことを本人の画面に知らせる(ホームで品を見せる)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		if meta.vip then
			player:SetAttribute("MinatoVip", true)
		end
		if result == "granted" then
			event:FireClient(player, "granted", ids)
		end
	end
	return true, result
end

-- Roblox から届いた購入(開発者製品)
function Shop.processReceipt(info)
	local entry = Shop.byProduct[info.ProductId]
	if not entry or type(info.PlayerId) ~= "number" or type(info.PurchaseId) ~= "string" then
		-- 知らない製品: 渡さずに残しておく(設定を直せば、次に届いた時に渡せる)
		warn("[Shop] 知らない製品の購入です: " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not Shop.grant(info.PlayerId, "p:" .. info.PurchaseId, { entry.item }) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- VIP パスを持っているか確かめて、特典を渡す(何度呼んでも1回だけ渡る)
function Shop.checkVip(player)
	local pass = Config.vip.pass
	if pass <= 0 then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass)
	if ok and owns then
		Shop.grant(player.UserId, "pass:" .. pass, Config.vip.items)
	end
end

function Shop.start()
	MarketplaceService.ProcessReceipt = Shop.processReceipt
	Players.PlayerAdded:Connect(function(player)
		task.spawn(Shop.checkVip, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(Shop.checkVip, player)
	end
	-- その場で VIP パスを買った時(番号を確かめてから、持っているかを Roblox に聞き直す)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.vip.pass then
			Shop.checkVip(player)
		end
	end)
end

return Shop
