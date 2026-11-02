--!strict
-- 光と空気感の基本設定(時間帯・天気による変化はクライアントの LightingController が行う)
local Lighting = game:GetService("Lighting")

local M = {}

local function get(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function M.setup()
	Lighting.Ambient = Color3.fromRGB(70, 70, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 125, 140)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 240, 220)
	Lighting.ShadowSoftness = 0.3
	Lighting.GeographicLatitude = 35 -- 日本

	local atm = get("Atmosphere", "Atmosphere") :: Atmosphere
	atm.Density = 0.32
	atm.Offset = 0.12
	atm.Color = Color3.fromRGB(199, 214, 222)
	atm.Decay = Color3.fromRGB(92, 110, 128)
	atm.Glare = 0.2
	atm.Haze = 1.4

	local bloom = get("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 28
	bloom.Threshold = 1.6

	local cc = get("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Saturation = 0.08
	cc.Contrast = 0.06
	cc.TintColor = Color3.fromRGB(255, 250, 244)

	local rays = get("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.6

	local sky = get("Sky", "Sky") :: Sky
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 14
	sky.SunAngularSize = 16
	sky.StarCount = 4000

	local terrain = workspace.Terrain
	terrain.WaterColor = Color3.fromRGB(46, 92, 84)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.6
	terrain.WaterWaveSize = 0.08
	terrain.WaterWaveSpeed = 6
	terrain:SetMaterialColor(Enum.Material.Grass, Color3.fromRGB(86, 120, 62))
	terrain:SetMaterialColor(Enum.Material.Mud, Color3.fromRGB(72, 60, 44))
	terrain:SetMaterialColor(Enum.Material.Rock, Color3.fromRGB(96, 98, 104))
	terrain:SetMaterialColor(Enum.Material.Ground, Color3.fromRGB(110, 92, 66))
	terrain:SetMaterialColor(Enum.Material.LeafyGrass, Color3.fromRGB(70, 108, 54))

	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.55
		clouds.Density = 0.6
		clouds.Color = Color3.fromRGB(240, 240, 245)
		clouds.Parent = terrain
	end
end

return M
