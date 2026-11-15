-- Minato Grand Prix: server-authoritative prototype.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local collision = require(script.Parent:WaitForChild("BoatCollision"))
local RaceAI = require(script.Parent:WaitForChild("RaceAI"))
local createRoster = require(script.Parent:WaitForChild("RaceRoster"))
local stepBoat = require(ReplicatedStorage:WaitForChild("BoatPhysics"))
local Rules = require(script.Parent:WaitForChild("ResultRules"))
-- Unpublished Studio places cannot open a DataStore. Only a live result needs it.
local localPractice = RunService:IsStudio() and game.GameId == 0
local PlayerStats = not localPractice and require(script.Parent:WaitForChild("PlayerStats"))
local isRoom = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
local RoomService = isRoom and require(script.Parent:WaitForChild("RoomService"))
local MatchQueue = isRoom and require(script.Parent:WaitForChild("MatchQueue"))
local roomMembers, roomHost, roomCode = {}, nil, nil
local roomWaiting = isRoom
local roomKind, rankedStartAt, rankedStarted = nil, nil, false
local rankedLobbyPlace = nil
local returning = {}
local roomRemote = Instance.new("RemoteEvent")
roomRemote.Name = "MinatoRoomRace"
roomRemote.Parent = ReplicatedStorage
local roomInfo = Instance.new("RemoteFunction")
roomInfo.Name = "MinatoRoomInfo"
roomInfo.Parent = ReplicatedStorage
roomInfo.OnServerInvoke = function(player)
    if roomMembers[player] then return roomCode end
    return nil
end

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
world:SetAttribute("RoomMode", isRoom)
world:SetAttribute("RoomWaiting", roomWaiting)

local STUDS_PER_METRE = 3.5
local BOAT_SCALE = STUDS_PER_METRE * (2.9 / 7)
local function part(parent, name, size, cf, color, material, shape, scale)
    local p = Instance.new("Part")
    scale = scale or STUDS_PER_METRE
    p.Name, p.Size, p.CFrame, p.Color = name, size * scale, cf - cf.Position + cf.Position * scale, color
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
for _, z in ipairs({-79,59}) do
    part(world,"Breakwater",Vector3.new(516,3,2),CFrame.new(-5,0,z),c(231,229,213),Enum.Material.Concrete)
end
for _, x in ipairs({-263,253}) do
    part(world,"Breakwater",Vector3.new(2,3,138),CFrame.new(x,0,-10),c(231,229,213),Enum.Material.Concrete)
end
for _, mark in ipairs({Vector3.new(150,0,8),Vector3.new(-150,0,0)}) do
    part(world,"TurnMark",Vector3.new(1.6,1.6,1.6),CFrame.new(mark.X,0.8,mark.Z),c(240,104,45),Enum.Material.SmoothPlastic,Enum.PartType.Ball)
    part(world,"MarkFlag",Vector3.new(0.3,7,0.3),CFrame.new(mark.X,4,mark.Z),c(240,240,235))
end
for _, u in ipairs(collision.units) do
    local center = Vector3.new(u.x,0.15,u.z)
    part(world,"MarkFloat",Vector3.new(u.width,0.5,u.length),
        CFrame.lookAt(center,center+Vector3.new(u.dx,0,u.dz)),c(32,98,192))
end
part(world,"StartLine",Vector3.new(0.3,0.1,40),CFrame.new(0,-0.4,28),c(238,235,210),Enum.Material.Neon)
part(world,"CenterPole",Vector3.new(1.2,8,1.2),CFrame.new(0,3.5,4),c(244,220,48),Enum.Material.Metal)

local templates = Instance.new("Folder")
templates.Name = "MinatoTemplates"
templates.Parent = ReplicatedStorage
local colors = {c(245,245,238),c(32,37,42),c(222,59,47),c(49,102,202),c(239,213,54),c(67,170,101)}
local visuals=require(ReplicatedStorage:WaitForChild("VisualModels"))
local venue=visuals.venue(world)
if venue then
    for _,p in ipairs(world:GetChildren()) do
        if p.Name=="Stand" or p.Name=="Terrace" or p.Name=="Breakwater" then p:Destroy() end
    end
