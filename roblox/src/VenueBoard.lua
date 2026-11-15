local Board = {}

function Board.angles(time)
    return (time % 12)*30, (time % 60)*6, time < 1.5
end

function Board.order(rows, racing)
    local order = {}
    for _, row in ipairs(rows) do
        if not row.absent then table.insert(order,row) end
    end
    table.sort(order,function(a,b)
        if racing and a.rank ~= b.rank then return a.rank < b.rank end
        return a.lane < b.lane
    end)
    return order
end

return Board
