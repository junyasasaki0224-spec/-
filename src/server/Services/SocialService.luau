--!strict
-- なかま(同じサーバーの人・友達とのやりとり)。
-- ・スタンプ: 決まった定型文だけ(自由な文字は送れない。文言は見る人の言語で表示される)。頭の上に少し出る
-- ・公開する情報: 対戦の点数・勝ち数・図鑑の数・称号・対戦中か・申し込みを受けるか だけを Player の属性に載せる
--   (名前は Roblox の表示名を使う)
-- ・水槽を見に行く: 相手の釣り小屋の前へ移動する
-- チャットは Roblox の標準チャット(Roblox が文字を検閲する)をそのまま使う。このゲーム独自の文字のやりとりは作らない。
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local RemoteGuard = require(script.Parent.RemoteGuard)

local O = Config.Online

local SocialService = {}
local S: any

local function setAttr(player: Player, key: string, value: any)
	if player:GetAttribute(key) ~= value then
		player:SetAttribute(key, value)
	end
end

-- 一覧に出す情報(ゲームの進み具合だけ)
local function publish(player: Player)
	local data = S.Data.get(player)
	if not data then
		return
	end
	local codex = 0
	for _ in data.codex do
		codex += 1
	end
	setAttr(player, "PvpRating", data.pvp.rating)
	setAttr(player, "PvpWins", data.pvp.wins)
	setAttr(player, "Codex", codex)
	setAttr(player, "TitleId", data.activeTitle)
	setAttr(player, "RodTier", data.rodTier)
	-- 一覧で「対戦中」「申し込みを受け付けていない」を先に見せる(押してから断られないように)
	setAttr(player, "InBattle", S.Battle.inBattle(player) or S.Raid.inRoom(player))
	setAttr(player, "ChallengePref", data.settings.challenges or "all")
end

SocialService.publish = publish

local handlers: { [string]: (Player, any, any) -> () } = {}

-- 相手の釣り小屋の前へ
handlers.visitTank = function(player, _data, payload)
	if not RemoteGuard.isInt(payload, 1, 1e12) or S.Battle.inBattle(player) then
		return
	end
	local target = Players:GetPlayerByUserId(payload)
	local hut: Model? = if target then S.Aquarium.hutOf(target) else nil
	local floor = if hut then hut:FindFirstChild("Floor") else nil
	local char = player.Character
	if not floor or not floor:IsA("BasePart") or not char then
		S.notify(player, "social_no_hut")
		return
	end
	S.Fishing.cancel(player)
	-- 小屋の正面(-Z、湖の側)に、小屋の方を向いて立たせる
	local cf = (floor :: BasePart).CFrame
	local front = cf * CFrame.new(0, 3.5, -10)
	local look = Vector3.new(cf.Position.X, front.Position.Y, cf.Position.Z)
	local body = char :: Model
	body:PivotTo(CFrame.lookAt(front.Position, look))
end

function SocialService.handleRequest(player: Player, action: string, payload: any): boolean
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

function SocialService.init(registry: any)
	S = registry
end

function SocialService.start()
	-- 人数の上限(重くならないように)。ゲーム設定の最大人数がずれていたら知らせる
	local max = (Players :: any).MaxPlayers
	if type(max) == "number" and max > O.MaxPlayers then
		warn(
			("[Online] 最大プレイヤー数が %d 人です。%d 人にしてください(ゲーム設定 → 場所)"):format(
				max,
				O.MaxPlayers
			)
		)
	end
	local shown = Remotes.event("StampShown")
	RemoteGuard.connect(Remotes.event("Stamp"), 0.7, 2, function(player, id)
		if type(id) ~= "string" or not table.find(O.Stamps, id) or not S.Data.isLoaded(player) then
			return
		end
		shown:FireAllClients(player.UserId, id)
	end)
	S.Data.Loaded:Connect(publish)
	task.spawn(function()
		while true do
			task.wait(3)
			for _, p in Players:GetPlayers() do
				pcall(publish, p)
			end
		end
	end)
end

return SocialService
