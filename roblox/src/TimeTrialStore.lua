-- タイムアタックの記録の保存場所(サーバーだけが書く)。
-- コースごとの世界ランキング: OrderedDataStore(キー = ユーザー ID、値 = タイムのミリ秒。小さいほど上)
-- コースごとの世界1位の走り(ゴースト): DataStore(キー = "lane0"〜"lane5"、値 = 入力の列)
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local suffix = RunService:IsStudio() and "_studio_v1" or "_v1"
local Store = { TOP = 100 }
local boards, ghosts = {}, DataStoreService:GetDataStore("MinatoTAGhost" .. suffix)
for lane = 0, 5 do
    boards[lane] = DataStoreService:GetOrderedDataStore("MinatoTA" .. lane .. suffix)
end
local cache, names = {}, {}
local CACHE_SECONDS = 60
-- ゴーストの入力の数の上限(4分の走りで十分な数。保存の大きさを抑える)
local MAX_INPUTS = 20000

-- 失敗したら少し待ってやり直す(最大3回)
local function retry(action)
    for attempt = 1, 3 do
        local ok, result = pcall(action)
        if ok then
            return true, result
        end
        if attempt < 3 then
            task.wait(attempt)
        end
    end
    return false, nil
end

-- 表示名をまとめて調べる(覚えておき、同じ人を何度も聞かない)
local function displayNames(userIds)
    local missing = {}
    for _, id in ipairs(userIds) do
        if names[id] == nil and id > 0 then
            table.insert(missing, id)
        end
    end
    for first = 1, #missing, 100 do
        local batch = table.move(missing, first, math.min(first + 99, #missing), 1, {})
        local ok, infos = retry(function()
            return UserService:GetUserInfosByUserIdsAsync(batch)
        end)
        if ok and type(infos) == "table" then
            for _, info in ipairs(infos) do
                names[info.Id] = info.DisplayName
            end
        end
    end
end

-- コースの上位100件(1分のあいだは覚えておいた物を返す)。戻り値: { {userId, ms, name}, ... } または nil
function Store.top(lane)
    local entry = cache[lane]
    if entry and os.clock() - entry.at < CACHE_SECONDS then
        return entry.rows
    end
    local ok, page = retry(function()
        return boards[lane]:GetSortedAsync(true, Store.TOP):GetCurrentPage()
    end)
    if not ok then
        return entry and entry.rows or nil
    end
    local rows, ids = {}, {}
    for _, item in ipairs(page) do
        local id = tonumber(item.key)
        if id then
            table.insert(rows, { userId = id, ms = item.value })
            table.insert(ids, id)
        end
    end
    displayNames(ids)
    for _, row in ipairs(rows) do
        row.name = names[row.userId] or "選手"
    end
    cache[lane] = { at = os.clock(), rows = rows }
    return rows
end

-- 上位100件の中での順位(同じタイムは同じ順位)。100件より下なら nil
function Store.rankOf(rows, ms)
    if type(rows) ~= "table" then
        return nil
    end
    local faster = 0
    for _, row in ipairs(rows) do
        if row.ms < ms then
            faster += 1
        end
    end
    if faster >= Store.TOP then
        return nil
    end
    if #rows >= Store.TOP and rows[#rows].ms < ms then
        return nil
    end
    return faster + 1
end

-- 確かめた記録を登録する。戻り値: { improved = 自己ベストを更新したか, best = 自己ベスト(ミリ秒), rank = 世界の順位か nil }
function Store.submit(userId, lane, seconds, record)
    local ms = math.max(1, math.floor(seconds * 1000 + 0.5))
    local improved, best = false, ms
    local ok = retry(function()
        return boards[lane]:UpdateAsync(tostring(userId), function(old)
            if type(old) == "number" and old <= ms then
                improved, best = false, old
                return nil
            end
            improved, best = true, ms
            return ms
        end)
    end)
    if not ok then
        return nil
    end
    -- 世界1位の走りが速くなったら、ゴーストを書き換える
    if improved and #record.inputs <= MAX_INPUTS then
        retry(function()
            return ghosts:UpdateAsync("lane" .. lane, function(old)
                if type(old) == "table" and type(old.ms) == "number" and old.ms <= ms then
                    return nil
                end
                return { userId = userId, ms = ms, lane = lane, tilt = record.tilt, inputs = record.inputs }
            end)
        end)
    end
    cache[lane] = nil
    local rows = Store.top(lane)
    return { improved = improved, best = best, rank = Store.rankOf(rows, best) }
end

-- コースの世界1位の走り(ゴースト)。無ければ nil
function Store.ghost(lane)
    local ok, value = retry(function()
        return ghosts:GetAsync("lane" .. lane)
    end)
    if ok and type(value) == "table" and value.lane == lane and type(value.inputs) == "table" then
        return value
    end
    return nil
end

return Store
