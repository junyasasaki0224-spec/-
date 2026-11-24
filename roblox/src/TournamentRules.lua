-- 大会(T17 ③)の決まり。Roblox に依存しない純粋な計算(公式 Luau CLI の単体テストでも動く)。
-- 大会の記録(record)は MemoryStore に置く1つの表。会場の鍵(access / privateId)はサーバーだけが見る。
local R = {}
R.SIZES = { 6, 12, 18, 24 }
R.FORMATS = {
    heats2 = { name = "予選2走+優勝戦", heats = 2 },
    single = { name = "1レース勝負", heats = 1 },
}
-- 開始: 0 は「人数がそろったら」、ほかは作ってから何分後か
R.STARTS = { 0, 5, 15, 30 }
R.POINTS = { 10, 8, 6, 4, 2, 1 }
R.NAME_MAX = 20
R.CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
-- 受付のまま2時間たったら中止(人数がそろわない大会を残さない)
R.OPEN_LIFETIME = 2 * 60 * 60
-- 会場の予約を始めたロビーが止まった時、ほかのロビーがやり直してよいまでの秒数
R.CLAIM_TIMEOUT = 60
-- 予選が終わった組がほかの組を待つ上限(会場が落ちた組があっても優勝戦へ進む)
R.HEAT_WAIT = 300
R.ACTIVE = { open = true, starting = true, running = true, final = true }

-- 作る時の5項目を確かめてそろえる。戻り値: 整えた値、または nil と理由
function R.validate(params)
    if type(params) ~= "table" then
        return nil, "内容を確かめてください"
    end
    local name = params.name
    if type(name) ~= "string" then
        return nil, "大会名を入れてください"
    end
    -- とても長い文字は、整える前に断る(サーバーの手間を増やさない)
    if #name > 240 then
        return nil, "大会名は" .. R.NAME_MAX .. "文字までです"
    end
    name = name:gsub("[%c]", ""):match("^%s*(.-)%s*$")
    local length = utf8.len(name)
    if not length or length < 1 then
        return nil, "大会名を入れてください"
    end
    if length > R.NAME_MAX then
        return nil, "大会名は" .. R.NAME_MAX .. "文字までです"
    end
    if not table.find(R.SIZES, params.size) then
        return nil, "人数を選んでください"
    end
    if not R.FORMATS[params.format] then
        return nil, "形式を選んでください"
    end
    if not table.find(R.STARTS, params.start) then
        return nil, "開始を選んでください"
    end
    if type(params.private) ~= "boolean" then
        return nil, "公開のしかたを選んでください"
    end
    return { name = name, size = params.size, format = params.format, start = params.start, private = params.private }
end

