--!strict
-- 釣り上げた時の結果表示。レアほど派手に(光の放射・画面フラッシュ・紙吹雪)。
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)
local FishBuilder = require(Shared.Lib.FishBuilder)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local Result = {}
local closedSignal = Instance.new("BindableEvent")
Result.Closed = closedSignal.Event -- (result)

local gui: ScreenGui
local current: Frame? = nil
local queue: { any } = {}

local function burst(parent: Frame, color: Color3)
	-- 放射状の光
	local rays = Kit.new("Frame", {
		Size = UDim2.fromOffset(640, 640),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 0,
		Parent = parent,
	})
	for i = 0, 11 do
		local ray = Kit.new("Frame", {
			Size = UDim2.fromOffset(46, 320),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 1),
			Rotation = i * 30,
			BackgroundColor3 = color,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			Parent = rays,
		})
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0.2),
			}),
			Rotation = 90,
			Parent = ray,
		})
		-- 回転の中心をパネル中央にするため、親を回す
	end
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		if not rays.Parent then
			conn:Disconnect()
			return
		end
		rays.Rotation += dt * 25
	end)
	-- 紙吹雪
	for _ = 1, 28 do
		local piece = Kit.new("Frame", {
			Size = UDim2.fromOffset(math.random(6, 12), math.random(10, 18)),
			Position = UDim2.new(0.5, math.random(-60, 60), 0.4, 0),
			BackgroundColor3 = if math.random() < 0.5 then color else C.goldLight,
			BorderSizePixel = 0,
			Rotation = math.random(0, 360),
			ZIndex = 5,
			Parent = parent,
		})
		local target = UDim2.new(0.5, math.random(-420, 420), 1.1, math.random(-100, 100))
		TweenService:Create(
			piece,
			TweenInfo.new(math.random(14, 26) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{
				Position = target,
				Rotation = piece.Rotation + math.random(-360, 360),
			}
		):Play()
	end
end

local function flash()
	local f = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.2,
		ZIndex = 50,
		Parent = gui,
	})
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	task.delay(0.65, function()
		f:Destroy()
	end)
end

