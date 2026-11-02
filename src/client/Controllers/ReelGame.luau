--!strict
-- 引き上げのミニゲーム。縦のゲージの中を魚が動き、押している間だけ網の枠が上がる。
-- 魚が枠の中: 巻き取りが進む / 枠の外: 糸の張りがたまる。
-- mode = "catch": 巻き取り満タンで成功、張り満タンで失敗
-- mode = "nushi": 終わりなし。枠に入っていた秒数を onZone で通知し続ける(ぬし釣り)
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Input = require(script.Parent.Input)
local C = Theme.Colors

local ReelGame = {}
ReelGame.__index = ReelGame

export type Params = {
	rarity: string,
	duration: number,
	fishSpeed: number,
	jitter: number,
	tensionRate: number,
	tensionDecay: number,
	netSize: number,
	reelSpeed: number,
	startProgress: number,
	seed: number,
	mutationHint: boolean?,
}

local GAUGE_H = 380

function ReelGame.new(
	parent: Instance,
	params: Params,
	mode: string,
	callbacks: { onFinish: ((boolean) -> ())?, onZone: ((number) -> ())? }
)
	local self = setmetatable({}, ReelGame) :: any
	self.params = params
	self.mode = mode
	self.callbacks = callbacks
	self.rng = Random.new(params.seed)
	self.net = 0.0 -- 網の下端(0..1-netSize)
	self.netVel = 0.0
	self.fish = 0.5
	self.fishTarget = 0.5
	self.retarget = 0.0
	self.progress = params.startProgress
	self.tension = 0.0
	self.done = false
	self.zoneAccum = 0.0
	self.stun = 0.0

	local rarity = Config.RarityById[params.rarity]
	local rarityColor = if rarity then Color3.fromHex(rarity.color) else C.gold

	local root = Kit.new("Frame", {
		Name = "ReelGame",
		Size = UDim2.fromOffset(170, GAUGE_H + 70),
		Position = UDim2.new(1, -40, 0.5, -10),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	self.root = root

	-- レア度の気配
	local hint = Kit.label({
		Size = UDim2.new(1, 40, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = if rarity
			then Locale.t("rarity_" .. rarity.id) .. (if params.mutationHint then " ✦" else "")
			else "",
		TextColor3 = rarityColor,
		Font = Theme.Fonts.title,
		MaxTextSize = 26,
		Parent = root,
	})
	Kit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Parent = hint })

	local gauge = Kit.new("Frame", {
		Name = "Gauge",
		Size = UDim2.fromOffset(74, GAUGE_H),
		Position = UDim2.new(0.5, 0, 0, 40),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.water,
		ClipsDescendants = true,
		Parent = root,
	})
	Kit.corner(gauge, UDim.new(0, 18))
	Kit.stroke(gauge, rarityColor, 3)
	Kit.gradient(gauge, Color3.fromRGB(80, 160, 190), C.waterDeep)
	-- 泡の模様
	for i = 1, 6 do
		local b = Kit.new("Frame", {
			Size = UDim2.fromOffset(6 + i % 3 * 3, 6 + i % 3 * 3),
			Position = UDim2.fromScale(0.2 + (i % 3) * 0.28, i / 7),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.8,
			Parent = gauge,
		})
		Kit.corner(b, UDim.new(1, 0))
	end

	local net = Kit.new("Frame", {
		Name = "Net",
		Size = UDim2.new(1, -8, params.netSize, 0),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.goldLight,
		BackgroundTransparency = 0.55,
		Parent = gauge,
	})
	Kit.corner(net, UDim.new(0, 12))
	local netStroke = Kit.stroke(net, C.goldLight, 3)
	self.netFrame = net
	self.netStroke = netStroke

	local fishIcon = Kit.new("TextLabel", {
		Name = "Fish",
		Size = UDim2.fromOffset(46, 46),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = rarityColor,
		Text = "🐟",
		TextScaled = true,
		Font = Theme.Fonts.title,
		ZIndex = 3,
		Parent = gauge,
	})
	Kit.corner(fishIcon, UDim.new(1, 0))
	Kit.stroke(fishIcon, Color3.new(1, 1, 1), 2)
	self.fishIcon = fishIcon

	-- 巻き取り(左)と糸の張り(右)
	local function vbar(x: number, color: Color3): Frame
		local bg = Kit.new("Frame", {
			Size = UDim2.fromOffset(16, GAUGE_H),
			Position = UDim2.new(0.5, x, 0, 40),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = C.panelDark,
			Parent = root,
		})
		Kit.corner(bg, UDim.new(1, 0))
		Kit.stroke(bg, C.gold, 1, 0.4)
		local fill = Kit.new("Frame", {
			Size = UDim2.fromScale(1, 0),
			Position = UDim2.fromScale(0, 1),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = color,
			Parent = bg,
		})
		Kit.corner(fill, UDim.new(1, 0))
		return fill
	end
	self.progressFill = vbar(-58, C.success)
	self.tensionFill = vbar(58, C.danger)
	Kit.label({
		Size = UDim2.fromOffset(44, 22),
		Position = UDim2.new(0.5, -58, 0, GAUGE_H + 44),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = Locale.t("reel_progress"),
		TextColor3 = C.success,
		Parent = root,
	})
	Kit.label({
		Size = UDim2.fromOffset(44, 22),
		Position = UDim2.new(0.5, 58, 0, GAUGE_H + 44),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = Locale.t("reel_tension"),
		TextColor3 = C.danger,
		Parent = root,
	})

	local s = Kit.new("UIScale", { Scale = 0.3, Parent = root })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	self.conn = RunService.RenderStepped:Connect(function(dt)
		self:step(math.min(dt, 0.05))
	end)
	return self
end

function ReelGame:step(dt: number)
	if self.done then
		return
	end
	local p = self.params
	local holding = Input.isHolding() and self.stun <= 0
	if self.stun > 0 then
		self.stun -= dt
	end

	-- 網: 押すと上向きの力、離すと落ちる
	local accel = if holding then 3.2 else -2.6
	self.netVel = math.clamp(self.netVel + accel * dt, -1.4, 1.4)
	self.net += self.netVel * dt
	local maxNet = 1 - p.netSize
	if self.net < 0 then
		self.net = 0
		self.netVel = math.abs(self.netVel) * 0.25
	elseif self.net > maxNet then
		self.net = maxNet
		self.netVel = -math.abs(self.netVel) * 0.25
	end

	-- 魚: ときどき目標を変えて泳ぐ
	self.retarget -= dt
	if self.retarget <= 0 then
		self.retarget = (1 / p.jitter) * self.rng:NextNumber(0.6, 1.4)
		local range = 0.25 + p.fishSpeed * 0.6
		self.fishTarget = math.clamp(self.fish + self.rng:NextNumber(-range, range), 0.04, 0.96)
		-- レアほどたまに急に跳ねる
		if self.rng:NextNumber() < p.fishSpeed * 0.25 then
			self.fishTarget = self.rng:NextNumber(0.05, 0.95)
		end
	end
	local diff = self.fishTarget - self.fish
	local maxMove = p.fishSpeed * dt
	self.fish += math.clamp(diff * 3 * dt, -maxMove, maxMove)

	local inZone = self.fish >= self.net and self.fish <= self.net + p.netSize
	if inZone then
		self.progress += dt / p.duration * p.reelSpeed
		self.tension = math.max(0, self.tension - p.tensionDecay * dt)
		self.zoneAccum += dt
	else
		self.progress = math.max(0, self.progress - dt * 0.06)
		self.tension += p.tensionRate * dt
	end

	-- 表示
	self.netFrame.Position = UDim2.new(0.5, 0, 1 - self.net, 0)
	self.netStroke.Color = if inZone then C.success else C.goldLight
	self.fishIcon.Position = UDim2.fromScale(0.5, 1 - self.fish)
	self.fishIcon.Rotation = math.sin(os.clock() * 14) * (if inZone then 8 else 22)
	self.progressFill.Size = UDim2.fromScale(1, math.clamp(self.progress, 0, 1))
	self.tensionFill.Size = UDim2.fromScale(1, math.clamp(self.tension, 0, 1))

	if self.mode == "nushi" then
		if self.tension >= 1 then
			self.tension = 0
			self.stun = 1.5
		end
		if self.progress >= 1 then
			self.progress = p.startProgress
		end
		return
	end
	if self.progress >= 1 then
		self:finish(true)
	elseif self.tension >= 1 then
		self:finish(false)
	end
end

-- ぬし釣り用: たまった「枠の中の秒数」を取り出す
function ReelGame:takeZoneSeconds(): number
	local z = self.zoneAccum
	self.zoneAccum = 0
	return z
end

function ReelGame:finish(success: boolean)
	if self.done then
		return
	end
	self.done = true
	if self.callbacks.onFinish then
		self.callbacks.onFinish(success)
	end
	self:destroy()
end

function ReelGame:destroy()
	self.done = true
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if self.root then
		local root = self.root
		self.root = nil
		local s = root:FindFirstChildOfClass("UIScale")
		if s then
			TweenService:Create(s, TweenInfo.new(0.15), { Scale = 0 }):Play()
		end
		task.delay(0.16, function()
			root:Destroy()
		end)
	end
end

return ReelGame
