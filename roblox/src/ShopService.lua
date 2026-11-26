-- ロビーのサーバー: Robux の購入を受け取って渡す(コインの袋は開発者製品、VIP 会員はサブスクリプション)。
-- 会場のサーバーも、VIP 会員かどうかの確かめ(Shop.ensureVip)だけに使う(start は呼ばない)。
-- 守ること:
--   ・渡すのはサーバーだけ。プレイヤー側からの「買った」という知らせは信じない(Roblox の ProcessReceipt だけで渡す)
--   ・保存できた時だけ PurchaseGranted を返す。できなければ NotProcessedYet(Roblox があとでもう一度届ける)
--   ・同じ購入番号は1回だけ渡す(Meta.grantPurchase が購入番号を覚えている)
--   ・コインはガチャ(中身がランダム)に使うので、Roblox の決まりで買えない地域がある。
--     PolicyService で確かめ、買えない人にはコインの袋の購入画面を出さず、VIP のコインの特典も付けない
--   ・VIP 会員かどうかは、毎回 Roblox に聞いて決める(画面からの知らせは信じない)。
--     切れたと確かめられたら、VIP の品をスタンダードに戻す。聞けなかった時は、今の状態のままにして次にもう一度聞く
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ShopConfig"))
local Meta = require(ReplicatedStorage:WaitForChild("Meta"))
local Service = require(script.Parent:WaitForChild("MetaService"))

local Shop = {}
-- 製品の番号 → コインの袋(番号が 0 の物は入れない)。key → コインの袋
Shop.byProduct = {}
Shop.byKey = {}
for _, entry in Config.coins do
	Shop.byKey[entry.key] = entry
	if entry.product > 0 then
		Shop.byProduct[entry.product] = entry
	end
end

-- 品が届いたことを本人の画面に知らせる合図(すでにあれば使い回す)。画面からは「この袋を買いたい」だけを受け取る
local event = ReplicatedStorage:FindFirstChild("MinatoShop")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "MinatoShop"
	event.Parent = ReplicatedStorage
end
Shop.event = event

-- コイン(ガチャに使える)を Robux で買えるか。確かめられない時は「買えない」として扱う
local allowed: { [Player]: boolean } = {}
function Shop.coinsAllowed(player: Player): boolean
	if allowed[player] ~= nil then
		return allowed[player]
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	local result = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
	if ok then
		-- 確かめられた時だけ覚える(失敗した時は次にもう一度聞く)
		allowed[player] = result
	end
	player:SetAttribute("MinatoCoinShop", result)
	return result
end

-- 品とコインを渡して保存する。保存できたら true と "granted" / "already"
function Shop.grant(userId: number, purchaseId: string, ids: { string }, coins: number)
	local ok, meta, result = pcall(Service.grant, userId, purchaseId, ids, coins)
	if not ok or meta == nil then
		warn("[Shop] 保存できませんでした。あとでもう一度受け取ります")
		return false
	end
	-- 届いたことを本人の画面に知らせる(ホームで品やコインを見せる)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		if result == "granted" then
			event:FireClient(player, "granted", ids, coins)
		end
	end
	return true, result
end