local function showNext()
	if current or #queue == 0 then
		return
	end
	local r = table.remove(queue, 1)
	local fish = Config.FishById[r.fishId]
	if not fish then
		return
	end
	local rarity = Config.RarityById[fish.rarity]
	local rColor = Color3.fromHex(rarity.color)
	local fancy = rarity.order >= 3 or r.firstEver

	local overlay = Kit.new("TextButton", {
		Name = "Result",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 20,
		Parent = gui,
	})
	current = overlay
	if fancy then
		burst(overlay, rColor)
	end
	if rarity.order >= 5 then
		flash()
	end

	local card = Kit.new("Frame", {
		Size = UDim2.fromOffset(440, 470),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		ZIndex = 21,
		Parent = overlay,
	})
	Kit.corner(card, UDim.new(0, 22))
	Kit.stroke(card, rColor, 4)
	Kit.gradient(card, Color3.new(1, 1, 1), Color3.fromRGB(160, 160, 190))

	Kit.label({
		Size = UDim2.new(1, -40, 0, 34),
		Position = UDim2.fromOffset(20, 14),
		Text = Locale.t("fish_caught_title"),
		TextColor3 = C.goldLight,
		Font = Theme.Fonts.title,
		MaxTextSize = 30,
		ZIndex = 22,
		Parent = card,
	})

	local vpHolder = Kit.new("Frame", {
		Size = UDim2.new(1, -40, 0, 200),
		Position = UDim2.fromOffset(20, 54),
		BackgroundColor3 = C.waterDeep,
		ZIndex = 22,
		Parent = card,
	})
	Kit.corner(vpHolder, UDim.new(0, 16))
	Kit.gradient(vpHolder, Color3.fromRGB(70, 140, 170), C.waterDeep)
	local model = FishBuilder.build(fish, { mutation = r.mutation })
	local vpf = Kit.viewport(vpHolder, model, { ZIndex = 23 })
	local spin = 0
	local spinConn = RunService.RenderStepped:Connect(function(dt)
		spin += dt * 0.9
		model:PivotTo(CFrame.Angles(0, spin, math.sin(spin * 2) * 0.12))
	end)

	local badges = {}
	if r.isNew then
		table.insert(badges, { Locale.t("fish_new"), C.vermilion })
	end
	if r.isRecord then
		table.insert(badges, { Locale.t("fish_record"), C.jade })
	end
	for i, b in badges do
		local badge = Kit.label({
			Size = UDim2.fromOffset(150, 30),
			Position = UDim2.fromOffset(30, 62 + (i - 1) * 36),
			Text = b[1],
			BackgroundTransparency = 0,
			BackgroundColor3 = b[2],
			MaxTextSize = 20,
			ZIndex = 24,
			Parent = card,
		})
		Kit.corner(badge, UDim.new(1, 0))
		badge.Rotation = -6
	end

	local rarityLabel = Kit.label({
		Size = UDim2.new(1, -40, 0, 30),
		Position = UDim2.fromOffset(20, 262),
		Text = Locale.t("rarity_" .. rarity.id)
			.. (if r.mutation then "  ·  " .. Locale.t("mutation_" .. r.mutation) else ""),
		TextColor3 = rColor,
		Font = Theme.Fonts.title,
		MaxTextSize = 26,
		ZIndex = 22,
		Parent = card,
	})
	Kit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Parent = rarityLabel })
	Kit.label({
		Size = UDim2.new(1, -40, 0, 46),
		Position = UDim2.fromOffset(20, 294),
		Text = Locale.fishName(fish),
		TextColor3 = C.text,
		Font = Theme.Fonts.title,
		MaxTextSize = 40,
		ZIndex = 22,
		Parent = card,
	})
	Kit.label({
		Size = UDim2.new(1, -40, 0, 28),
		Position = UDim2.fromOffset(20, 344),
		Text = Format.kg(r.grams) .. "   ·   " .. Format.coins(r.price, Locale.get()) .. " " .. Locale.t(
			"coins"
		),
		TextColor3 = C.goldLight,
		MaxTextSize = 24,
		ZIndex = 22,
		Parent = card,
	})
	if r.autoSold then
		Kit.label({
			Size = UDim2.new(1, -40, 0, 24),
			Position = UDim2.fromOffset(20, 376),
			Text = Locale.t("fish_sold_auto", { coins = Format.coins(r.price, Locale.get()) }),
			TextColor3 = C.textDim,
			MaxTextSize = 18,
			ZIndex = 22,
			Parent = card,
		})
	end
	Kit.label({
		Size = UDim2.new(1, -40, 0, 40),
		Position = UDim2.fromOffset(20, 410),
		Text = Locale.fishDesc(fish),
		TextColor3 = C.textDim,
		Font = Theme.Fonts.body,
		MaxTextSize = 17,
		TextWrapped = true,
		ZIndex = 22,
		Parent = card,
	})

	local s = Kit.new("UIScale", { Scale = 0.4, Parent = card })
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Sound.play(if rarity.order >= 4 then "rare" else "catch", 0.7, if rarity.order >= 4 then 0.8 else 1)

	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		spinConn:Disconnect()
		TweenService:Create(s, TweenInfo.new(0.15), { Scale = 0 }):Play()
		task.delay(0.16, function()
			overlay:Destroy()
			vpf:Destroy()
			current = nil
			closedSignal:Fire(r)
			showNext()
		end)
	end
	overlay.Activated:Connect(close)
	task.delay(if fancy then 5 else 3, close)
end

function Result.show(r: any)
	table.insert(queue, r)
	showNext()
end

function Result.isShowing(): boolean
	return current ~= nil
end

function Result.init(g: ScreenGui)
	gui = g
	Remotes.event("CatchResult").OnClientEvent:Connect(function(r)
		if type(r) ~= "table" or type(r.fishId) ~= "string" then
			return
		end
		-- 自動釣り中の並・上は控えめに(通知だけ)
		local fish = Config.FishById[r.fishId]
		local auto = game:GetService("Players").LocalPlayer:GetAttribute("AutoFishing") == true
		if auto and fish and Config.RarityById[fish.rarity].order <= 2 and not r.isNew and not r.mutation then
			local Notify = require(script.Parent.Notify)
			Notify.show(("%s  %s"):format(Locale.fishName(fish), Format.kg(r.grams)), C.textDim, 2)
			return
		end
		Result.show(r)
	end)
end

return Result
