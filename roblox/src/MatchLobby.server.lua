local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local TeleportService=game:GetService("TeleportService")
local HttpService=game:GetService("HttpService")
local config=require(script.Parent:WaitForChild("LobbyConfig"))
local Stats,queue
if game.GameId~=0 and type(config.racePlaceId)=="number" and config.racePlaceId>0 then
    Stats=require(script.Parent:WaitForChild("PlayerStats"))
    queue=require(script.Parent:WaitForChild("MatchQueue"))
end
local remote=Instance.new("RemoteEvent")
remote.Name="MinatoRankedLobby"
remote.Parent=ReplicatedStorage
local active, last, loading={},{},{}
local cancellations={ranked={},online={}}
local function cancel(player, notify)
    local entry=active[player]
    if entry then
        cancellations[entry.mode][tostring(player.UserId)]=entry.session
        active[player]=nil
    end
    if notify and player.Parent == Players then remote:FireClient(player,"待機を終了しました",false) end
end
remote.OnServerEvent:Connect(function(player,action)
    if action ~= "join" and action ~= "online" and action ~= "cancel" then return end
    if action=="cancel" then
        if (active[player] and not active[player].teleporting) or loading[player] then
            loading[player]=nil
            cancel(player,true)
        end
        return
    end
    if last[player] and os.clock()-last[player] < 2 then return end
    last[player]=os.clock()
    if active[player] or loading[player] then return end
    if not queue then
        remote:FireClient(player,"レース会場は準備中です",false); return
    end
    local token=HttpService:GenerateGUID(false)
    if action=="online" then
        active[player]={session=token,rating=0,mode="online"}
        remote:FireClient(player,"オンライン：6人そろうまで待機します",true,"online")
        return
    end
    loading[player]=token
    remote:FireClient(player,"成績を確認しています",true)
    task.spawn(function()
        local profile=Stats.load(player.UserId)
        if loading[player] ~= token then return end
        loading[player]=nil
        if player.Parent ~= Players then return end
        if not profile then remote:FireClient(player,"成績を取得できません。もう一度お試しください",false); return end
        active[player]={session=token,rating=profile.rating,mode="ranked"}
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
    if type(data)=="table" and (data.mode=="ranked" or data.mode=="online") and active[player] and active[player].session==data.session then
        cancel(player,false)
        if player.Parent == Players then remote:FireClient(player,"移動できませんでした。もう一度お試しください",false) end
    end
end)
local function poll(mode)
    local entries={}
    for player,entry in pairs(active) do
        if entry.mode==mode and player.Parent == Players then entries[tostring(player.UserId)]={session=entry.session,rating=entry.rating} end
    end
    if next(entries) or next(cancellations[mode]) then
        local pending=cancellations[mode]
        cancellations[mode]={}
        local state,matchId=queue.update(entries,pending,mode)
        if not state then
            for id,token in pairs(pending) do cancellations[mode][id]=token end
            for player,entry in pairs(active) do
                if entry.mode==mode then remote:FireClient(player,"通信を確認しています",true,mode) end
            end
        else
            -- この呼び出しで組が決まった場合は、このロビーが会場を1つ予約して、組の全員に鍵を配る
            local committed=false
            for _,record in pairs(state.players) do
                if record.match==matchId and not record.access then committed=true; break end
            end
            if committed then
                local ok,access,privateId=pcall(TeleportService.ReserveServerAsync,TeleportService,config.racePlaceId)
                if ok and type(access)=="string" and type(privateId)=="string" and privateId~="" and queue.assign(matchId,access,privateId,mode) then
                    for _,record in pairs(state.players) do
                        if record.match==matchId then record.access,record.privateId=access,privateId end
                    end
                else
                    queue.release(matchId,mode)
                    for _,record in pairs(state.players) do
                        if record.match==matchId then record.match=nil end
                    end
                end
            end
            for player,entry in pairs(active) do
                if entry.mode~=mode or not entries[tostring(player.UserId)] or entries[tostring(player.UserId)].session~=entry.session then continue end
                local record=state.players[tostring(player.UserId)]
                if not record or record.session ~= entry.session then
                    active[player]=nil
                    remote:FireClient(player,"参加できません。少し待ってからお試しください",false)
                elseif record.match and record.access and not entry.teleporting then
                    entry.teleporting=true
                    remote:FireClient(player,"対戦相手が決まりました。移動します",true,mode)
                    task.spawn(function()
                        local options=Instance.new("TeleportOptions")
                        options.ReservedServerAccessCode=record.access
                        options:SetTeleportData({mode=mode,session=entry.session})
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
for _,mode in ipairs({"ranked","online"}) do
    task.spawn(function()
        while true do
            task.wait(3)
            poll(mode)
        end
    end)
end
