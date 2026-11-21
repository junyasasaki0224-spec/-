local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Service=require(script.Parent:WaitForChild("MetaService"))
local Meta=require(ReplicatedStorage:WaitForChild("Meta"))
local remote=Instance.new("RemoteFunction")
remote.Name="MinatoMeta"
remote.Parent=ReplicatedStorage
local last,busy={},{}
remote.OnServerInvoke=function(player,action,arg,token)
    if busy[player] or (last[player] and os.clock()-last[player]<.35) then return nil,"通信中です" end
    if action~="get" and action~="pull" and action~="mail" and action~="mission" and action~="equip" and action~="settings" then return nil,"操作を確認してください" end
    if action~="get" then
        if type(token)~="string" or #token>60 then return nil,"ホームを開き直してください" end
        -- ガチャは「種類:回数」(例 "helmet:10")。種類と回数(1 か 10)を確かめる
        if action=="pull" then if Meta.pullArg(arg)==nil then return nil end
        elseif type(arg)~="string" or #arg>80 then return nil end
    end
    last[player],busy[player]=os.clock(),true
    local ok,data=pcall(function()
        if action=="get" then return Service.get(player.UserId) end
        return Service.action(player.UserId,token,action,arg)
    end)
    busy[player]=nil
    if ok and data then return data end
    return nil,"保存を確認できません。同じ操作を再試行してください"
end
Players.PlayerRemoving:Connect(function(p) last[p]=nil;busy[p]=nil end)
