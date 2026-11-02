--!strict
-- 時間帯と天気の見た目。サーバー時刻から全員同じ値を計算するので通信は不要。
--   朝: 霞んだ金色 / 昼: 澄んだ空 / 夜: 青い月明かり + 灯籠と蛍
--   雨: 雨粒と暗い空 / 霧: 濃い霧 / 雷: 雨 + ときどき稲光
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local WorldClock = require(Shared.Lib.WorldClock)

local Notify = require(script.Parent.Notify)

local W = Config.Tuning.World

local LightingFX = {}

type Look = {
	density: number,
	haze: number,
	color: Color3,
	decay: Color3,
	ambient: Color3,
	outdoor: Color3,
	brightness: number,
	tint: Color3,
}

local PHASE: { [string]: Look } = {
	morning = {
		density = 0.38,
		haze = 2.2,
		color = Color3.fromRGB(255, 214, 180),
		decay = Color3.fromRGB(180, 140, 120),
		ambient = Color3.fromRGB(90, 80, 90),
		outdoor = Color3.fromRGB(150, 130, 130),
		brightness = 2.0,
		tint = Color3.fromRGB(255, 240, 225),
	},
	day = {
		density = 0.28,
		haze = 1.2,
		color = Color3.fromRGB(199, 214, 222),
		decay = Color3.fromRGB(92, 110, 128),
		ambient = Color3.fromRGB(80, 82, 96),
		outdoor = Color3.fromRGB(130, 135, 145),
		brightness = 2.4,
		tint = Color3.fromRGB(255, 252, 246),
	},
	night = {
		density = 0.36,
		haze = 1.6,
		color = Color3.fromRGB(70, 90, 140),
		decay = Color3.fromRGB(30, 40, 80),
		ambient = Color3.fromRGB(40, 46, 80),
		outdoor = Color3.fromRGB(60, 70, 120),
		brightness = 1.2,
		tint = Color3.fromRGB(200, 215, 255),
	},
}

local WEATHER_DENSITY = { sunny = 0, rain = 0.12, fog = 0.3, thunder = 0.16 }
local WEATHER_DARK = { sunny = 1, rain = 0.75, fog = 0.85, thunder = 0.6 }

local rainPart: Part
local rainEmitter: ParticleEmitter
local lastWeather = ""
local lastPhase = ""
local nextThunder = 0

local function setNightFX(on: boolean)
	for _, pe in CollectionService:GetTagged("NightFX") do
		if pe:IsA("ParticleEmitter") then
			pe.Enabled = on
		end
	end
	for _, l in CollectionService:GetTagged("NightLight") do
		if l:IsA("Light") then
			l.Enabled = on
		end
	end
end

local function thunderFlash()
	local cc = Lighting:FindFirstChild("Grade") :: ColorCorrectionEffect?
	if not cc then
		return
	end
	cc.Brightness = 0.5
	TweenService:Create(cc, TweenInfo.new(0.5), { Brightness = 0 }):Play()
end

function LightingFX.init()
	rainPart = Instance.new("Part")
	rainPart.Name = "RainEmitter"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(80, 1, 80)
	rainPart.Parent = workspace
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(190, 210, 230))
	rainEmitter.Transparency = NumberSequence.new(0.45)
	rainEmitter.Size = NumberSequence.new(0.08)
	rainEmitter.Squash = NumberSequence.new(-3)
	rainEmitter.Lifetime = NumberRange.new(0.9, 1.1)
	rainEmitter.Speed = NumberRange.new(60, 70)
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.Rate = 0
	rainEmitter.LightInfluence = 1
	rainEmitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	rainEmitter.Parent = rainPart

	local atm = Lighting:WaitForChild("Atmosphere", 10) :: Atmosphere?
	local grade = Lighting:WaitForChild("Grade", 10) :: ColorCorrectionEffect?
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		local clock = WorldClock.clockTime(now, W)
		Lighting.ClockTime = clock
		local cam = workspace.CurrentCamera
		if cam then
			rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 35, 0))
		end
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		local phase = WorldClock.phase(clock, W)
		local weather = WorldClock.weatherAt(now, W)
		local look = PHASE[phase]
		local dark = WEATHER_DARK[weather] or 1
		local tween = TweenInfo.new(3)
		if atm then
			TweenService:Create(atm, tween, {
				Density = math.clamp(look.density + (WEATHER_DENSITY[weather] or 0), 0, 0.8),
				Haze = look.haze + (if weather == "fog" then 2 else 0),
				Color = look.color:Lerp(Color3.fromRGB(150, 155, 165), 1 - dark),
				Decay = look.decay,
			}):Play()
		end
		TweenService:Create(Lighting, tween, {
			Ambient = look.ambient,
			OutdoorAmbient = look.outdoor:Lerp(Color3.fromRGB(70, 74, 86), 1 - dark),
			Brightness = look.brightness * dark,
		}):Play()
		if grade then
			TweenService:Create(
				grade,
				tween,
				{ TintColor = look.tint, Saturation = if weather == "sunny" then 0.1 else -0.05 }
			):Play()
		end
		rainEmitter.Rate = if weather == "rain" then 700 elseif weather == "thunder" then 1000 else 0
		if weather == "thunder" and os.clock() > nextThunder then
			nextThunder = os.clock() + math.random(6, 16)
			thunderFlash()
		end
		if phase ~= lastPhase then
			lastPhase = phase
			setNightFX(phase == "night" or weather == "rain" or weather == "thunder")
		end
		if weather ~= lastWeather then
			if lastWeather ~= "" then
				Notify.key("notify_weather", { weather = weather })
			end
			lastWeather = weather
			setNightFX(phase == "night" or weather == "rain" or weather == "thunder")
		end
	end)
	-- 後から生成されたものにも反映
	CollectionService:GetInstanceAddedSignal("NightLight"):Connect(function()
		lastPhase = ""
	end)
end

return LightingFX
