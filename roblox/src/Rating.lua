-- participants contain server-determined rating and finish position.
local function ratingChanges(participants)
    local changes = {}
    local count = #participants
    if count < 2 then
        for i = 1, count do changes[i] = 0 end
        return changes
    end
    for i, racer in ipairs(participants) do
        local change = 0
        for j, opponent in ipairs(participants) do
            if i ~= j then
                local expected = 1 / (1 + 10 ^ ((opponent.rating-racer.rating)/400))
                local actual = racer.place == opponent.place and 0.5 or (racer.place < opponent.place and 1 or 0)
                change += (32/(count-1))*(actual-expected)
            end
        end
        changes[i] = change >= 0 and math.floor(change+0.5) or math.ceil(change-0.5)
    end
    return changes
end
return ratingChanges
