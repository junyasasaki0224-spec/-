-- ロビー: 今日のイベント内のランキングを見せる(読むだけ。得点を足すのはレース会場のサーバー)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Meta = require(ReplicatedStorage:WaitForChild("Meta"))
local Board = require(script.Parent:WaitForChild("EventBoard"))
local remote = Instance.new("RemoteFunction")
remote.Name = "MinatoEventBoard"
remote.Parent = ReplicatedStorage
local last = {}

remote.OnServerInvoke = function(player)
    local now = os.clock()
    if last[player] and now - last[player] < 0.5 then
        return { busy = true }
    end
    last[player] = now
    local day = Meta.today()
    local rows = Board.top(day)
    if not rows then
        return { failed = true }
    end
    -- 画面には上位20人と自分の行だけを送る
    local list, mine = {}, nil
    for i, row in ipairs(rows) do
        local me = row.userId == player.UserId
        if i <= 20 then
            table.insert(list, { rank = row.rank, name = row.name, points = row.points, races = row.races, me = me })
        end
        if me then
            mine = { rank = row.rank, points = row.points, races = row.races }
        end
    end
    return { day = day, rows = list, mine = mine, count = #rows }
end

Players.PlayerRemoving:Connect(function(player)
    last[player] = nil
end)