-- Roblox から届いた購入(コインの袋)
function Shop.processReceipt(info)
	local entry = Shop.byProduct[info.ProductId]
	if not entry or type(info.PlayerId) ~= "number" or type(info.PurchaseId) ~= "string" then
		-- 知らない製品: 渡さずに残しておく(設定を直せば、次に届いた時に渡せる)
		warn("[Shop] 知らない製品の購入です: " .. tostring(info.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- 支払いが済んだ購入は、必ず渡す(画面を出す前に地域の決まりは確かめている)
	if not Shop.grant(info.PlayerId, "p:" .. info.PurchaseId, {}, entry.coins + entry.bonus) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- VIP 会員(サブスクリプション)かどうかを Roblox に聞く。会員なら true、違えば false、聞けなかった時は nil
function Shop.subscribed(player: Player): boolean?
	-- Studio の検証用: プレイヤーの属性 MinatoTestVip(true / false)で、会員の状態をまねる
	if RunService:IsStudio() then
		local test = player:GetAttribute("MinatoTestVip")
		if type(test) == "boolean" then
			return test
		end
	end
	local id = Config.vip.subscription
	if type(id) ~= "string" or id == "" then
		-- まだ作っていない: だれも会員ではない
		return false
	end
	local ok, status = pcall(MarketplaceService.GetUserSubscriptionStatusAsync, MarketplaceService, player, id)
	if not ok or type(status) ~= "table" then
		return nil
	end
	return status.IsSubscribed == true
end

-- VIP 会員かどうかを確かめて保存し、特典を渡す(何度呼んでもよい)。
--   ・会員: 初めての時だけのコイン(一人1回)と、毎日のボーナス(その日に1回)
--   ・会員でない: 印を外し、着ていた VIP の品をスタンダードに戻す
-- 同じ日・同じ状態なら保存しない(確かめ終えた人と、その時の状態を覚えておく)
local checked: { [Player]: { day: string, vip: boolean } } = {}
function Shop.checkVip(player: Player, force: boolean?)
	local isVip = Shop.subscribed(player)
	if isVip == nil then
		return
	end
	local today = Meta.today()
	local last = checked[player]
	if not force and last and last.vip == isVip and last.day == today then
		return
	end
	local ok, meta = pcall(Service.setVip, player.UserId, isVip)
	if not ok or meta == nil then
		warn("[Shop] VIP 会員の印を保存できませんでした。あとでもう一度確かめます")
		return
	end
	player:SetAttribute("MinatoVip", isVip)
	if isVip and Shop.coinsAllowed(player) then
		local vip = Config.vip
		local received = type(meta.receipts) == "table" and table.find(meta.receipts, "sub:welcome") ~= nil
		if
			vip.welcomeCoins > 0
			and not received
			and not Shop.grant(player.UserId, "sub:welcome", {}, vip.welcomeCoins)
		then
			return
		end
		local ok2, saved = pcall(Service.vipDaily, player.UserId, vip.dailyCoins, today)
		if not (ok2 and saved) then
			return
		end
	end
	checked[player] = { day = today, vip = isVip }
end

-- 会場のサーバー用: VIP の品を着ている人(会員の印がある人)が、今も会員かを確かめる。
-- 切れていたら印を外して保存し、VIP の品を外した持ち物を返す(招待から直接会場に来た人も、ここで外れる)
function Shop.ensureVip(player: Player, meta: any): any
	if type(meta) ~= "table" or meta.vip ~= true then
		return meta
	end
	local isVip = Shop.subscribed(player)
	if isVip ~= false then
		return meta
	end
	local ok, saved = pcall(Service.setVip, player.UserId, false)
	player:SetAttribute("MinatoVip", false)
	if ok and saved then
		return saved
	end
	-- 保存できなくても、このレースでは VIP の品を着せない
	local copy = Meta.clone(meta)
	Meta.setVip(copy, false)
	return copy
end

-- 画面から「この袋を買いたい」: 番号と地域の決まりを確かめてから、Roblox の購入画面を出す
local last: { [Player]: number } = {}
local function onShopEvent(player: Player, action: unknown, key: unknown)
	if action ~= "buy" or type(key) ~= "string" or #key > 8 then
		return
	end
	if last[player] and os.clock() - last[player] < 1 then
		return
	end
	last[player] = os.clock()
	local entry = Shop.byKey[key]
	if not entry or entry.product <= 0 then
		event:FireClient(player, "notice", "この品は準備中です")
		return
	end
	if not Shop.coinsAllowed(player) then
		event:FireClient(player, "notice", "お住まいの地域の決まりで、コインは買えません")
		return
	end
	local ok = pcall(MarketplaceService.PromptProductPurchase, MarketplaceService, player, entry.product)
	if not ok then
		event:FireClient(player, "notice", "購入の画面を開けませんでした")
	end
end

function Shop.start()
	MarketplaceService.ProcessReceipt = Shop.processReceipt
	event.OnServerEvent:Connect(onShopEvent)
	local function joined(player: Player)
		task.spawn(function()
			Shop.coinsAllowed(player)
			Shop.checkVip(player)
		end)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		allowed[player] = nil
		last[player] = nil
		checked[player] = nil
	end)
	-- その場で VIP 会員になった時・会員の状態が変わった時(番号を確かめてから、Roblox に聞き直す)
	local function changed(player: Player, subscriptionId: unknown)
		if subscriptionId == Config.vip.subscription and Config.vip.subscription ~= "" then
			Shop.checkVip(player, true)
		end
	end
	pcall(function()
		MarketplaceService.PromptSubscriptionPurchaseFinished:Connect(function(player, subscriptionId, didTry)
			if didTry then
				changed(player, subscriptionId)
			end
		end)
	end)
	pcall(function()
		Players.UserSubscriptionStatusChanged:Connect(changed)
	end)
	-- ロビーに長くいる人も、10分ごとに会員かを確かめ直す(切れたら VIP の品を外す。
	-- 日付が変わったら毎日のボーナスも届く。同じ日・同じ状態なら保存はしない)
	task.spawn(function()
		while true do
			task.wait(600)
			for _, player in Players:GetPlayers() do
				task.spawn(Shop.checkVip, player)
			end
		end
	end)
	-- Studio の検証用: 属性 MinatoTestVip を変えたら、すぐ確かめ直す
	if RunService:IsStudio() then
		local function watch(player: Player)
			player:GetAttributeChangedSignal("MinatoTestVip"):Connect(function()
				Shop.checkVip(player, true)
			end)
		end
		Players.PlayerAdded:Connect(watch)
		for _, player in Players:GetPlayers() do
			watch(player)
		end
	end
end

return Shop
