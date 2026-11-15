local Meta = if script then require(game:GetService("ReplicatedStorage"):WaitForChild("Meta")) else require("./Meta")
local Rules = {}

function Rules.normalize(value)
    if type(value) ~= "table" then value = {} end
    local data = table.clone(value)
    data.rating = type(value.rating) == "number" and value.rating or 1500
    data.races = type(value.races) == "number" and value.races or 0
    data.wins = type(value.wins) == "number" and value.wins or 0
    data.bestTime = type(value.bestTime) == "number" and value.bestTime or nil
    data.version = type(value.version) == "number" and value.version or 0
    data.recentRaces = type(value.recentRaces) == "table" and table.clone(value.recentRaces) or {}
    return data
end

function Rules.apply(value, result, raceId, change)
    local data = Rules.normalize(value)
    for _, id in ipairs(data.recentRaces) do if id == raceId then return data end end
    data.meta=Meta.normalize(data.meta)
    Meta.daily(data.meta,result.day)
    Meta.result(data.meta,result)
    data.races += 1
    if result.won then data.wins += 1 end
    if result.time and (not data.bestTime or result.time < data.bestTime) then data.bestTime = result.time end
    data.rating = math.clamp(data.rating+change,0,1000000)
    data.version += 1
    table.insert(data.recentRaces,raceId)
    if #data.recentRaces > 128 then table.remove(data.recentRaces,1) end
    return data
end

-- Only assigned racers count. An empty practice field must still run normally.
function Rules.shouldEnd(boats, clock, aloneSince)
    local hasHuman, survivingHuman, racing = false, false, false
    for _, b in ipairs(boats) do
        if b.humanUserId then
            hasHuman = true
            if not b.out then survivingHuman = true end
        end
        if not b.out and not b.finished then racing = true end
    end
    if hasHuman and not survivingHuman then aloneSince = aloneSince or clock else aloneSince = nil end
    return not racing or (aloneSince ~= nil and clock-aloneSince >= 10), aloneSince
end

-- 人間だけの着順を付ける(results は全体の着順に並んでいる)。シーズンのレートはこの順位だけで決める
function Rules.rankHumans(results)
    for k, r in ipairs(results) do
        r.humans, r.humanPlace = #results, k
    end
    return results
end

function Rules.entry(b, position)
    return {userId=b.humanUserId, place=b.out and 6 or position, out=b.out, st=b.startTime, lane=(b.number or 1)-1,
        won=not b.out and b.finished and b.place==1,
        time=not b.out and b.finished and b.finishTime or nil}
end

return Rules
