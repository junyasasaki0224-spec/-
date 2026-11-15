-- 大会の記録の置き場所(サーバーだけが読み書きする)。
-- 進行中: MemoryStore のソート済みマップ(キー = 大会の番号、値 = 記録)。終わった大会の結果: DataStore。
-- 公開していない Studio では MemoryStore / DataStore が使えないので、サーバーの中の表で同じように動かす。
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local localOnly = RunService:IsStudio() and game.GameId == 0
local suffix = RunService:IsStudio() and "_studio_v1" or "_v1"
local map = not localOnly and MemoryStoreService:GetSortedMap("MinatoTournaments" .. suffix)
local results = not localOnly and DataStoreService:GetDataStore("MinatoTournamentResults" .. suffix)
-- 記録は6時間で消える(終わった大会も「終了」のタブにしばらく出す)
local LIFETIME = 6 * 60 * 60
local memory = {}
local Store = { localOnly = localOnly }
local listCache, listAt = nil, -math.huge

-- 1つの大会を書き換える。fn が nil を返したら書き換えない。戻り値: 書き換えた後の記録(失敗・取り消しは nil)
function Store.update(id, fn)
    if type(id) ~= "string" or #id > 64 then
        return nil
    end
    listAt = -math.huge
    if localOnly then
        local copy = memory[id] and table.clone(memory[id]) or nil
        local nextValue = fn(copy)
        if nextValue ~= nil then
            memory[id] = nextValue
        end
        return nextValue
    end
    local changed = nil
    local ok = pcall(function()
        map:UpdateAsync(id, function(old)
            local nextValue = fn(old)
            changed = nextValue
            return nextValue
        end, LIFETIME)
    end)
    return ok and changed or nil
end

-- 1つの大会を読む
function Store.get(id)
    if type(id) ~= "string" or #id > 64 then
        return nil
    end
    if localOnly then
        return memory[id] and table.clone(memory[id]) or nil
    end
    local ok, value = pcall(map.GetAsync, map, id)
    return ok and value or nil
end

-- すべての大会(3秒のあいだは覚えておいた一覧を返す。上限200件)
function Store.list()
    if os.clock() - listAt < 3 and listCache then
        return listCache
    end
    local list = {}
    if localOnly then
        for _, record in pairs(memory) do
            table.insert(list, table.clone(record))
        end
    else
        local ok, items = pcall(map.GetRangeAsync, map, Enum.SortDirection.Ascending, 200)
        if not ok then
            return listCache
        end
        for _, item in ipairs(items) do
            table.insert(list, item.value)
        end
    end
    listCache, listAt = list, os.clock()
    return list
end

-- 終わった大会の結果を残す(名前・主催者・優勝者・得点表)
function Store.saveResult(record)
    if localOnly then
        return true
    end
    local summary = {
        name = record.name, hostName = record.hostName, format = record.format, champion = record.champion,
        finishedAt = record.finishedAt, points = record.points, entrants = record.entrants, finalResults = record.finalResults,
    }
    -- 参加者のユーザー ID を結び付けておく(データ削除の依頼に応えられるように)
    local userIds = {}
    for _, e in ipairs(record.entrants) do
        table.insert(userIds, e.userId)
    end
    for _ = 1, 3 do
        local ok = pcall(results.SetAsync, results, record.id, summary, userIds)
        if ok then
            return true
        end
        task.wait(2)
    end
    return false
end

return Store
