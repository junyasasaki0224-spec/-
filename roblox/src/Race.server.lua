-- Minato Grand Prix: server-authoritative prototype.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local collision = require(script.Parent:WaitForChild("BoatCollision"))
local RaceAI = require(script.Parent:WaitForChild("RaceAI"))
local stepBoat = require(ReplicatedStorage:WaitForChild("BoatPhysics"))

local input = Instance.new("RemoteEvent")
input.Name = "MinatoInput"
input.Parent = ReplicatedStorage
local snapshots = Instance.new("RemoteEvent")
snapshots.Name = "MinatoSnapshots"
snapshots.Parent = ReplicatedStorage
local setup = Instance.new("RemoteEvent")
setup.Name = "MinatoSetup"
setup.Parent = ReplicatedStorage
local world = Instance.new("Folder")
world.Name = "Minato"
world.Parent = workspace

local function part(parent, name, size, cf, color, material, shape)
    local p = Instance.new("Part")
    p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
    p.Material = material or Enum.Material.SmoothPlastic
    p.Anchored, p.CanCollide = true, false
    if shape then p.Shape = shape end
    p.Parent = parent
    return p
end
local function c(r,g,b) return Color3.fromRGB(r,g,b) end
Lighting.ClockTime = 14
Lighting.Brightness = 2
Lighting.Ambient = c(135,150,160)
part(world,"Water",Vector3.new(560,1,170),CFrame.new(0,-1,0),c(39,104,124),Enum.Material.Glass).Transparency = 0.24
part(world,"Stand",Vector3.new(440,14,35),CFrame.new(0,5,101),c(96,106,110),Enum.Material.Concrete)
for i = 0, 5 do
    part(world,"Terrace",Vector3.new(440,2,5),CFrame.new(0,12+i*2,90+i*5),c(169,176,173),Enum.Material.Concrete)
end
for _, z in ipairs({-83,83}) do
    part(world,"Breakwater",Vector3.new(560,3,2),CFrame.new(0,0,z),c(231,229,213),Enum.Material.Concrete)
end
for _, x in ipairs({-278,278}) do
    part(world,"Breakwater",Vector3.new(2,3,166),CFrame.new(x,0,0),c(231,229,213),Enum.Material.Concrete)
end
for _, mark in ipairs({Vector3.new(150,0,8),Vector3.new(-150,0,0)}) do
    part(world,"TurnMark",Vector3.new(3,3,3),CFrame.new(mark.X,1,mark.Z),c(240,104,45),Enum.Material.SmoothPlastic,Enum.PartType.Ball)
    part(world,"MarkFlag",Vector3.new(0.3,7,0.3),CFrame.new(mark.X,4,mark.Z),c(240,240,235))
end
part(world,"StartLine",Vector3.new(0.3,0.1,40),CFrame.new(0,-0.4,28),c(238,235,210),Enum.Material.Neon)
part(world,"CenterPole",Vector3.new(1.2,8,1.2),CFrame.new(0,3.5,4),c(244,220,48),Enum.Material.Metal)

local colors = {c(245,245,238),c(32,37,42),c(222,59,47),c(49,102,202),c(239,213,54),c(67,170,101)}
local boats = {}
for i=1,6 do
    local model = Instance.new("Model")
    model.Name = "Boat"..i
    local hull = part(model,"Hull",Vector3.new(3.1,0.8,7),CFrame.new(),colors[i],Enum.Material.SmoothPlastic)
    model.PrimaryPart = hull
    part(model,"Bow",Vector3.new(2.5,0.5,2),CFrame.new(0,0.15,-3.5),colors[i])
    part(model,"Deck",Vector3.new(2.5,0.3,3.8),CFrame.new(0,0.5,0.2),c(220,219,201))
    part(model,"Motor",Vector3.new(1.1,1.3,1.2),CFrame.new(0,0.5,3.3),c(45,48,50),Enum.Material.Metal)
    part(model,"Racer",Vector3.new(1.4,1.3,1.5),CFrame.new(0,1.2,0.5),colors[i])
    part(model,"Helmet",Vector3.new(1.2,1.2,1.2),CFrame.new(0,2,0.2),colors[i],Enum.Material.SmoothPlastic,Enum.PartType.Ball)
    model.Parent = world
    boats[i] = {model=model, x=-95, z=14+i*5, h=0, vx=0, vz=0, w=0, throttle=0, steer=0, lap=0, checkpoint=0, finished=false, speed=0}
end

local commands = {}
local tilts = {
    {acc=1.085,top=0.965,grip=1.065},
    {acc=1,top=1,grip=1},
    {acc=0.94,top=1.035,grip=0.945},
    {acc=0.88,top=1.075,grip=0.89},
}
local raceClock = -31
local wave = 0
local function applyTilt(boat, index)
    local tilt=tilts[index]
    boat.tilt=index
    boat.accF,boat.topF=tilt.acc,tilt.top
    boat.gripSet=tilt.grip*(1-wave*0.006)