end
local boats = {}
for i=1,6 do
    local model = Instance.new("Model")
    model.Name = "Boat"..i
    local hull = part(model,"Hull",Vector3.new(3.1,0.8,7),CFrame.new(),colors[i],Enum.Material.SmoothPlastic,nil,BOAT_SCALE)
    model.PrimaryPart = hull
    part(model,"Bow",Vector3.new(2.5,0.5,2),CFrame.new(0,0.15,-3.5),colors[i],nil,nil,BOAT_SCALE)
    part(model,"Deck",Vector3.new(2.5,0.3,3.8),CFrame.new(0,0.5,0.2),c(220,219,201),nil,nil,BOAT_SCALE)
    part(model,"Motor",Vector3.new(1.1,1.3,1.2),CFrame.new(0,0.5,3.3),c(45,48,50),Enum.Material.Metal,nil,BOAT_SCALE)
    part(model,"Racer",Vector3.new(1.4,1.3,1.5),CFrame.new(0,1.2,0.5),colors[i],nil,nil,BOAT_SCALE)
    part(model,"Helmet",Vector3.new(1.2,1.2,1.2),CFrame.new(0,2,0.2),colors[i],Enum.Material.SmoothPlastic,Enum.PartType.Ball,BOAT_SCALE)
    local detailed=visuals.boat(nil,i)
    if detailed then
        model:Destroy()
        model=detailed
        model.Name="Boat"..i
    end
    model.Parent = templates
    boats[i] = {number=i,model=model, x=-95, z=14+i*5, h=0, vx=0, vz=0, w=0, throttle=0, steer=0, lap=0, checkpoint=0, finished=false, speed=0}
end

local MetaService=require(script.Parent:WaitForChild("MetaService"))
local commands = {}
local raceNumber = 0
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
local saveResults
local function preparePlayer(player)
    player:SetAttribute("MinatoBoat", 0)
    if not isRoom then return end
    task.spawn(function()
        local join = player:GetJoinData()
        local data = join and join.TeleportData
        if type(data) == "table" and (data.mode == "ranked" or data.mode == "online") then
            if rankedStarted or (roomKind and roomKind ~= data.mode) or not MatchQueue.accept(player.UserId,game.PrivateServerId,data.mode)
                or rankedStarted or (roomKind and roomKind ~= data.mode) then
                if player.Parent == Players then player:Kick("対戦会場に入れません。ロビーから入り直してください") end
                return
            end
            if player.Parent ~= Players then return end
            roomKind=data.mode
            world:SetAttribute("MatchMode",roomKind)
            if type(join.SourcePlaceId)=="number" and join.SourcePlaceId>0 then rankedLobbyPlace=rankedLobbyPlace or join.SourcePlaceId end
            roomMembers[player]=true
            rankedStartAt=rankedStartAt or os.clock()+20
            world:SetAttribute("RoomMode",false)
            world:SetAttribute("RankedPhase","waiting")
            return
        end
        local code = type(data) == "table" and data.mode == "room" and data.code or nil
        local owner
        if code then
            owner = RoomService.accept(code,player.UserId,game.PrivateServerId)
        else
            -- Invitations may arrive directly in this server; launch data can be delayed.
            for _ = 1, 10 do
                if player.Parent ~= Players then return end
                local incoming = player:GetJoinData().LaunchData
                if type(incoming) == "string" and #incoming == 6 then
                    code = incoming
                    owner = RoomService.acceptInvite(code,game.PrivateServerId)
                    break
                end
                task.wait(1)
            end
        end
        if player.Parent ~= Players then return end
        if not owner or (roomKind and roomKind ~= "room") or (roomCode and roomCode ~= code) or (roomHost and roomHost ~= owner) then
            player:Kick("部屋に入れません。ロビーから入り直してください")
            return
        end
        roomKind = "room"
        roomHost, roomCode = owner, code
        roomMembers[player] = true
        world:SetAttribute("RoomHost", owner)
    end)
