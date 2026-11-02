--!strict
-- サーバーの起動スクリプト。
-- 1) 設定データの検査 2) 通信の作成 3) ワールド生成 4) 各サービスの init → start
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)

local Services = script.Services
local RemoteGuard = require(Services.RemoteGuard)

-- 1) データの整合性チェック(問題があれば Output に表示。ゲームは止めない)
local problems = Config.Validate()
for _, p in problems do
	warn("[Config] " .. p)
end
if #problems == 0 then
	print(("[Config] OK: %d fish, %d spots"):format(#Config.Fish, #Config.Spots))
end

-- 2) 通信
Remotes.setupServer()

-- 3) ワールド(地形・建物・光)
require(script.World.Lighting).setup()
require(script.World.Swamp).build()
require(script.World.Village).build()

-- 4) サービス
local S = {
	Data = require(Services.DataService),
	World = require(Services.WorldService),
	Analytics = require(Services.Analytics),
	Monetization = require(Services.MonetizationService),
	Fishing = require(Services.FishingService),
	Shop = require(Services.ShopService),
	Quest = require(Services.QuestService),
	Leaderboard = require(Services.LeaderboardService),
	Aquarium = require(Services.AquariumService),
	Nushi = require(Services.NushiService),
	notify = nil :: any,
	announce = nil :: any,
}

local notifyRemote = Remotes.event("Notify")
local announceRemote = Remotes.event("Announce")

-- 文言はクライアントで翻訳する。args の値は数値か、翻訳キー("...Key")か、短い文字列のみ
function S.notify(player: Player, key: string, args: { [string]: any }?)
	if player.Parent == Players then
		notifyRemote:FireClient(player, key, args or {})
	end
end

function S.announce(key: string, args: { [string]: any }?)
	announceRemote:FireAllClients(key, args or {})
end

local ORDER = {
	"Data",
	"World",
	"Analytics",
	"Monetization",
	"Fishing",
	"Shop",
	"Quest",
	"Leaderboard",
	"Aquarium",
	"Nushi",
}
for _, name in ORDER do
	(S :: any)[name].init(S)
end
for _, name in ORDER do
	(S :: any)[name].start()
end

-- 店・設定などの操作はひとつの通信にまとめ、操作名で振り分ける
local REQUEST_HANDLERS: { any } = { S.Shop, S.Quest, S.Monetization }
RemoteGuard.connect(Remotes.event("Request"), 6, 12, function(player, action, payload)
	if not RemoteGuard.isId(action, 24) then
		return
	end
	if not S.Data.isLoaded(player) then
		return
	end
	-- payload は浅いテーブル・数値・文字列・真偽値のみ受け付ける
	local t = type(payload)
	if t == "string" and #payload > 64 then
		return
	end
	if t ~= "nil" and t ~= "string" and t ~= "number" and t ~= "boolean" and t ~= "table" then
		return
	end
	for _, svc in REQUEST_HANDLERS do
		if svc.handleRequest(player, action, payload) then
			return
		end
	end
end)

-- キャラクターの出現はワールド生成の後(生成前に出ると落下するため、自動出現を切っている)
local function spawnLoop(player: Player)
	player.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				task.wait(Players.RespawnTime)
				if player.Parent == Players then
					player:LoadCharacter()
				end
			end)
		end
	end)
	if not player.Character then
		player:LoadCharacter()
	end
end
Players.PlayerAdded:Connect(function(player)
	S.Analytics.onboarding(player, S.Analytics.Onboarding.Joined)
	spawnLoop(player)
end)
for _, p in Players:GetPlayers() do
	task.spawn(spawnLoop, p)
end

print("[YokaiFishing] server ready")