end
local nextFirst = 1
local function preparePlayer(player)
    player:SetAttribute("MinatoBoat", 0)
end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(function(player)
    commands[player] = nil
    for _, boat in ipairs(boats) do
        if boat.player == player then boat.player = nil end
    end
end)
for _, player in ipairs(Players:GetPlayers()) do preparePlayer(player) end
local function assignPlayers()
    local players = Players:GetPlayers()
    table.sort(players, function(a,b) return a.UserId < b.UserId end)
    commands = {}
    for _, player in ipairs(players) do player:SetAttribute("MinatoBoat", 0) end
    for i, boat in ipairs(boats) do
        local player = nil
        if i <= #players then player = players[((nextFirst+i-2) % #players)+1] end
        boat.player = player
        if player then
            commands[player] = {throttle=0, steer=0, last=0}
            player:SetAttribute("MinatoBoat", i)
        end
    end
    if #players > 6 then nextFirst = ((nextFirst+5) % #players)+1 else nextFirst = 1 end
end
input.OnServerEvent:Connect(function(player, throttle, steer)
    local command = commands[player]
    if not command or type(throttle) ~= "number" or type(steer) ~= "number" then return end
    if throttle ~= throttle or steer ~= steer or math.abs(throttle) > 1 or math.abs(steer) > 1 then return end
    local now = os.clock()
    if now - command.last < 0.04 then return end
    command.throttle, command.steer, command.last = math.clamp(throttle,0,1), steer, now
end)
setup.OnServerEvent:Connect(function(player, index)
    if type(index) ~= "number" or index ~= index or index%1 ~= 0 or not tilts[index] or raceClock >= 0 then return end
    local command = commands[player]
    if not command or os.clock()-(command.setupLast or 0)<0.2 then return end
    command.setupLast = os.clock()
    for _,boat in ipairs(boats) do
        if boat.player == player and not boat.started then applyTilt(boat,index); return end
    end
end)

local raceNumber = 0
local function reset()
    raceNumber += 1
    wave = ((raceNumber*7)%16)/10
    local wind = ((raceNumber*13)%41)/10
    local windAngle = ((raceNumber*47)%360)*math.pi/180
    world:SetAttribute("Wind",wind)
    world:SetAttribute("Wave",wave)
    for i,b in ipairs(boats) do
        local lane = i-1
        local startX = lane < 3 and -106-lane*4 or -182-(lane-3)*5
        b.x,b.z,b.h,b.vx,b.vz,b.w = startX,11+lane*5.5,0,0,0,0
        b.laneZ = b.z
        b.throttle,b.steer,b.lap,b.checkpoint,b.finished,b.speed = 0,0,0,0,false,0
        b.started,b.flying,b.place = false,false,0
        b.player = nil
        b.windX,b.windZ = math.cos(windAngle)*wind,math.sin(windAngle)*wind
        b.motor,b.gripF,b.thrustF,b.inWake = 1,1,1,0
        b.trail,b.trailTimer = {},0
        applyTilt(b,2)
        RaceAI.init(b,i-1,1000+raceNumber*37+i*7919)
    end
    commands = {}
    for _, player in ipairs(Players:GetPlayers()) do player:SetAttribute("MinatoBoat", 0) end
