-- 待ち合わせの決まり(Roblox に依存しない純粋な計算)。1回の UpdateAsync で組の全員をまとめて確定する。
-- モード: ranked(シーズン。近いレートどうし) / online(レートなし) / event(日替わり。レートなし)
-- 出走の決まり(T17): 6人そろえばすぐ。2人以上なら最初の人が30秒待った時点で、残りを AI(達人)で埋める。
-- 1人だけなら60秒まで待ってから AI で埋める。
local Policy = {}
local MAX_WAITERS = 60
local WAIT_TTL = 25
local MATCH_TTL = 120
local GROUP_WAIT = 30
local SOLO_WAIT = 60
local FIELD = 6
-- 組が決まってから会場の鍵(access)が書き込まれるまでの猶予。過ぎたら組をほどいて待ち直しにする
-- (組を決めたロビーが会場の予約に失敗したり、止まったりした場合)
local ASSIGN_TTL = 15
Policy.ASSIGN_TTL = ASSIGN_TTL
Policy.GROUP_WAIT = GROUP_WAIT
Policy.SOLO_WAIT = SOLO_WAIT
Policy.MODES = { ranked = true, online = true, event = true }

-- シーズンで許すレートの差。10秒待つごとに100ずつ広げる
local function range(wait)
    return 100 * (1 + math.floor(math.max(0, wait) / 10))
end

-- 2人が同じ組に入れるか(シーズンだけレートの差を見る)
local function compatible(mode, now, a, b)
    if mode ~= "ranked" then
        return true
    end
    local delta = math.abs(a.rating - b.rating)
    return delta <= range(now - a.joined) and delta <= range(now - b.joined)
end

-- 集まった人数と最初の人の待ち時間から、出走してよいか
local function ready(count, waited)
    return count >= FIELD or (count >= 2 and waited >= GROUP_WAIT) or (count >= 1 and waited >= SOLO_WAIT)
end
Policy.ready = ready

-- 待っている人を、並んだ順(同じ時刻なら番号順)に並べる
local function waitingList(players)
    local waiting = {}
    for id, entry in pairs(players) do
        if not entry.match then
            table.insert(waiting, { id = id, entry = entry })
        end
    end
    table.sort(waiting, function(a, b)
        if a.entry.joined == b.entry.joined then
            return a.id < b.id
        end
        return a.entry.joined < b.entry.joined
    end)
    return waiting
end

-- 待ち行列を1回ぶん進める: 期限切れを消し、取り消しと新しい参加を反映し、そろった組を1つ確定する
function Policy.update(previous, now, localEntries, cancellations, matchId, mode)
    mode = mode or "ranked"
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
        local entry = players[id]
        if entry and entry.session == session and not entry.used then
            players[id] = nil
        end
    end
    local count = 0
    for _ in pairs(players) do
        count += 1
    end
    for id, candidate in pairs(localEntries) do
        local existing = players[id]
        if existing and existing.session == candidate.session then
            if not existing.match then
                existing.seen = now
            end
        elseif not existing and count < MAX_WAITERS then
            players[id] = { rating = candidate.rating, joined = now, seen = now, session = candidate.session }
            count += 1
        end
    end
    local waiting = waitingList(players)
    -- 後から来た人も、いちばん長く待っている人とのレート差を満たす必要がある
    for _, anchor in ipairs(waiting) do
        local selected = { anchor }
        for _, candidate in ipairs(waiting) do
            if candidate ~= anchor and compatible(mode, now, anchor.entry, candidate.entry) then
                table.insert(selected, candidate)
                if #selected == FIELD then
                    break
                end
            end
        end
        if ready(#selected, now - anchor.entry.joined) then
            for _, item in ipairs(selected) do
                item.entry.match = matchId
                item.entry.matchedAt = now
                item.entry.used = false
            end
            break
        end
    end
    return { players = players }
end

-- 待っている人に見せる「集まった人数」と「出走までの残り秒数」
-- 人数はその人と同じ組に入れる人(本人を含む。6人まで)。残りは、その中でいちばん長く待っている人が基準
function Policy.status(state, userId, now, mode)
    mode = mode or "ranked"
    if type(state) ~= "table" or type(state.players) ~= "table" then
        return nil
    end
    local me = state.players[tostring(userId)]
    if type(me) ~= "table" or me.match then
        return nil
    end
    local count, oldest = 0, me.joined
    for _, item in ipairs(waitingList(state.players)) do
        if item.entry == me or compatible(mode, now, me, item.entry) then
            count += 1
            oldest = math.min(oldest, item.entry.joined)
        end
    end
    count = math.min(count, FIELD)
    local limit = count >= 2 and GROUP_WAIT or SOLO_WAIT
    return { count = count, remaining = math.max(0, math.ceil(oldest + limit - now)) }
end

-- 組を決めたロビーが会場を予約したあと、その組の全員に会場の鍵と会場の番号を書き込む
function Policy.assign(previous, matchId, access, privateId)
    if type(previous) ~= "table" or type(previous.players) ~= "table" then
        return nil
    end
    local players, changed = {}, false
    for id, entry in pairs(previous.players) do
        local copy = table.clone(entry)
        if copy.match == matchId and not copy.access then
            copy.access, copy.privateId = access, privateId
            changed = true
        end
        players[id] = copy
    end
    if not changed then
        return nil
    end
    return { players = players }
end

-- 会場の予約に失敗した時、その組をほどいて待ち直しにする(待った時間は保つ)
function Policy.release(previous, matchId, now)
    if type(previous) ~= "table" or type(previous.players) ~= "table" then
        return nil
    end
    local players = {}
    for id, entry in pairs(previous.players) do
        local copy = table.clone(entry)
        if copy.match == matchId and not copy.access then
            copy.match, copy.matchedAt, copy.used = nil, nil, nil
            copy.seen = now
        end
        players[id] = copy
    end
    return { players = players }
end

-- 会場側で、その会場に割り当てられた参加者かを確かめ、入場を使用済みにする
function Policy.accept(previous, now, userId, privateId)
    if type(previous) ~= "table" or type(previous.players) ~= "table" then
        return nil
    end
    local id = tostring(userId)
    local entry = previous.players[id]
    if
        not entry
        or not entry.match
        or entry.privateId == nil
        or entry.privateId ~= privateId
        or entry.used
        or entry.matchedAt + MATCH_TTL <= now
    then
        return nil
    end
    local state = { players = table.clone(previous.players) }
    state.players[id] = table.clone(entry)
    state.players[id].used = true
    return state
end

-- 会場側で、この会場に来る予定の人数を数える(全員そろえば20秒を待たずに始められる)
function Policy.expected(state, privateId)
    if type(state) ~= "table" or type(state.players) ~= "table" then
        return 0
    end
    local n = 0
    for _, entry in pairs(state.players) do
        if entry.privateId == privateId then
            n += 1
        end
    end
    return n
end

return Policy
