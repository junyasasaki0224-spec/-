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
    data.races += 1
    if result.won then data.wins += 1 end
    if result.time and (not data.bestTime or result.time < data.bestTime) then data.bestTime = result.time end
    data.rating = math.clamp(data.rating+change,0,1000000)
    data.version += 1
    table.insert(data.recentRaces,raceId)
    if #data.recentRaces > 128 then table.remove(data.recentRaces,1) end
    return data
end

return Rules
