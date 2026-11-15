local Lighting = game:GetService("Lighting")
local Rules = require(script.Parent.WaterRules)
local Water = {}
local rgb = Color3.fromRGB
-- 時間帯ごとの見た目。水は深い色・不透明にして空を強く映す(明るい水色だとプールのように見えるため)
local scenes = {
    day = {hour=14, sun=2.7, ambient=rgb(104,117,127), outdoor=rgb(150,168,187),
        horizon=rgb(180,211,236), decay=rgb(92,127,155), tint=rgb(255,251,246),
        water=rgb(10,64,62), reflection=.7, bloom=.14, lamp=0,
        density=.3, haze=1.2, cover=.58, cloud=rgb(255,255,255), exposure=0},
    evening = {hour=17.55, sun=2.2, ambient=rgb(112,96,104), outdoor=rgb(168,140,146),
        horizon=rgb(250,170,108), decay=rgb(130,104,138), tint=rgb(255,232,212),
        water=rgb(34,46,66), reflection=.82, bloom=.26, lamp=.45,
        density=.32, haze=1.6, cover=.5, cloud=rgb(255,206,170), exposure=.05},
    -- ナイターは照明で明るい会場にする(空は暗く、水は自分の色を見せる)
    night = {hour=20.5, sun=3, ambient=rgb(110,124,160), outdoor=rgb(150,168,214),
        horizon=rgb(70,88,140), decay=rgb(30,40,76), tint=rgb(228,238,255),
        water=rgb(20,58,86), reflection=.28, bloom=.42, lamp=1,
        density=.26, haze=.4, cover=.32, cloud=rgb(46,56,84), exposure=.6},
}

function Water.fill()
    -- Four-stud voxel boundaries, top at zero. Include the western pit inlet only.
    local terrain = workspace.Terrain
    terrain:FillBlock(CFrame.new(-18,-8,-34), Vector3.new(1804,16,480), Enum.Material.Water)
    terrain:FillBlock(CFrame.new(-964,-8,40), Vector3.new(88,16,232), Enum.Material.Water)
end

local function effect(class)
    local obj = Lighting:FindFirstChildOfClass(class)
    if not obj then
        obj = Instance.new(class)
        obj.Parent = Lighting
    end
    return obj
end

function Water.configure(venue)
    local terrain = workspace.Terrain
    local air, sky = effect("Atmosphere"), effect("Sky")
    local bloom, grade, rays = effect("BloomEffect"), effect("ColorCorrectionEffect"), effect("SunRaysEffect")
    local panels, lights = {}, {}
    if venue then
        for _, part in venue:GetDescendants() do
            if part:IsA("MeshPart") and part.Name:find("__Lamp__", 1, true) then
                table.insert(panels, part)
            end
        end
        -- Pools of floodlight at the water's edge below four far-bank towers.
        -- The imported lamp faces above remain the visible light sources.
        for _, x in {-215,-75,95,215} do
            local anchor = Instance.new("Attachment")
            anchor.Position = Vector3.new(x,3,-78) * 3.5
            anchor.Parent = terrain
            local light = Instance.new("PointLight")
            light.Name = "QuayFlood"
            light.Range = 58
            light.Color = rgb(255,234,199)
            light.Shadows = false
            light.Parent = anchor
            table.insert(lights, light)
            venue.Destroying:Once(function() anchor:Destroy() end)
        end
    end
    return function(name, wave)
        local e = scenes[name] or scenes.day
        terrain.WaterColor, terrain.WaterReflectance, terrain.WaterTransparency = e.water, e.reflection, 0
        -- 雲(地形の Clouds)で空に奥行きを出す
        local clouds = terrain:FindFirstChildOfClass("Clouds")
        if not clouds then
            clouds = Instance.new("Clouds")
            clouds.Parent = terrain
        end
        clouds.Cover, clouds.Density, clouds.Color = e.cover, .5, e.cloud
        Lighting.ExposureCompensation = e.exposure
        terrain.WaterWaveSize, terrain.WaterWaveSpeed = Rules.wave(wave)
        Lighting.GlobalShadows = true
        Lighting.ClockTime, Lighting.Brightness = e.hour, e.sun
        Lighting.Ambient, Lighting.OutdoorAmbient = e.ambient, e.outdoor
        Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = .65, 1
        air.Density, air.Haze, air.Glare, air.Color, air.Decay = e.density, e.haze, .12, e.horizon, e.decay
        sky.StarCount = name == "night" and 1200 or 0
        bloom.Intensity, bloom.Size, bloom.Threshold = e.bloom, 22, .92
        grade.TintColor, grade.Contrast, grade.Saturation = e.tint, .035, .035
        rays.Intensity = name == "night" and 0 or .035
        for _, panel in panels do
            panel.Material = e.lamp > 0 and Enum.Material.Neon or Enum.Material.SmoothPlastic
        end
        for _, light in lights do
            light.Enabled, light.Brightness = e.lamp > 0, 2.4 * e.lamp
        end
    end
end

return Water