end
Players.PlayerAdded:Connect(preparePlayer)
Players.PlayerRemoving:Connect(function(player)
    commands[player] = nil
    roomMembers[player] = nil
    for _, boat in ipairs(boats) do
        if boat.player == player then
            collision.disqualify(boat,"退出",raceClock)
            boat.player = nil
        end
    end
    if saveResults then
        local remaining = false
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= player then remaining = true; break end
        end
        if not remaining then saveResults() end
    end
end)
for _, player in ipairs(Players:GetPlayers()) do preparePlayer(player) end
local function assignPlayers()
    local players = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if not isRoom or roomMembers[player] then table.insert(players,player) end
    end
    table.sort(players, function(a,b) return a.UserId < b.UserId end)
    commands = {}
    for _, player in ipairs(players) do player:SetAttribute("MinatoBoat", 0) end
    for i, boat in ipairs(boats) do
        local player = nil
        if i <= #players then player = players[((nextFirst+i-2) % #players)+1] end
        boat.player = player
        boat.humanUserId = player and player.UserId or nil
        if player then
            commands[player] = {throttle=0, steer=0, last=0, sequence=0, applied=0}
            player:SetAttribute("MinatoBoat", i)
            local round=raceNumber
            task.spawn(function()
                local outfit=MetaService.get(player.UserId)
                if outfit and raceNumber==round and boat.player==player then
                    boat.model:SetAttribute("Skin",outfit.skin)
                    boat.model:SetAttribute("HelmetStyle",outfit.helmet)
                end
            end)
        end
    end
    if #players > 6 then nextFirst = ((nextFirst+5) % #players)+1 else nextFirst = 1 end
end
input.OnServerEvent:Connect(function(player, throttle, steer, sequence, round)
    local command = commands[player]
    if roomWaiting or round ~= raceNumber then return end
    if not command or type(throttle) ~= "number" or type(steer) ~= "number" or type(sequence) ~= "number" then return end
    if throttle ~= throttle or steer ~= steer or math.abs(throttle) > 1 or math.abs(steer) > 1 then return end
    if sequence ~= sequence or sequence%1 ~= 0 or sequence <= command.sequence or sequence > 2147483647 then return end
    local now = os.clock()
    if now - command.last < 0.04 then return end
    command.throttle, command.steer, command.last, command.sequence = math.clamp(throttle,0,1), steer, now, sequence
end)
setup.OnServerEvent:Connect(function(player, index, round)
    if roomWaiting or round ~= raceNumber then return end
    if type(index) ~= "number" or index ~= index or index%1 ~= 0 or not tilts[index] or raceClock >= 0 then return end
    local command = commands[player]
    if not command or os.clock()-(command.setupLast or 0)<0.2 then return end
    command.setupLast = os.clock()
    for _,boat in ipairs(boats) do
        if boat.player == player and not boat.started then applyTilt(boat,index); return end
    end
end)

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
local function orderBoats()
    local order = table.clone(boats)
    table.sort(order,function(a,b)
        local outA,outB = a.out ~= nil, b.out ~= nil
        if outA ~= outB then return not outA end
        if a.finished ~= b.finished then return a.finished end
        if a.finished and b.finished then return a.place < b.place end
        local ap,bp = progress(a),progress(b)
        if ap == bp then return a.model.Name < b.model.Name end
        return ap > bp
    end)
    return order
end

local function reset()
    raceNumber += 1
    wave = ((raceNumber*7)%16)/10
    local wind = ((raceNumber*13)%41)/10
    local windAngle = ((raceNumber*47)%360)*math.pi/180
    local racers = createRoster(raceNumber)
    world:SetAttribute("Wind",wind)
    world:SetAttribute("Wave",wave)
    for i,b in ipairs(boats) do
        local lane = i-1
        local startX = lane < 3 and -106-lane*4 or -182-(lane-3)*5
        b.x,b.z,b.h,b.vx,b.vz,b.w = startX,11+lane*5.5,0,0,0,0
        b.laneZ = b.z
        b.throttle,b.steer,b.lap,b.checkpoint,b.finished,b.speed = 0,0,0,0,false,0
        b.started,b.flying,b.place,b.startTime = false,false,0,nil
        b.out,b.outAt,b.sunk = nil,nil,false
        b.model:SetAttribute("Skin",nil)
        b.model:SetAttribute("HelmetStyle",nil)
        b.player = nil
        b.humanUserId,b.finishTime = nil,nil
        b.windX,b.windZ = math.cos(windAngle)*wind,math.sin(windAngle)*wind
        b.motor,b.gripF,b.thrustF,b.inWake = racers[i].motor,1,1,0
        b.model:SetAttribute("Racer",racers[i].racer.name)
        b.trail,b.trailTimer = {},0
        applyTilt(b,2)
        RaceAI.init(b,i-1,1000+raceNumber*37+i*7919,racers[i].racer)
    end
    commands = {}
    for _, player in ipairs(Players:GetPlayers()) do player:SetAttribute("MinatoBoat", 0) end
