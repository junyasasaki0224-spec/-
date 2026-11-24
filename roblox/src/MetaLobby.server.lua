local Players=game:GetService("Players")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Service=require(script.Parent:WaitForChild("MetaService"))
local Meta=require(ReplicatedStorage:WaitForChild("Meta"))
local remote=Instance.new("RemoteFunction")
remote.Name="MinatoMeta"
remote.Parent=ReplicatedStorage
-- 保存(DataStore)の読み書きには、サーバー全体で1分あたりの上限がある。1人が連打しても、
-- ほかの人のレース結果や購入の保存が遅れないよう、1人ぶんの書き込みを回数券で抑える
local BURST=10 -- 続けて使える回数
local REFILL=3 -- 1枚戻るまでの秒数(続けて押し続けても、1分に20回まで)
local GET_REUSE=5 -- 読み直し(get)は、この秒数のあいだ前に返した物を使い回す(保存に触れない)
local last,busy,tickets,cached={},{},{},{}

-- 回数券を1枚使う。足りなければ false
local function spend(player)
    local now=os.clock()
    local t=tickets[player] or {n=BURST,at=now}
    t.n=math.min(BURST,t.n+(now-t.at)/REFILL)
    t.at=now
    tickets[player]=t
    if t.n<1 then return false end
    t.n-=1
    return true
end

remote.OnServerInvoke=function(player,action,arg,token)
    if busy[player] or (last[player] and os.clock()-last[player]<.35) then return nil,"通信中です" end
    if action~="get" and action~="pull" and action~="mail" and action~="mission" and action~="equip" and action~="settings" then return nil,"操作を確認してください" end
    if action~="get" then
        if type(token)~="string" or #token>60 then return nil,"ホームを開き直してください" end
        -- ガチャは「種類:回数」(例 "helmet:10")。種類と回数(1 か 10)を確かめる
        if action=="pull" then if Meta.pullArg(arg)==nil then return nil end
        elseif type(arg)~="string" or #arg>80 then return nil end
    end
    -- 読み直しは、少し前に返した物があればそれを返す(購入や VIP のボーナスで中身が変わった後は使わない)
    local c=cached[player]
    if action=="get" and c and os.clock()-c.at<GET_REUSE and c.version==Service.version(player.UserId) then
        return Meta.clone(c.data)
    end
    if not spend(player) then return nil,"操作が多すぎます。少し待ってからもう一度お試しください" end
    last[player],busy[player]=os.clock(),true
    local version=Service.version(player.UserId)
    local ok,data=pcall(function()
        if action=="get" then return Service.get(player.UserId) end
        return Service.action(player.UserId,token,action,arg)
    end)
    busy[player]=nil
    if ok and data then
        cached[player]={at=os.clock(),data=Meta.clone(data),version=version}
        return data
    end
    return nil,"保存を確認できません。同じ操作を再試行してください"
end
Players.PlayerRemoving:Connect(function(p) last[p]=nil;busy[p]=nil;tickets[p]=nil;cached[p]=nil end)
