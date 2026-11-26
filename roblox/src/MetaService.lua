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
-- 購入や VIP のボーナスで中身が変わった回数(ロビーが前に返した持ち物を使い回してよいかの目印)
local versions={}
function Service.version(userId)
    return versions[userId] or 0
end
local function bump(userId)
    versions[userId]=(versions[userId] or 0)+1
end
-- 検証用: 全部の品(ガチャ・VIP の品)を倉庫で使えるようにする。Studio と、このゲームの持ち主だけ。
-- (VIP 会員が切れた時に VIP の品が外れるかを Studio で試す時は、一時的に false にする)
-- 持ち物の記録(own)は変えない(ガチャの重複などは本当の持ち物で決まる)。公開する前に false にする(PUBLISH.md)
local TEST_UNLOCK_ALL=true
local function testUnlock(userId)
    if not TEST_UNLOCK_ALL then return false end
    if RunService:IsStudio() then return true end
    return game.CreatorType==Enum.CreatorType.User and game.CreatorId==userId
end
-- 保存の前に、解放の印をその時の決まりで付け直す(false にすれば次の読み込みで消える)
local function mark(v,userId)
    v.meta.testUnlock=testUnlock(userId) or nil
    return v
end
-- Roblox のバッジ(ShopConfig.badges に番号がある物だけ)を、届いた級のぶん渡す。渡し終えた物は meta.awarded に覚える
local BadgeService=game:GetService("BadgeService")
local badgeIds=require(game:GetService("ReplicatedStorage"):WaitForChild("ShopConfig")).badges or {}
local awarding={}
local function awardBadges(userId,meta)
    if awarding[userId] or type(meta.badges)~="table" then return end
    local todo={}
    for _,name in ipairs(meta.badges) do
        local id=badgeIds[name]
        if type(id)=="number" and id>0 and not (type(meta.awarded)=="table" and table.find(meta.awarded,name)) then table.insert(todo,{name=name,id=id}) end
    end
    if #todo==0 then return end
    awarding[userId]=true
    task.spawn(function()
        local done={}
        for _,b in ipairs(todo) do
            local ok,has=pcall(BadgeService.UserHasBadgeAsync,BadgeService,userId,b.id)
            if ok and not has then ok=pcall(BadgeService.AwardBadge,BadgeService,userId,b.id) end
            if ok then table.insert(done,b.name) end
        end
        if #done>0 then
            update(userId,function(v)
                v=Meta.clone(v or {})
                v.meta=Meta.normalize(v.meta)
                if type(v.meta.awarded)~="table" then v.meta.awarded={} end
                for _,name in ipairs(done) do if not table.find(v.meta.awarded,name) then table.insert(v.meta.awarded,name) end end
                return mark(v,userId)
            end)
        end
        awarding[userId]=nil
    end)
end
function Service.get(userId)
    local token=HttpService:GenerateGUID(false)
    local today=day()
    -- S の線(ロビーの順位表が出す。会場のサーバーにはないので、その時は S の印を変えない)
    local cutoff=game:GetService("ReplicatedStorage"):GetAttribute("MinatoSCutoff")
    local data=update(userId,function(v)
        v=Meta.clone(v or {})
        v.meta=Meta.normalize(v.meta)
        v.meta.token=v.meta.token or token
        Meta.daily(v.meta,today)
        Meta.updateS(v.meta,cutoff)
        return mark(v,userId)
    end)
    if data and data.meta and userId>0 then awardBadges(userId,data.meta) end
    return data and data.meta
end
function Service.action(userId,token,action,arg)
    local random=Random.new()
    local draws={}
    for i=1,20 do draws[i]=random:NextNumber() end
    local nextToken=HttpService:GenerateGUID(false)
    local today=day()
    local data=update(userId,function(v)
        v=Meta.clone(v or {})
        v.meta=Meta.normalize(v.meta)
        mark(v,userId)
        return Meta.transact(v,token,action,arg,today,draws,nextToken)
    end)
    return data and data.meta
end
-- Robux の購入で品とコインを渡して保存する。保存できた時だけ meta と "granted" / "already" を返す(できなければ nil)
function Service.grant(userId,purchaseId,ids,coins)
    bump(userId)
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
-- VIP 会員かどうかの印を保存する(サーバーが Roblox に確かめた結果だけを入れる)。
-- 会員でなくなったら、着ていた VIP の品をスタンダードに戻す(Meta.setVip)。保存できたら meta、できなければ nil
function Service.setVip(userId,isVip)
    bump(userId)
    local data=update(userId,function(v)
        v=Meta.clone(v or {})
        v.meta=Meta.normalize(v.meta)
        Meta.setVip(v.meta,isVip==true)
        return v
    end)
    return data and data.meta
end
-- VIP の毎日のボーナスをメールで届けて保存する(その日にすでに届いていれば何もしない)。保存できたら true
function Service.vipDaily(userId,coins,today)
    bump(userId)
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
