local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TeleportService=game:GetService("TeleportService")
local HttpService=game:GetService("HttpService")
local Stats=require(script.Parent:WaitForChild("PlayerStats"))
local config=require(script.Parent:WaitForChild("LobbyConfig"))
local queue=require(script.Parent:WaitForChild("MatchQueue"))
local remote=Instance.new("RemoteEvent")
remote.Name="MinatoRankedLobby"
remote.Parent=ReplicatedStorage
local active, cancellations, last, loading={},{},{},{}
local function cancel(player, notify)
    local entry=active[player]
    if entry then
        cancellations[tostring(player.UserId)]=entry.session
        active[player]=nil
    end
    if notify and player.Parent == Players then remote:FireClient(player,"待機を終了しました",false) end
end
remote.OnServerEvent:Connect(function(player,action)
    if action ~= "join" and action ~= "cancel" then return end
    if last[player] and os.clock()-last[player] < 2 then return end
    last[player]=os.clock()
    if action == "cancel" then cancel(player,true); loading[player]=nil; return end
    if active[player] or loading[player] then return end
    if type(config.racePlaceId) ~= "number" or config.racePlaceId <= 0 then
        remote:FireClient(player,"レース会場は準備中です",false); return
    end
    local token=HttpService:GenerateGUID(false)
    loading[player]=token
    remote:FireClient(player,"成績を確認しています",true)
    task.spawn(function()
        local profile=Stats.load(player.UserId)
        if loading[player] ~= token then return end
        loading[player]=nil
        if player.Parent ~= Players then return end
        if not profile then remote:FireClient(player,"成績を取得できません。もう一度お試しください",false); return end
        active[player]={session=token,rating=profile.rating}
        remote:FireClient(player,"対戦相手を探しています",true)
    end)
end)
Players.PlayerRemoving:Connect(function(player)
    local entry=active[player]
    if entry and not entry.teleporting then cancel(player,false) end
    active[player]=nil; last[player]=nil; loading[player]=nil
end)
TeleportService.TeleportInitFailed:Connect(function(player,_,_,_,options)
    local data=options and options:GetTeleportData()
    if type(data)=="table" and data.mode=="ranked" then
        cancel(player,false)
        if player.Parent == Players then remote:FireClient(player,"移動できませんでした。もう一度お試しください",false) end
    end
end)
task.spawn(function()
    while true do
        task.wait(3)
        local entries={}
        for player,entry in pairs(active) do
            if player.Parent == Players then entries[tostring(player.UserId)]={session=entry.session,rating=entry.rating} end
        end
        if next(entries) or next(cancellations) then
            local pending=cancellations
            cancellations={}
            local state=queue.update(entries,pending)
            if not state then
                for id,token in pairs(pending) do cancellations[id]=token end
                for player in pairs(active) do remote:FireClient(player,"通信を確認しています",true) end
            else
                for player,entry in pairs(active) do
                    local record=state.players[tostring(player.UserId)]
                    if not record or record.session ~= entry.session then
                        active[player]=nil
                        remote:FireClient(player,"参加できません。少し待ってからお試しください",false)
                    elseif record.match and not entry.teleporting then
                        entry.teleporting=true
                        remote:FireClient(player,"対戦相手が決まりました。移動します",true)
                        task.spawn(function()
                            local options=Instance.new("TeleportOptions")
                            options.ReservedServerId=record.match
                            options:SetTeleportData({mode="ranked"})
                            local ok=pcall(TeleportService.TeleportAsync,TeleportService,config.racePlaceId,{player},options)
                            if not ok and active[player]==entry then
                                cancel(player,false)
                                if player.Parent == Players then remote:FireClient(player,"移動できませんでした。もう一度お試しください",false) end
                            end
                        end)
                    end
                end
            end
        end
    end
end)
