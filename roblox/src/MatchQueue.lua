-- 待ち行列の保存場所。モードごとに MemoryStore のソート済みマップの1項目へまとめて置く(上限つきの試作)。
-- 公開していない Studio では MemoryStore が使えないので、同じ決まり(MatchPolicy)をサーバーの中の表で動かす。
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local policy = require(script.Parent:WaitForChild("MatchPolicy"))
local localOnly = RunService:IsStudio() and (game.GameId == 0 or not workspace:GetAttribute("MinatoLiveData"))
local map = not localOnly
    and MemoryStoreService:GetSortedMap(RunService:IsStudio() and "MinatoRankQueue_studio_v1" or "MinatoRankQueue_v1")
local memory = {}
local Queue = { localOnly = localOnly }

-- モードごとの項目名(ranked は以前と同じ "queue" のまま)
local function key(mode)
    if mode == "online" then
        return "online"
    elseif mode == "event" then
        return "event"
    end
    return "queue"
end

-- 項目を1つ、まとめて書き換える。fn が nil を返したら書き換えない
local function update(mode, fn)
    if localOnly then
        local nextState = fn(memory[key(mode)])
        if nextState ~= nil then
            memory[key(mode)] = nextState
        end
        return true, nextState or memory[key(mode)]
    end
    return pcall(function()
        return map:UpdateAsync(key(mode), function(old)
            local nextState = fn(old)
            if nextState == nil then
                return nil
            end
            return nextState, 0
        end, 900)
    end)
end

-- 待っている人の更新と組の確定。戻り値: 新しい状態(失敗は nil)、この呼び出しで使った組の番号
function Queue.update(localEntries, cancellations, mode)
    local now = os.time()
    local matchId = HttpService:GenerateGUID(false)
    local ok, result = update(mode, function(old)
        return policy.update(old, now, localEntries, cancellations, matchId, mode)
    end)
    return ok and result or nil, matchId
end

-- 予約した会場の鍵を、その組の全員に書き込む
function Queue.assign(matchId, access, privateId, mode)
    local ok, result = update(mode, function(old)
        return policy.assign(old, matchId, access, privateId)
    end)
    return ok and result ~= nil
end

-- 会場の予約に失敗した組を待ち直しにする
function Queue.release(matchId, mode)
    local now = os.time()
    update(mode, function(old)
        return policy.release(old, matchId, now)
    end)
end

-- 会場側の入場の確認。戻り値: 入れてよいか、この会場に来る予定の人数
function Queue.accept(userId, privateId, mode)
    if type(privateId) ~= "string" or privateId == "" then
        return false, 0
    end
    local marker = HttpService:GenerateGUID(false)
    local ok, result = update(mode, function(old)
        local nextState = policy.accept(old, os.time(), userId, privateId)
        if not nextState then
            return nil
        end
        nextState.players[tostring(userId)].acceptedMarker = marker
        return nextState
    end)
    local entry = ok and result and result.players and result.players[tostring(userId)]
    local admitted = type(entry) == "table" and entry.acceptedMarker == marker
    return admitted, admitted and policy.expected(result, privateId) or 0
end

return Queue
