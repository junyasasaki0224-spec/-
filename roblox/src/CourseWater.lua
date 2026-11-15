local Lighting = game:GetService("Lighting")
local Rules = require(script.Parent.WaterRules)
local Water = {}
local rgb = Color3.fromRGB
local scenes = {
    day = {hour=14, sun=2.7, ambient=rgb(104,117,127), outdoor=rgb(150,168,187),
        horizon=rgb(180,211,236), decay=rgb(92,127,155), tint=rgb(255,251,246),
        water=rgb(35,105,105), reflection=.49, bloom=.12, lamp=0},
    evening = {hour=17.4, sun=2.1, ambient=rgb(105,93,105), outdoor=rgb(155,135,148),
        horizon=rgb(247,173,114), decay=rgb(122,105,141), tint=rgb(255,235,217),
        water=rgb(65,86,98), reflection=.60, bloom=.21, lamp=.42},
    night = {hour=20.5, sun=1.65, ambient=rgb(62,71,90), outdoor=rgb(102,116,146),
        horizon=rgb(94,111,154), decay=rgb(40,49,80), tint=rgb(223,235,255),
        water=rgb(19,48,60), reflection=.73, bloom=.30, lamp=1},
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
        terrain.WaterColor, terrain.WaterReflectance, terrain.WaterTransparency = e.water, e.reflection, .22
        terrain.WaterWaveSize, terrain.WaterWaveSpeed = Rules.wave(wave)
        Lighting.GlobalShadows = true
        Lighting.ClockTime, Lighting.Brightness = e.hour, e.sun
        Lighting.Ambient, Lighting.OutdoorAmbient = e.ambient, e.outdoor
        Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = .65, 1
        air.Density, air.Haze, air.Glare, air.Color, air.Decay = .21, .65, .12, e.horizon, e.decay
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
