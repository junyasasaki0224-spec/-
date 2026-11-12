-- Short-lived room directory. Only servers can read the reserved-server credential.
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local map = MemoryStoreService:GetHashMap(RunService:IsStudio() and "MinatoRooms_studio_v1" or "MinatoRooms_v1")
local alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
local random = Random.new()
local lifetime = 2 * 60 * 60
local ticketLifetime = 120
local RoomService = {}

local function validCode(code)
    if type(code) ~= "string" or #code ~= 6 then return false end
    for i = 1, #code do
        if not string.find(alphabet, string.sub(code,i,i), 1, true) then return false end
    end
    return true
end

local function newCode()
    local code = ""
    for _ = 1, 6 do
        local n = random:NextInteger(1,#alphabet)
        code ..= string.sub(alphabet,n,n)
    end
    return code
end

function RoomService.create(owner, placeId)
    local ok, access, privateId = pcall(TeleportService.ReserveServerAsync, TeleportService, placeId)
    if not ok or type(access) ~= "string" or type(privateId) ~= "string" or privateId == "" then return nil end
    for _ = 1, 8 do
        local code = newCode()
        local nonce = HttpService:GenerateGUID(false)
        local record = {owner=owner.UserId, access=access, privateId=privateId, nonce=nonce,
            expires=os.time()+lifetime, tickets={}}
        local saved, result = pcall(function()
            return map:UpdateAsync(code, function(old)
                if old ~= nil then return nil end
                return record
            end, lifetime)
        end)
        if not saved then return nil end
        if result and result.nonce == nonce then return code end
    end
    return nil
end

-- A ticket is bound to one Roblox user and consumed in the destination server.
function RoomService.ticket(code, userId)
    if not validCode(code) then return nil end
    local stamp = HttpService:GenerateGUID(false)
    local now = os.time()
    local ok, result = pcall(function()
        return map:UpdateAsync(code,function(old)
            if type(old) ~= "table" or type(old.expires) ~= "number" or old.expires <= now
                or type(old.tickets) ~= "table" then return nil end
            local nextRecord = table.clone(old)
            local tickets = {}
            local count = 0
            for key, ticket in pairs(old.tickets) do
                if type(ticket) == "table" and type(ticket.expires) == "number" and ticket.expires > now then
                    tickets[key] = ticket
                    count += 1
                end
            end
            if count >= 50 and not tickets[tostring(userId)] then return nil end
            tickets[tostring(userId)] = {expires=now+ticketLifetime, stamp=stamp}
            nextRecord.tickets = tickets
            return nextRecord
        end,lifetime)
    end)
    if not ok or type(result) ~= "table" or not result.tickets then return nil end
    local ticket = result.tickets[tostring(userId)]
    if not ticket or ticket.stamp ~= stamp then return nil end
    return result.access
end

function RoomService.accept(code, userId, privateId)
    if not validCode(code) or privateId == "" then return nil end
    local now = os.time()
    local consumed = HttpService:GenerateGUID(false)
    local ok, result = pcall(function()
        return map:UpdateAsync(code,function(old)
            if type(old) ~= "table" or old.privateId ~= privateId or type(old.expires) ~= "number"
                or old.expires <= now or type(old.tickets) ~= "table" then return nil end
            local ticket = old.tickets[tostring(userId)]
            if type(ticket) ~= "table" or type(ticket.expires) ~= "number" or ticket.expires <= now then return nil end
            local nextRecord = table.clone(old)
            nextRecord.tickets = table.clone(old.tickets)
            nextRecord.tickets[tostring(userId)] = nil
            nextRecord.lastConsumed = consumed
            return nextRecord
        end,lifetime)
    end)
    if ok and type(result) == "table" and result.lastConsumed == consumed then return result.owner end
    return nil
end
-- Invite launch data is the same six-character secret as manual entry.
-- The destination server still verifies that it belongs to this room.
function RoomService.acceptInvite(code, privateId)
    if not validCode(code) or privateId == "" then return nil end
    local ok, record = pcall(map.GetAsync,map,code)
    if ok and type(record) == "table" and record.privateId == privateId
        and type(record.expires) == "number" and record.expires > os.time() then
        return record.owner
    end
    return nil
end
return RoomService
