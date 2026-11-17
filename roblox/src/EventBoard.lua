-- イベント内のランキング(日替わり)。イベントのレースの着順で得点(10・8・6・4・2・1、失格0)を足し、その日の合計で並べる。
-- MemoryStore のソート済みマップに日付ごとに置く(2日で自動で消える。キー = ユーザー ID、並びの値 = -得点)。
-- 公開していない Studio ではサーバー内の表で同じように動く。
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local localOnly = RunService:IsStudio() and (game.GameId == 0 or not workspace:GetAttribute("MinatoLiveData"))
local suffix = RunService:IsStudio() and "_studio_v1" or "_v1"
local LIFETIME = 2 * 24 * 60 * 60
local Board = { POINTS = { 10, 8, 6, 4, 2, 1 }, TOP = 100 }
local memory, cache = {}, {}

-- 着順から得点(失格は0点)
function Board.points(place, out)
    if out then
        return 0
    end
    return Board.POINTS[place] or 0
end

-- その日のマップ(日付は日本時間の "YYYY-MM-DD")
local function map(day)
    return MemoryStoreService:GetSortedMap("MinatoEventBoard_" .. day .. suffix)
end

-- イベントの1レースの得点を足す
function Board.add(day, userId, name, points)
    local key = tostring(userId)
    local function apply(old)
        local value = type(old) == "table" and table.clone(old) or { points = 0, races = 0 }
        value.points += points
        value.races += 1
        value.name = name
        return value
    end
    if localOnly then
        memory[day] = memory[day] or {}
        memory[day][key] = apply(memory[day][key])
        cache[day] = nil
        -- Studio だけ: 確かめやすいように、その日の表をワークスペースの属性にも写す
        workspace:SetAttribute("MinatoEventBoardStudio", game:GetService("HttpService"):JSONEncode(memory[day]))
        return true
    end
    for attempt = 1, 3 do
        local ok = pcall(function()
            map(day):UpdateAsync(key, function(old)
                local value = apply(old)
                return value, -value.points
            end, LIFETIME)
        end)
        if ok then
            cache[day] = nil
            return true
        end
        task.wait(attempt)
    end
    return false
end

-- その日の上位100人(30秒のあいだは覚えておいた物を返す)。戻り値: { {userId, name, points, races, rank}, ... } または nil
function Board.top(day)
    local entry = cache[day]
    if entry and os.clock() - entry.at < 30 then
        return entry.rows
    end
    local items = {}
    if localOnly then
        for key, value in pairs(memory[day] or {}) do
            table.insert(items, { key = key, value = value })
        end
    else
        local ok, result = pcall(function()
            return map(day):GetRangeAsync(Enum.SortDirection.Ascending, Board.TOP)
        end)
        if not ok then
            return entry and entry.rows or nil
        end
        items = result
    end
    local rows = {}
    for _, item in ipairs(items) do
        local id = tonumber(item.key)
        if id and type(item.value) == "table" then
            table.insert(rows, { userId = id, name = item.value.name or "選手", points = item.value.points or 0, races = item.value.races or 0 })
        end
    end
    table.sort(rows, function(a, b)
        if a.points ~= b.points then
            return a.points > b.points
        end
        return a.userId < b.userId
    end)
    -- 同じ得点は同じ順位
    for i, row in ipairs(rows) do
        row.rank = (i > 1 and rows[i - 1].points == row.points) and rows[i - 1].rank or i
    end
    cache[day] = { at = os.clock(), rows = rows }
    return rows
end

return Board
