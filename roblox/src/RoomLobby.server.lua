local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local config = require(script.Parent:WaitForChild("LobbyConfig"))
local rooms = require(script.Parent:WaitForChild("RoomService"))
local remote = Instance.new("RemoteEvent")
remote.Name = "MinatoRoomLobby"
remote.Parent = ReplicatedStorage
local last, busy = {}, {}
local function setup(player)
    task.spawn(function()
        -- Roblox says invite launch data may arrive several seconds after joining.
        for _ = 1, 10 do
            if player.Parent ~= Players then return end
            local data = player:GetJoinData()
            if type(data.LaunchData) == "string" and #data.LaunchData == 6 then
                player:SetAttribute("MinatoInviteCode", data.LaunchData)
                return
            end
            task.wait(1)
        end
    end)
end
Players.PlayerAdded:Connect(setup)
Players.PlayerRemoving:Connect(function(player) last[player]=nil; busy[player]=nil end)
for _, player in ipairs(Players:GetPlayers()) do setup(player) end
remote.OnServerEvent:Connect(function(player, action, suppliedCode)
    if busy[player] or (last[player] and os.clock()-last[player] < 5) then return end
    last[player]=os.clock()
    if action ~= "create" and action ~= "join" then return end
    if type(config.racePlaceId) ~= "number" or config.racePlaceId <= 0 then
        remote:FireClient(player,"レース会場は準備中です"); return
    end
    busy[player]=true
    local code
    if action == "create" then code=rooms.create(player,config.racePlaceId)
    elseif type(suppliedCode) == "string" and #suppliedCode == 6 then code=string.upper(suppliedCode) end
    local access = code and rooms.ticket(code,player.UserId)
    if access and player.Parent == Players then
        local options = Instance.new("TeleportOptions")
        options.ReservedServerAccessCode = access
        options:SetTeleportData({mode="room",code=code})
        local ok = pcall(TeleportService.TeleportAsync,TeleportService,config.racePlaceId,{player},options)
        if not ok then remote:FireClient(player,"移動できませんでした。もう一度お試しください") end
    elseif player.Parent == Players then
        remote:FireClient(player,action == "create" and "部屋を作れませんでした。もう一度お試しください" or "部屋に入れません。合言葉と期限を確認してください")
    end
    busy[player]=nil
end)
TeleportService.TeleportInitFailed:Connect(function(player)
    if player.Parent == Players then remote:FireClient(player,"移動できませんでした。もう一度お試しください") end
end)
