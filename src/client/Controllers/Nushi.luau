--!strict
-- ぬし釣りの画面: 湖の近くで「参加」→ 引き上げゲージ(終わりなし)で、枠に入れた秒数がみんなの進み具合になる。
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local ReelGame = require(script.Parent.ReelGame)
local Fishing = require(script.Parent.Fishing)
local C = Theme.Colors

local NT = Config.Tuning.Nushi
local player = Players.LocalPlayer

local Nushi = {}
local bar: Frame
local fill: Frame
local label: TextLabel
local joinButton: TextButton
local game_: any = nil
local latest: any = { active = false }

local function lakeCenter(): Vector3
	local spot = Config.SpotById.nushi_lake
	return Vector3.new(spot.origin.x + spot.water.x, spot.origin.y, spot.origin.z + spot.water.z)
end

local function nearLake(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	local c = lakeCenter()
	return Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z).Magnitude <= NT.joinRadius - 4
end

local function stopGame()
	if game_ then
		game_:destroy()
		game_ = nil
	end
end

local function startGame()
	if game_ or not latest.active then
		return
	end
	Fishing.cancel()
	game_ = ReelGame.new(bar.Parent :: Instance, {
		rarity = "mythic",
		duration = 6,
		fishSpeed = 0.7,
		jitter = 1.6,
		tensionRate = 0.3,
		tensionDecay = 0.12,
		netSize = 0.28,
		reelSpeed = 1,
		startProgress = 0,
		seed = math.random(1, 1e6),
	}, "nushi", {})
end

local function refresh()
	local s = latest
	local show = s.active == true
	bar.Visible = show
	if show then
		local p = math.clamp(s.progress / math.max(1, s.required), 0, 1)
		fill.Size = UDim2.fromScale(p, 1)
		label.Text = Locale.t("nushi_progress", { p = math.floor(p * 100) })
			.. ("  ·  👥%d  ·  %s"):format(s.participants or 0, Format.time(s.remaining or 0))
	end
	joinButton.Visible = show and game_ == nil and nearLake()
	if game_ and (not show or not nearLake()) then
		stopGame()
	end
end

function Nushi.init(gui: ScreenGui)
	local bg, f = Kit.bar(gui, C.vermilion)
	bar = bg
	fill = f
	bar.Size = UDim2.fromOffset(520, 26)
	bar.Position = UDim2.new(0.5, 0, 0, 138)
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Visible = false
	Kit.stroke(bar, C.goldLight, 2)
	label = Kit.label({
		Size = UDim2.new(1, -16, 1, -4),
		Position = UDim2.fromOffset(8, 2),
		MaxTextSize = 18,
		ZIndex = 3,
		Parent = bar,
	})
	Kit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Parent = label })

	joinButton = Kit.button({
		Text = Locale.t("nushi_join"),
		Size = UDim2.fromOffset(260, 60),
		Position = UDim2.new(0.5, 0, 1, -130),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.vermilion,
		MaxTextSize = 26,
		Parent = gui,
	}, startGame)
	joinButton.Visible = false

	Remotes.event("NushiState").OnClientEvent:Connect(function(s)
		if type(s) == "table" then
			latest = s
			refresh()
		end
	end)
	local reelRemote = Remotes.event("NushiReel")
	task.spawn(function()
		while true do
			task.wait(0.5)
			if game_ then
				reelRemote:FireServer(game_:takeZoneSeconds())
			end
			refresh()
		end
	end)
end

return Nushi
