local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local Meta=require(game:GetService("ReplicatedStorage"):WaitForChild("Meta"))
local Service={}
local practice=RunService:IsStudio() and (game.GameId == 0 or not workspace:GetAttribute("MinatoLiveData"))
local memory={}
local Stats=not practice and require(script.Parent:WaitForChild("PlayerStats"))
local function update(userId,fn)
    if practice then
        memory[userId]=fn(memory[userId])
        return Meta.clone(memory[userId])
    end
    return Stats.mutate(userId,fn)
end
local function day() return os.date("!%Y-%m-%d",os.time()+9*3600) end
function Service.get(userId)
    local token=HttpService:GenerateGUID(false)
    local today=day()
    local data=update(userId,function(v)
        v=Meta.clone(v or {})
        v.meta=Meta.normalize(v.meta)
        v.meta.token=v.meta.token or token
        Meta.daily(v.meta,today)
        return v
    end)
    return data and data.meta
end
function Service.action(userId,token,action,arg)
    local random=Random.new()
    local draws={}
    for i=1,20 do draws[i]=random:NextNumber() end
    local nextToken=HttpService:GenerateGUID(false)
    local today=day()
    local data=update(userId,function(v) return Meta.transact(v,token,action,arg,today,draws,nextToken) end)
    return data and data.meta
end
-- Robux の購入で品とコインを渡して保存する。保存できた時だけ meta と "granted" / "already" を返す(できなければ nil)
function Service.grant(userId,purchaseId,ids,coins)
    local result
    local data=update(userId,function(v)
        v=Meta.clone(v or {})
        v.meta=Meta.normalize(v.meta)
        result=Meta.grantPurchase(v.meta,purchaseId,ids,coins)
        return v
    end)
    if not data then return nil end
    return data.meta,result
end
-- VIP の毎日のボーナスをメールで届けて保存する(その日にすでに届いていれば何もしない)。保存できたら true
function Service.vipDaily(userId,coins,today)
    local data=update(userId,function(v)
        v=Meta.clone(v or {})
        v.meta=Meta.normalize(v.meta)
        Meta.daily(v.meta,today)
        Meta.vipDaily(v.meta,today,coins)
        return v
    end)
    return data~=nil
end
return Service
