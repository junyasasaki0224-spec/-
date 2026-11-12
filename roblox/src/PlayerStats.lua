-- All writes originate on the server. Each race is applied once per player.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local calculateRating = require(script.Parent:WaitForChild("Rating"))
local rules = require(script.Parent:WaitForChild("ResultRules"))

local suffix = RunService:IsStudio() and "_studio_v1" or "_v1"
local profiles = DataStoreService:GetDataStore("MinatoStats"..suffix)
local ordered = {
    rating = DataStoreService:GetOrderedDataStore("MinatoRating"..suffix),
    wins = DataStoreService:GetOrderedDataStore("MinatoWins"..suffix),
    bestTime = DataStoreService:GetOrderedDataStore("MinatoBestTimeMs"..suffix),
}
local VERSION_BASE = 1000000000
local pending = 0
local rankingJobs = {}
local resultQueues = {}
local Stats = {ordered = ordered, versionBase = VERSION_BASE}

local function retry(action)
    local lastError
    for attempt = 1, 5 do
        local ok, result = pcall(action)
        if ok then return result end
        lastError = result
        if attempt < 5 then task.wait(math.min(2^(attempt-1),8)) end
    end
    return nil, tostring(lastError)
end

local function updateRankings(userId, profile)
    local key = tostring(userId)
    -- The version prevents an older server's delayed write from replacing a newer rating.
    local encoded = math.clamp(math.floor(profile.rating+0.5),0,1000000)*VERSION_BASE + profile.version
    local okRating = retry(function()
        return ordered.rating:UpdateAsync(key,function(old)
            if old and old%VERSION_BASE >= profile.version then return old end
            return encoded
        end)
    end)
    local okWins = retry(function()
        return ordered.wins:UpdateAsync(key,function(old) return math.max(old or 0,profile.wins) end)
    end)
    local okBest = true
    if profile.bestTime then
        local millis = math.max(1,math.floor(profile.bestTime*1000+0.5))
        okBest = retry(function()
            return ordered.bestTime:UpdateAsync(key,function(old) return old and math.min(old,millis) or millis end)
        end)
    end
    return okRating ~= nil and okWins ~= nil and okBest ~= nil
end

local function scheduleRankingSync(userId, profile)
    local existing = rankingJobs[userId]
    if existing then
        if profile.version > existing.profile.version then existing.profile=profile end
        return
    end
    local job = {profile=profile}
    rankingJobs[userId]=job
    pending += 1
    task.spawn(function()
        while true do
            local snapshot=job.profile
            local ok=updateRankings(userId,snapshot)
            if ok and job.profile==snapshot then break end
            if not ok then warn("Minato ranking sync failed; retrying"); task.wait(30) end
        end
        rankingJobs[userId]=nil
        pending -= 1
    end)
end

function Stats.load(userId)
    local key = tostring(userId)
    local value, err = retry(function() return profiles:GetAsync(key) end)
    if err then return nil,err end
    return rules.normalize(value)
end

function Stats.ensure(userId)
    local profile, err = retry(function()
        return profiles:UpdateAsync(tostring(userId),function(value,info)
            local userIds=userId>0 and {userId} or {}
            return rules.normalize(value),userIds,info and info:GetMetadata() or {}
        end)
    end)
    if not profile then return nil,err end
    scheduleRankingSync(userId,profile)
    return profile
end

local function applyResult(userId, result, raceId, change)
    local profile, err = retry(function()
        return profiles:UpdateAsync(tostring(userId),function(value,info)
            local userIds=userId>0 and {userId} or {}
            return rules.apply(value,result,raceId,change),userIds,info and info:GetMetadata() or {}
        end)
    end)
    if not profile then return false,err end
    scheduleRankingSync(userId,profile)
    return true
end

local function queueResult(result, raceId, change)
    local userId=result.userId
    local queue=resultQueues[userId]
    if not queue then queue={}; resultQueues[userId]=queue end
    table.insert(queue,{result=result,raceId=raceId,change=change})
    pending += 1
    if #queue > 1 then return end
    task.spawn(function()
        while #queue > 0 do
            local item=queue[1]
            local ok,err=applyResult(userId,item.result,item.raceId,item.change)
            if ok then
                table.remove(queue,1)
                pending -= 1
            else
                warn("Minato result save failed: "..tostring(err))
                task.wait(20)
            end
        end
        resultQueues[userId]=nil
    end)
end

function Stats.recordRace(raceId, participants, ranked)
    -- Loading every opponent can yield or fail; retry without blocking Heartbeat.
    pending += 1
    task.spawn(function()
        local eligible = {}
        if ranked then
            while true do
                eligible = {}
                local complete = true
                for _, result in ipairs(participants) do
                    local profile = Stats.load(result.userId)
                    if not profile then complete=false; break end
                    eligible[#eligible+1] = {rating=profile.rating,place=result.place}
                end
                if complete then break end
                warn("Minato ranked ratings unavailable; retrying")
                task.wait(20)
            end
        end
        local changes = ranked and calculateRating(eligible) or {}
        for i, result in ipairs(participants) do
            queueResult(result,raceId,changes[i] or 0)
        end
        pending -= 1
    end)
    return true
end

function Stats.waitForPending(seconds)
    local untilTime = os.clock()+seconds
    while pending > 0 and os.clock() < untilTime do task.wait(0.25) end
    if pending > 0 then warn("Minato has pending result or ranking updates at shutdown") end
    return pending == 0
end
game:BindToClose(function()
    task.wait(0.2)
    Stats.waitForPending(24)
end)

return Stats