end
reset()
local elapsed = -31
local finishTime = nil
local finishCount = 0
local assigned = false
local accumulator = 0
local dt = 1/120
local function step()
    elapsed += dt
    raceClock = elapsed
    if not assigned and elapsed >= -14 then
        assigned = true
        assignPlayers()
    end
    if not assigned then return end
    for i,b in ipairs(boats) do
        local previousX, previousZ = b.x, b.z
        local throttle, steer = 0,0
        if not b.finished and not b.flying then
            if b.player then
                local command = commands[b.player]
                if command and os.clock()-command.last < 0.6 then throttle,steer = command.throttle,command.steer end
            else
                throttle,steer = RaceAI.update(b,boats,elapsed,dt)
            end
        end
        stepBoat(b, throttle, steer, dt)
        collision.obstacles(b)
        b.speed = math.sqrt(b.vx*b.vx+b.vz*b.vz)
        b.trailTimer += dt
        if b.trailTimer >= 0.06 then
            b.trailTimer -= 0.06
            b.trail[#b.trail+1] = {x=b.x-math.cos(b.h)*2,z=b.z-math.sin(b.h)*2,time=elapsed}
            while #b.trail>0 and elapsed-b.trail[1].time>2.6 do table.remove(b.trail,1) end
        end
        if not b.started and previousX < 0 and b.x >= 0 and b.z > 4 then
            b.started = true
            if elapsed < 0 then b.flying = true end
        end
        if b.x < -274 or b.x > 274 then b.x=math.clamp(b.x,-274,274); b.vx *= -0.25 end
        if b.z < -79 or b.z > 79 then b.z=math.clamp(b.z,-79,79); b.vz *= -0.25 end
        -- The mark crossings enforce the correct side and sequence.
        if b.checkpoint == 0 and previousX < 150 and b.x >= 150 and b.z > 8 then b.checkpoint=1 end
        if b.checkpoint == 1 and previousZ > 8 and b.z <= 8 and b.x > 150 then b.checkpoint=2 end
        if b.checkpoint == 2 and previousX > 150 and b.x <= 150 and b.z < 8 then b.checkpoint=3 end
        if b.checkpoint == 3 and previousX > -150 and b.x <= -150 and b.z < 0 then b.checkpoint=4 end
        if b.checkpoint == 4 and previousZ < 0 and b.z >= 0 and b.x < -150 then b.checkpoint=5 end
        if b.checkpoint == 5 and previousX < -150 and b.x >= -150 and b.z > 0 then b.checkpoint=0; b.lap += 1 end
        if not b.finished and not b.flying and b.lap >= 3 and previousX < 0 and b.x >= 0 and b.z > 4 then
            b.finished=true
            finishCount += 1
            b.place = finishCount
            finishTime=finishTime or elapsed
        end
    end
    for i = 1, #boats - 1 do
        for j = i + 1, #boats do
            collision.boats(boats[i], boats[j])
        end
    end
    for _, boat in ipairs(boats) do
        boat.x = math.clamp(boat.x, -274, 274)
        boat.z = math.clamp(boat.z, -79, 79)
        boat.speed = math.sqrt(boat.vx * boat.vx + boat.vz * boat.vz)
        local wake = 0
        for _, other in ipairs(boats) do
            if other ~= boat then
                for index = #other.trail, 1, -2 do
                    local point = other.trail[index]
                    local age = elapsed-point.time
                    local radius = 1.1+age*0.45
                    if age >= 0.25 and (point.x-boat.x)^2+(point.z-boat.z)^2 < radius*radius then wake=1; break end
                end
            end
            if wake==1 then break end
        end
        boat.inWake += math.clamp(wake-boat.inWake,-4*dt,6*dt)
        boat.gripF = 1-0.22*boat.inWake
        boat.thrustF = 1-0.05*boat.inWake
    end
    if (finishTime and elapsed-finishTime > 45) or elapsed > 240 then
        reset(); elapsed=-31; raceClock=elapsed; finishTime=nil; finishCount=0; assigned=false
    end
end
local snapshotTimer = 0
local function progress(b)
    local cp = b.checkpoint
    if cp == 0 then return b.lap*720 + math.clamp(b.x+150,0,300) end
    if cp == 1 or cp == 2 then
        local angle = math.atan2(b.x-150,b.z-8)
        return b.lap*720 + 300 + 60*math.clamp(angle,0,math.pi)/math.pi
    end
    if cp == 3 then return b.lap*720 + 360 + math.clamp(150-b.x,0,300) end
    local angle = math.atan2(-(b.x+150),-b.z)
    return b.lap*720 + 660 + 60*math.clamp(angle,0,math.pi)/math.pi
end
RunService.Heartbeat:Connect(function(frame)
    accumulator = math.min(accumulator+frame,0.25)
    while accumulator >= dt do step(); accumulator -= dt end
    for i,b in ipairs(boats) do
        local pos = Vector3.new(b.x,0.5,b.z)
        b.model:PivotTo(CFrame.lookAt(pos,pos+Vector3.new(math.cos(b.h),0,math.sin(b.h))) * CFrame.Angles(0,0,math.clamp(-b.w*0.12,-0.18,0.18)))
        b.model:SetAttribute("Speed",math.floor(b.speed*3.6+0.5))
        b.model:SetAttribute("Lap",math.min(b.lap+1,3))
        b.model:SetAttribute("Finished",b.finished)
        b.model:SetAttribute("Flying",b.flying)
        b.model:SetAttribute("Place",b.place)
        b.model:SetAttribute("Tilt",b.tilt)
    end
    local order = table.clone(boats)
    table.sort(order,function(a,b)
        if a.flying ~= b.flying then return not a.flying end
        if a.finished ~= b.finished then return a.finished end
        if a.finished and b.finished then return a.place < b.place end
        local ap,bp = progress(a),progress(b)
        if ap == bp then return a.model.Name < b.model.Name end
        return ap > bp
    end)
    for rank,b in ipairs(order) do b.model:SetAttribute("Rank",rank) end
    world:SetAttribute("Time",math.floor(elapsed*10)/10)
    snapshotTimer += frame
    if snapshotTimer >= 1/15 then
        snapshotTimer %= 1/15
        local states = {}
        for i, b in ipairs(boats) do
            states[i] = {b.x,b.z,b.h,b.vx,b.vz,b.w,b.throttle,b.steer,b.accF,b.topF,b.gripSet,b.gripF,b.thrustF,b.windX,b.windZ,b.motor}
        end
        snapshots:FireAllClients(states, assigned)
    end
end)
