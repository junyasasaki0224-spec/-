-- Client-only foam. Attachment axes follow the rendered boat, even during prediction.
local Rules = require(script.Parent.WaterRules)
local Wake = {}
local key = NumberSequenceKeypoint.new
local function sequence(a,b,c)
    return NumberSequence.new({key(0,a), key(.38,b), key(1,c)})
end
local function attachment(root, name, pos, direction)
    local a = Instance.new("Attachment")
    a.Name = name
    a.CFrame = CFrame.lookAt(pos, pos + direction)
    a.Parent = root
    return a
end

local function drops(anchor, name, speed, spread)
    local p = Instance.new("ParticleEmitter")
    p.Name = name
    p.Texture = "rbxasset://textures/particles/smoke_main.dds"
    p.EmissionDirection = Enum.NormalId.Front
    p.Orientation = Enum.ParticleOrientation.VelocityParallel
    p.Squash = NumberSequence.new(-.72)
    p.Size = sequence(.6,1,.35)
    p.Color = ColorSequence.new(Color3.fromRGB(245,252,255), Color3.fromRGB(184,211,221))
    p.Transparency = sequence(.16,.30,1)
    p.Speed, p.SpreadAngle = speed, spread
    p.Acceleration = Vector3.new(0,-34,0)
    p.Lifetime = NumberRange.new(.48,.83)
    p.LightInfluence, p.LightEmission = .5, .07
    p.Rate = 0
    p.Parent = anchor
    return p
end

function Wake.new(root)
    local stern = attachment(root,"PropWash",Vector3.new(0,-.75,4.8),Vector3.new(0,.85,1))
    local fan = attachment(root,"TurnSheet",Vector3.new(0,-.8,4.4),Vector3.new(1,.7,.55))
    local jet = drops(stern,"SternDrops",NumberRange.new(9,17),Vector2.new(14,17))
    local sheet = drops(fan,"SheetDrops",NumberRange.new(17,34),Vector2.new(30,20))
    local mist = drops(stern,"Spindrift",NumberRange.new(3,6),Vector2.new(30,20))
    mist.Orientation = Enum.ParticleOrientation.FacingCamera
    mist.Squash, mist.Size = NumberSequence.new(0), sequence(1,2.1,4.2)
    mist.Acceleration, mist.Transparency = Vector3.new(0,1,0), sequence(.78,.83,1)
    local crown = drops(stern,"ImpactCrown",NumberRange.new(16,36),Vector2.new(62,62))
    crown.EmissionDirection = Enum.NormalId.Top
    -- Separate upright attachment for the radial burst.
    crown.Parent = attachment(root,"Impact",Vector3.new(0,-.7,0),Vector3.new(0,0,-1))
    local ribbons = {}
    for _, side in {-1,1} do
        local trail = Instance.new("Trail")
        trail.Name = "PropFoam"
        trail.Attachment0 = attachment(root,"FoamInner",Vector3.new(side*.14,-1.15,4.7),Vector3.zAxis)
        trail.Attachment1 = attachment(root,"FoamOuter",Vector3.new(side*2.6,-1.15,4.8),Vector3.zAxis)
        trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
        trail.TextureMode, trail.TextureLength = Enum.TextureMode.Wrap, 8
        trail.FaceCamera = false
        trail.Color = ColorSequence.new(Color3.fromRGB(236,250,248),Color3.fromRGB(156,190,198))
        trail.Transparency = sequence(.28,.56,1)
        trail.WidthScale = sequence(.48,.84,1)
        trail.MinLength, trail.MaxLength, trail.Lifetime = .65, 95, 1.55
        trail.Enabled = false
        trail.Parent = root
        table.insert(ribbons,trail)
    end
    return {jet=jet, sheet=sheet, mist=mist, crown=crown, fan=fan, ribbons=ribbons}
end

function Wake.update(e, race, out, age, speed, throttle, slip, side, distance, following, jump, scale)
    scale=scale or 1
    if e.race ~= race or jump then
        for _, trail in e.ribbons do trail:Clear() end
        for _, p in {e.jet,e.sheet,e.mist,e.crown} do p:Clear() end
        if e.race ~= race then e.sunk = false end
        e.race = race
    end
    local jet, sheet, mist = 0,0,0
    if out == "" then
        jet, sheet, mist = Rules.rates(speed, throttle, slip, distance, following)
    end
    e.jet.Rate, e.sheet.Rate, e.mist.Rate = jet*scale, sheet*scale, scale>.35 and mist*scale or 0
    for _, trail in e.ribbons do trail.Enabled = out == "" and speed > 3 and not jump end
    if sheet > 0 and side ~= e.side then
        local origin = Vector3.new(side*.85,-.8,4.4)
        e.fan.CFrame = CFrame.lookAt(origin,origin + Vector3.new(side,.73,.53))
        e.side = side
    end
    if out == "沈" and not e.sunk then
        e.sunk = true
        if age < 1 then e.crown:Emit(math.ceil(32*scale)); e.mist:Emit(math.ceil(6*scale)) end
    end
end

return Wake
