-- Pure, deterministic queue policy. One UpdateAsync commits every selected participant.
local Policy = {}
local MAX_WAITERS = 60
local WAIT_TTL = 25
local MATCH_TTL = 120
-- 組が決まってから会場の鍵(access)が書き込まれるまでの猶予。過ぎたら組をほどいて待ち直しにする
-- (組を決めたロビーが会場の予約に失敗したり、止まったりした場合)
local ASSIGN_TTL = 15
Policy.ASSIGN_TTL = ASSIGN_TTL
local function range(wait)
    return 100 * (1 + math.floor(math.max(0,wait)/10))
end
function Policy.update(previous, now, localEntries, cancellations, matchId)
    local old = type(previous) == "table" and previous or {}
    local players = {}
    for id, entry in pairs(old.players or {}) do
        local deadline = entry.match and (entry.matchedAt + MATCH_TTL) or (entry.seen + WAIT_TTL)
        if deadline > now then
            local copy = table.clone(entry)
            if copy.match and not copy.access and copy.matchedAt + ASSIGN_TTL <= now then
                copy.match, copy.matchedAt, copy.used = nil, nil, nil
                copy.seen = now
            end
            players[id] = copy
        end
    end
    for id, session in pairs(cancellations) do
        local entry=players[id]
        if entry and entry.session==session and not entry.used then players[id]=nil end
    end
    local count=0
    for _ in pairs(players) do count += 1 end
    for id, candidate in pairs(localEntries) do
        local existing=players[id]
        if existing and existing.session == candidate.session then
            if not existing.match then existing.seen=now end
        elseif not existing and count < MAX_WAITERS then
            players[id]={rating=candidate.rating, joined=now, seen=now, session=candidate.session}
            count += 1
        end
    end
    local waiting={}
    for id,entry in pairs(players) do
        if not entry.match then table.insert(waiting,{id=id,entry=entry}) end
    end
    table.sort(waiting,function(a,b)
        if a.entry.joined == b.entry.joined then return a.id < b.id end
        return a.entry.joined < b.entry.joined
    end)
    -- A newer arrival must also accept the oldest player's current rating difference.
    for _, anchor in ipairs(waiting) do
        local selected={anchor}
        for _, candidate in ipairs(waiting) do
            if candidate ~= anchor then
                local delta=math.abs(anchor.entry.rating-candidate.entry.rating)
                if delta <= range(now-anchor.entry.joined) and delta <= range(now-candidate.entry.joined) then
                    table.insert(selected,candidate)
                    if #selected == 6 then break end
                end
            end
        end
        if #selected == 6 or now-anchor.entry.joined >= 30 then
            for _, item in ipairs(selected) do
                item.entry.match=matchId
                item.entry.matchedAt=now
                item.entry.used=false
            end
            break
        end
    end
    return {players=players}
end
-- 組を決めたロビーが会場を予約したあと、その組の全員に会場の鍵と会場の番号を書き込む
function Policy.assign(previous, matchId, access, privateId)
    if type(previous) ~= "table" or type(previous.players) ~= "table" then return nil end
    local players, changed = {}, false
    for id, entry in pairs(previous.players) do
        local copy = table.clone(entry)
        if copy.match == matchId and not copy.access then
            copy.access, copy.privateId = access, privateId
            changed = true
        end
        players[id] = copy
    end
    if not changed then return nil end
    return {players=players}
end
-- 会場の予約に失敗した時、その組をほどいて待ち直しにする(待った時間は保つ)
function Policy.release(previous, matchId, now)
    if type(previous) ~= "table" or type(previous.players) ~= "table" then return nil end
    local players = {}
    for id, entry in pairs(previous.players) do
        local copy = table.clone(entry)
        if copy.match == matchId and not copy.access then
            copy.match, copy.matchedAt, copy.used = nil, nil, nil
            copy.seen = now
        end
        players[id] = copy
    end
    return {players=players}
end
-- 会場側で、その会場に割り当てられた参加者かを確かめ、入場を使用済みにする
function Policy.accept(previous, now, userId, privateId)
    if type(previous) ~= "table" or type(previous.players) ~= "table" then return nil end
    local id=tostring(userId)
    local entry=previous.players[id]
    if not entry or not entry.match or entry.privateId == nil or entry.privateId ~= privateId
        or entry.used or entry.matchedAt+MATCH_TTL <= now then return nil end
    local state={players=table.clone(previous.players)}
    state.players[id]=table.clone(entry)
    state.players[id].used=true
    return state
end
return Policy
