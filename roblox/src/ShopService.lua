-- ロビーのサーバー: Robux の購入を受け取って渡す(コインの袋は開発者製品、VIP はゲームパス)。
-- 守ること:
--   ・渡すのはサーバーだけ。プレイヤー側からの「買った」という知らせは信じない(Roblox の ProcessReceipt だけで渡す)
--   ・保存できた時だけ PurchaseGranted を返す。できなければ NotProcessedYet(Roblox があとでもう一度届ける)
--   ・同じ購入番号は1回だけ渡す(Meta.grantPurchase が購入番号を覚えている)
--   ・コインはガチャ(中身がランダム)に使うので、Roblox の決まりで買えない地域がある。
--     PolicyService で確かめ、買えない人にはコインの袋の購入画面を出さず、VIP のコインの特典も付けない
local MarketplaceService = game:GetService("MarketplaceService")
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
		if meta.vip then
			player:SetAttribute("MinatoVip", true)
		end
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

-- VIP パスを持っているか確かめて、特典を渡す(何度呼んでも1回だけ渡る)。
-- 毎日のボーナスもここで届ける(入った時と、日付が変わってから最初に確かめた時)。
-- 同じ日に何度も保存しないよう、その日に確かめ終えた人は覚えておく
local checkedDay: { [Player]: string } = {}
function Shop.checkVip(player: Player)
	local pass = Config.vip.pass
	local today = Meta.today()
	if pass <= 0 or checkedDay[player] == today then
		return
	end
	local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, pass)
	if not (ok and owns) then
		return
	end
	local coinsOk = Shop.coinsAllowed(player)
	if not Shop.grant(player.UserId, "pass:" .. pass, Config.vip.items, coinsOk and Config.vip.welcomeCoins or 0) then
		return
	end
	if coinsOk then
		local ok2, saved = pcall(Service.vipDaily, player.UserId, Config.vip.dailyCoins, today)
		if not (ok2 and saved) then
			return
		end
	end
	checkedDay[player] = today
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
		checkedDay[player] = nil
	end)
	-- その場で VIP パスを買った時(番号を確かめてから、持っているかを Roblox に聞き直す)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.vip.pass then
			checkedDay[player] = nil
			Shop.checkVip(player)
		end
	end)
	-- ロビーに長くいる人にも、日付が変わったら VIP の毎日のボーナスを届ける(1日1回だけ届く)
	task.spawn(function()
		while true do
			task.wait(600)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("MinatoVip") then
					task.spawn(Shop.checkVip, player)
				end
			end
		end
	end)
end

return Shop