end
reset()
local elapsed = -31
local finishTime = nil
local finishCount = 0
local assigned = false
local raceId = HttpService:GenerateGUID(false)
local resultsSaved = false
local aloneSince, finalRows = nil,nil
local accumulator = 0
local dt = 1/120
saveResults = function()
    if resultsSaved or not assigned then return end
    resultsSaved = true
    local results = {}
    finalRows = {}
    for position, boat in ipairs(orderBoats()) do
        finalRows[position] = {boat.number,boat.out or (boat.finished and tostring(boat.place) or "未完走")}
        if boat.humanUserId then table.insert(results,Rules.entry(boat,position)) end
    end
    if #results > 0 and not localPractice then
        -- The mode was established only after server-side admission.
        PlayerStats.recordRace(raceId,results,roomKind=="ranked")
    end
end
roomRemote.OnServerEvent:Connect(function(player, action)
    if action == "return" and (roomKind == "ranked" or roomKind == "online") and (world:GetAttribute("RankedPhase") == "finished" or world:GetAttribute("RankedPhase") == "incomplete")
        and roomMembers[player] and rankedLobbyPlace and not returning[player] then
        returning[player]=true
        task.spawn(function()
            local ok=pcall(TeleportService.TeleportAsync,TeleportService,rankedLobbyPlace,{player})
            if not ok and player.Parent == Players then roomRemote:FireClient(player,"ロビーへ戻れません。もう一度お試しください") end
            returning[player]=nil
        end)
        return
    end
    if not isRoom or roomKind ~= "room" or action ~= "start" or not roomWaiting or not roomMembers[player] or player.UserId ~= roomHost then return end
    roomWaiting = false
    world:SetAttribute("RoomWaiting", false)
    elapsed = -14
    raceClock = elapsed
end)
local function step()
    if roomWaiting then
        if (roomKind == "ranked" or roomKind == "online") and not rankedStarted and rankedStartAt and os.clock() >= rankedStartAt then
            rankedStarted = true
            if roomKind == "online" then
                local count = 0
                for member in pairs(roomMembers) do
                    if member.Parent == Players then count += 1 end
                end
                if count < 6 then
                    world:SetAttribute("RankedPhase","incomplete")
                    return
                end
            end
            roomWaiting = false
            elapsed = -14
            raceClock = elapsed
            world:SetAttribute("RoomWaiting",false)
            world:SetAttribute("RankedPhase","racing")
        else return end
    end
    elapsed += dt
    raceClock = elapsed
    if not assigned and elapsed >= -14 then
        assigned = true
        finalRows = nil
        assignPlayers()
    end
    if not assigned then return end
    for i,b in ipairs(boats) do
        if b.out then continue end
        local previousX, previousZ = b.x, b.z
        local throttle, steer = 0,0
        if not b.finished and not b.flying then
            if b.player then
                local command = commands[b.player]
                if command then
                    if os.clock()-command.last < 0.6 then throttle,steer = command.throttle,command.steer end
                    command.applied = command.sequence
                end
            else
                throttle,steer = RaceAI.update(b,boats,elapsed,dt,collision.units)
            end
        end
        stepBoat(b, throttle, steer, dt)
        collision.walls(b,elapsed)
        collision.obstacles(b,elapsed)
        if b.out then
            if b.player then commands[b.player]=nil end
            continue
        end
        b.speed = math.sqrt(b.vx*b.vx+b.vz*b.vz)
        b.trailTimer += dt
        if b.trailTimer >= 0.06 then
            b.trailTimer -= 0.06
            b.trail[#b.trail+1] = {x=b.x-math.cos(b.h)*2,z=b.z-math.sin(b.h)*2,time=elapsed}
            while #b.trail>0 and elapsed-b.trail[1].time>2.6 do table.remove(b.trail,1) end
        end
        if not b.started and previousX < 0 and b.x >= 0 and b.z > 4 then
            b.started = true
            local fraction = (0-previousX)/math.max(b.x-previousX,0.000001)
            b.startTime = elapsed-dt*(1-fraction)
            if b.startTime < 0 then
                collision.disqualify(b,"F",elapsed)
                if b.player then commands[b.player]=nil end
                continue
            end
        end
        -- The mark crossings enforce the correct side and sequence.
        if b.checkpoint == 0 and previousX < 150 and b.x >= 150 and b.z > 8 then b.checkpoint=1 end
        if b.checkpoint == 1 and previousZ > 8 and b.z <= 8 and b.x > 150 then b.checkpoint=2 end
        if b.checkpoint == 2 and previousX > 150 and b.x <= 150 and b.z < 8 then b.checkpoint=3 end
        if b.checkpoint == 3 and previousX > -150 and b.x <= -150 and b.z < 0 then b.checkpoint=4 end
        if b.checkpoint == 4 and previousZ < 0 and b.z >= 0 and b.x < -150 then b.checkpoint=5 end
        if b.checkpoint == 5 and previousX < -150 and b.x >= -150 and b.z > 0 then b.checkpoint=0; b.lap += 1 end
        if not b.finished and not b.flying and b.lap >= 3 and previousX < 0 and b.x >= 0 and b.z > 4 then
            b.finished=true
            if b.player then commands[b.player]=nil end
            b.finishTime = math.max(0.001,elapsed-(b.startTime or 0))
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
        if boat.out then continue end
        boat.speed = math.sqrt(boat.vx * boat.vx + boat.vz * boat.vz)
        local wake = 0
        for _, other in ipairs(boats) do
            if other ~= boat and not other.out then
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
    local endEarly
    endEarly, aloneSince = Rules.shouldEnd(boats,elapsed,aloneSince)
    if endEarly or (finishTime and elapsed-finishTime > 45) or elapsed > 240 then
        saveResults()
        if roomKind == "ranked" or roomKind == "online" then
            roomWaiting=true
            world:SetAttribute("RoomWaiting",true)
            world:SetAttribute("RankedPhase","finished")
            return
        end
        reset(); elapsed=-31; raceClock=elapsed; finishTime=nil; finishCount=0; assigned=false
        raceId = HttpService:GenerateGUID(false)
        resultsSaved = false
        aloneSince = nil
        if isRoom then
            roomWaiting = true
            world:SetAttribute("RoomWaiting", true)
        end
    end
end
game:BindToClose(function()
    saveResults()
    if PlayerStats then PlayerStats.waitForPending(25) end
end)
local snapshotTimer = 0
RunService.Heartbeat:Connect(function(frame)
    accumulator = math.min(accumulator+frame,0.25)
    while accumulator >= dt do step(); accumulator -= dt end
    for i,b in ipairs(boats) do
        b.model:SetAttribute("Speed",math.floor(b.speed*3.6+0.5))
        b.model:SetAttribute("Lap",math.min(b.lap+1,3))
        b.model:SetAttribute("Finished",b.finished)
        b.model:SetAttribute("Flying",b.flying)
        b.model:SetAttribute("Place",b.place)
        b.model:SetAttribute("Tilt",b.tilt)
        b.model:SetAttribute("StartTime",b.startTime)
    end
    local order = orderBoats()
    for rank,b in ipairs(order) do b.model:SetAttribute("Rank",rank) end
    world:SetAttribute("Time",math.floor(elapsed*10)/10)
    snapshotTimer += frame
    if snapshotTimer >= 1/15 then
        snapshotTimer %= 1/15
        local states = {}
        for i, b in ipairs(boats) do
            states[i] = {b.x,b.z,b.h,b.vx,b.vz,b.w,b.throttle,b.steer,b.accF,b.topF,b.gripSet,b.gripF,b.thrustF,b.windX,b.windZ,b.motor,b.out or "",b.outAt or 0,b.finished,b.place}
        end
        for _, player in ipairs(Players:GetPlayers()) do
            local command = commands[player]
            snapshots:FireClient(player, states, assigned and not roomWaiting, command and command.applied or 0, raceNumber, elapsed, player:GetAttribute("MinatoBoat") or 0, finalRows)
        end
    end
end)
