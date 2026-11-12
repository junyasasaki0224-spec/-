local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Stats = require(script.Parent:WaitForChild("PlayerStats"))
local config = require(script.Parent:WaitForChild("LobbyConfig"))
local PAGE_SIZE = 50
local MAX_PAGES = 5

local remote = Instance.new("RemoteFunction")
remote.Name = "MinatoLeaderboard"
remote.Parent = ReplicatedStorage
local practice = Instance.new("RemoteEvent")
practice.Name = "MinatoPractice"
practice.Parent = ReplicatedStorage
local teleporting = {}
local lastTeleport = {}
practice.OnServerEvent:Connect(function(player)
    if teleporting[player] then return end
    local now=os.clock()
    if lastTeleport[player] and now-lastTeleport[player]<5 then return end
    lastTeleport[player]=now
    if type(config.racePlaceId) ~= "number" or config.racePlaceId <= 0 then
        practice:FireClient(player,"レース会場は準備中です")
        return
    end
    teleporting[player]=true
    local ok = pcall(function() TeleportService:TeleportAsync(config.racePlaceId,{player}) end)
    if not ok then practice:FireClient(player,"移動できませんでした。もう一度お試しください") end
    teleporting[player]=nil
end)

local boards = {
    rating={entries={},ranks={},below={},ready=false,busy=false,lastStarted=-60},
    wins={entries={},ranks={},below={},ready=false,busy=false,lastStarted=-60},
    bestTime={entries={},ranks={},below={},ready=false,busy=false,lastStarted=-60},
}
local profiles, names, lastRequest = {}, {}, {}
local nameQueue, queuedNames = {}, {}

local function queueName(userId)
    if names[userId] or queuedNames[userId] then return end
    queuedNames[userId] = true
    table.insert(nameQueue,userId)
end
task.spawn(function()
    while true do
        local userId = table.remove(nameQueue,1)
        if userId then
            local ok,name = pcall(Players.GetNameFromUserIdAsync,Players,userId)
            names[userId] = ok and name or nil
            queuedNames[userId] = nil
            task.wait(0.1)
        else task.wait(0.5) end
    end
end)

local function displayValue(kind, value)
    if kind == "rating" then return math.floor(value/Stats.versionBase) end
    if kind == "bestTime" then return value/1000 end
    return value
end

local function refresh(kind)
    local board = boards[kind]
    if board.busy or os.clock()-board.lastStarted < 60 then return end
    board.busy = true
    board.lastStarted = os.clock()
    local wanted = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local profile = profiles[player.UserId]
        if profile and (kind ~= "bestTime" or profile.bestTime) then wanted[player.UserId]=true end
    end
    local ok,pages = pcall(function() return Stats.ordered[kind]:GetSortedAsync(kind=="bestTime",PAGE_SIZE) end)
    if not ok then board.busy=false; board.error=true; return end
    local results,ranks,index = {},{},0
    local pageCount,lastValue = 0,nil
    repeat
        pageCount += 1
        for _, entry in ipairs(pages:GetCurrentPage()) do
            index += 1
            lastValue = entry.value
            local id=tonumber(entry.key)
            if id then
                if index <= 50 then
                    table.insert(results,{userId=id,value=displayValue(kind,entry.value)})
                    queueName(id)
                end
                if wanted[id] then ranks[id]=index; wanted[id]=nil end
            end
        end
        if index <= 50 then
            board.entries=results
            board.below={}
            board.ready=true
            board.error=false
        end
        board.ranks=ranks
        for id in pairs(wanted) do
            if not Players:GetPlayerByUserId(id) then wanted[id]=nil end
        end
        if not next(wanted) or pages.IsFinished then break end
        if pageCount >= MAX_PAGES then
            local below = {}
            for id in pairs(wanted) do
                if Players:GetPlayerByUserId(id) then
                    local found,score = pcall(function() return Stats.ordered[kind]:GetAsync(tostring(id)) end)
                    if found and type(score)=="number" and lastValue and
                        ((kind=="bestTime" and score>=lastValue) or (kind~="bestTime" and score<=lastValue)) then
                        below[id]=index+1
                    end
                    task.wait(0.1)
                end
            end
            board.below=below
            break
        end
        task.wait(1)
        ok = pcall(function() pages:AdvanceToNextPageAsync() end)
        if not ok then board.error=true; break end
    until false
    board.busy=false
end

local function refreshAll()
    for kind in pairs(boards) do task.spawn(refresh,kind) end
end
local function initialize(player)
    task.spawn(function()
        while player.Parent == Players do
            local profile = Stats.ensure(player.UserId)
            if profile then
                profiles[player.UserId] = profile
                refreshAll()
                return
            end
            task.wait(30)
        end
    end)
end
Players.PlayerAdded:Connect(initialize)
Players.PlayerRemoving:Connect(function(player)
    profiles[player.UserId],lastRequest[player.UserId] = nil,nil
    teleporting[player],lastTeleport[player] = nil,nil
end)
for _,player in ipairs(Players:GetPlayers()) do initialize(player) end
task.spawn(function()
    while true do
        task.wait(60)
        if #Players:GetPlayers() > 0 then refreshAll() end
    end
end)

remote.OnServerInvoke = function(player)
    local now=os.clock()
    if lastRequest[player.UserId] and now-lastRequest[player.UserId] < 1 then return nil end
    lastRequest[player.UserId]=now
    local saved = profiles[player.UserId]
    local publicProfile = saved and {rating=saved.rating,races=saved.races,wins=saved.wins,bestTime=saved.bestTime,version=saved.version} or nil
    local response = {profile=publicProfile,boards={}}
    for kind,board in pairs(boards) do
        local entries={}
        for i,entry in ipairs(board.entries) do
            entries[i]={userId=entry.userId,name=names[entry.userId],value=entry.value}
        end
        response.boards[kind]={entries=entries,rank=board.ranks[player.UserId],below=board.below[player.UserId],ready=board.ready,busy=board.busy,error=board.error}
    end
    return response
end
