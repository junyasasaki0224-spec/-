-- The single sorted-map item is a deliberately bounded, atomic pilot queue.
local MemoryStoreService=game:GetService("MemoryStoreService")
local RunService=game:GetService("RunService")
local HttpService=game:GetService("HttpService")
local policy=require(script.Parent:WaitForChild("MatchPolicy"))
local map=MemoryStoreService:GetSortedMap(RunService:IsStudio() and "MinatoRankQueue_studio_v1" or "MinatoRankQueue_v1")
local Queue={}
function Queue.update(localEntries,cancellations)
    local now=os.time()
    local matchId=HttpService:GenerateGUID(false)
    local ok,result=pcall(function()
        return map:UpdateAsync("queue",function(old)
            return policy.update(old,now,localEntries,cancellations,matchId),0
        end,900)
    end)
    return ok and result or nil, matchId
end
function Queue.assign(matchId,access,privateId)
    local ok,result=pcall(function()
        return map:UpdateAsync("queue",function(old)
            local nextState=policy.assign(old,matchId,access,privateId)
            if not nextState then return nil end
            return nextState,0
        end,900)
    end)
    return ok and result ~= nil
end
function Queue.release(matchId)
    local now=os.time()
    pcall(function()
        return map:UpdateAsync("queue",function(old)
            local nextState=policy.release(old,matchId,now)
            if not nextState then return nil end
            return nextState,0
        end,900)
    end)
end
function Queue.accept(userId,privateId)
    if type(privateId) ~= "string" or privateId == "" then return false end
    local marker=HttpService:GenerateGUID(false)
    local ok,result=pcall(function()
        return map:UpdateAsync("queue",function(old)
            local nextState=policy.accept(old,os.time(),userId,privateId)
            if not nextState then return nil end
            nextState.players[tostring(userId)].acceptedMarker=marker
            return nextState,0
        end,900)
    end)
    local entry=ok and result and result.players and result.players[tostring(userId)]
    return entry ~= nil and entry.acceptedMarker == marker
end
return Queue