-- 6文字の合言葉(紛らわしい O/0/I/1 は使わない)。random(n) は 1〜n の整数を返す関数
function R.newCode(random)
    local code = ""
    for _ = 1, 6 do
        local n = random(#R.CODE_CHARS)
        code ..= string.sub(R.CODE_CHARS, n, n)
    end
    return code
end

-- 新しい大会。主催者は最初の参加者になる
function R.new(id, host, hostName, params, now, code)
    return {
        id = id, name = params.name, host = host, hostName = hostName, size = params.size,
        format = params.format, start = params.start, startAt = params.start > 0 and now + params.start * 60 or nil,
        private = params.private, code = params.private and code or nil, created = now, status = "open",
        entrants = { { userId = host, name = hostName, joined = now } },
        points = {}, history = {}, best = {}, groups = nil, finalists = nil, champion = nil,
    }
end

function R.findEntrant(record, userId)
    for i, e in ipairs(record.entrants) do
        if e.userId == userId then
            return i, e
        end
    end
    return nil
end

-- 参加(受付中だけ。合言葉の大会はコードが合う時だけ)。戻り値: 成功したか、理由
function R.join(record, userId, name, code, now)
    if record.status ~= "open" then
        return false, "受付は終わっています"
    end
    if R.findEntrant(record, userId) then
        return false, "すでに参加しています"
    end
    if #record.entrants >= record.size then
        return false, "満員です"
    end
    if record.private and code ~= record.code then
        return false, "合言葉が違います"
    end
    table.insert(record.entrants, { userId = userId, name = name, joined = now })
    return true
end

-- 参加をやめる(受付中だけ。主催者はやめられない。中止を使う)
function R.leave(record, userId)
    if record.status ~= "open" or userId == record.host then
        return false
    end
    local i = R.findEntrant(record, userId)
    if not i then
        return false
    end
    table.remove(record.entrants, i)
    return true
end

-- 始めてよいか: 満員、決めた時刻になった、または主催者が「開始を早める」を押した
function R.shouldStart(record, now)
    if record.status ~= "open" then
        return false
    end
    return #record.entrants >= record.size
        or record.startNow == true
        or (record.startAt ~= nil and now >= record.startAt)
end

-- 受付のまま長くたった大会は中止する
function R.expired(record, now)
    return record.status == "open" and now - record.created >= R.OPEN_LIFETIME
end

-- 人数を6人までの組に分ける(できるだけ同じ人数。参加した順に組へ順番に配る)
function R.makeGroups(record)
    local n = #record.entrants
    local g = math.max(1, math.ceil(n / 6))
    local groups = {}
    for k = 1, g do
        groups[k] = { members = {}, heatsDone = 0 }
    end
    for i, e in ipairs(record.entrants) do
        table.insert(groups[(i - 1) % g + 1].members, e.userId)
        record.points[tostring(e.userId)] = 0
        record.history[tostring(e.userId)] = {}
        record.best[tostring(e.userId)] = 9
    end
    record.groups = groups
    return groups
end

function R.heatsPerGroup(record)
    return R.FORMATS[record.format].heats
end

-- 優勝戦をするか: 予選2走+優勝戦はいつも、1レース勝負は7人以上の時だけ
function R.needsFinal(record)
    return record.format == "heats2" or #record.entrants > 6
end

-- 予選1走の結果を足す。results = { {userId, place(1〜6), out(失格なら文字)} }(人間だけ)
-- 失格は0点。同じ組の同じ走りを二度足さない(heat はその組の何走目か)
function R.addHeat(record, group, heat, results)
    local g = record.groups and record.groups[group]
    if not g or heat ~= g.heatsDone + 1 then
        return false
    end
    for _, r in ipairs(results) do
        local key = tostring(r.userId)
        if record.points[key] ~= nil then
            local pts = (not r.out and R.POINTS[r.place]) or 0
            record.points[key] += pts
            table.insert(record.history[key], r.out and r.out or r.place)
            if not r.out and r.place < record.best[key] then
                record.best[key] = r.place
            end
        end
    end
    g.heatsDone = heat
    return true
end

-- すべての組が予選を終えたか
function R.allHeatsDone(record)
    if not record.groups then
        return false
    end
    for _, g in ipairs(record.groups) do
        if g.heatsDone < R.heatsPerGroup(record) then
            return false
        end
    end
    return true
end

-- 得点の順(同点はいちばん良い着、次に参加した順)に並べた参加者
function R.standings(record)
    local list = {}
    for i, e in ipairs(record.entrants) do
        local key = tostring(e.userId)
        table.insert(list, {
            userId = e.userId, name = e.name, order = i,
            points = record.points[key] or 0, best = record.best[key] or 9, history = record.history[key] or {},
        })
    end
    table.sort(list, function(a, b)
        if a.points ~= b.points then
            return a.points > b.points
        end
        if a.best ~= b.best then
            return a.best < b.best
        end
        return a.order < b.order
    end)
    return list
end

-- 優勝戦に出る人(得点の上位6人)
function R.finalists(record)
    local ids = {}
    for i, s in ipairs(R.standings(record)) do
        if i > 6 then
            break
        end
        table.insert(ids, s.userId)
    end
    return ids
end

-- 大会を終える。finalOrder = 優勝戦の人間の着順({userId, place, out})。優勝戦がない時は nil(得点の1位が優勝)
function R.finish(record, finalOrder, now)
    local champion
    if finalOrder then
        record.finalResults = finalOrder
        local bestPlace = math.huge
        for _, r in ipairs(finalOrder) do
            if not r.out and r.place < bestPlace then
                bestPlace, champion = r.place, r.userId
            end
        end
    end
    if not champion then
        local top = R.standings(record)[1]
        champion = top and top.userId
    end
    local _, entrant = R.findEntrant(record, champion or -1)
    record.champion = entrant and { userId = entrant.userId, name = entrant.name } or nil
    record.status, record.finishedAt = "done", now
    return record.champion
end

-- 画面に送る形(会場の鍵は外す。合言葉は主催者と参加者にだけ見せる)
function R.view(record, viewerId)
    local entrant = R.findEntrant(record, viewerId) ~= nil
    local finalists = {}
    for _, id in ipairs(record.finalists or {}) do
        finalists[tostring(id)] = true
    end
    local standings = {}
    if record.groups then
        for _, s in ipairs(R.standings(record)) do
            table.insert(standings, { name = s.name, points = s.points, history = s.history, me = s.userId == viewerId,
                final = finalists[tostring(s.userId)] == true })
        end
    end
    local groups = {}
    for k, g in ipairs(record.groups or {}) do
        groups[k] = { size = #g.members, heatsDone = g.heatsDone, live = g.privateId ~= nil and g.heatsDone < R.heatsPerGroup(record) }
    end
    return {
        id = record.id, name = record.name, hostName = record.hostName, host = record.host == viewerId,
        size = record.size, count = #record.entrants, format = R.FORMATS[record.format].name, formatId = record.format,
        start = record.start, startAt = record.startAt, private = record.private,
        code = (entrant or record.host == viewerId) and record.code or nil, status = record.status,
        entrant = entrant, standings = standings, groups = groups, champion = record.champion and record.champion.name or nil,
        finalLive = record.status == "final", heats = R.heatsPerGroup(record), needsFinal = R.needsFinal(record),
    }
end

return R
