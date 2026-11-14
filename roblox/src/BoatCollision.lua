-- Three overlapping circles approximate each hull in the horizontal plane.
local offsets = {-1.05, 0, 1.05}
local radius = 0.68
local diameter = radius * 2
local inertia = 1.25
local restitution = 0.25

local function collide(a, b)
    if a.out or b.out then return end
    local dx, dz = b.x - a.x, b.z - a.z
    if dx * dx + dz * dz > 18 then return end

    local ax, az = math.cos(a.h), math.sin(a.h)
    local bx, bz = math.cos(b.h), math.sin(b.h)
    local depth, nx, nz, contactX, contactZ = 0, 0, 0, 0, 0
    for _, aOffset in ipairs(offsets) do
        local aX, aZ = a.x + ax * aOffset, a.z + az * aOffset
        for _, bOffset in ipairs(offsets) do
            local bX, bZ = b.x + bx * bOffset, b.z + bz * bOffset
            local x, z = bX - aX, bZ - aZ
            local distanceSquared = x * x + z * z
            if distanceSquared < diameter * diameter then
                local distance = math.sqrt(distanceSquared)
                local penetration = diameter - distance
                if penetration > depth then
                    depth = penetration
                    if distance > 0.00001 then
                        nx, nz = x / distance, z / distance
                    else
                        -- A fixed perpendicular prevents division by zero on exact overlap.
                        nx, nz = -az, ax
                    end
                    contactX, contactZ = (aX + bX) * 0.5, (aZ + bZ) * 0.5
                end
            end
        end
    end
    if depth == 0 then return end

    local correction = depth * 0.5
    a.x, a.z = a.x - nx * correction, a.z - nz * correction
    b.x, b.z = b.x + nx * correction, b.z + nz * correction
    local rax, raz = contactX - a.x, contactZ - a.z
    local rbx, rbz = contactX - b.x, contactZ - b.z
    local relativeX = (b.vx - b.w * rbz) - (a.vx - a.w * raz)
    local relativeZ = (b.vz + b.w * rbx) - (a.vz + a.w * rax)
    local closingSpeed = relativeX * nx + relativeZ * nz
    if closingSpeed >= 0 then return end

    local armA, armB = rax * nz - raz * nx, rbx * nz - rbz * nx
    local impulse = -(1 + restitution) * closingSpeed / (2 + (armA * armA + armB * armB) / inertia)
    a.vx, a.vz = a.vx - impulse * nx, a.vz - impulse * nz
    b.vx, b.vz = b.vx + impulse * nx, b.vz + impulse * nz
    a.w, b.w = a.w - armA * impulse / inertia, b.w + armB * impulse / inertia
    local tx, tz = -nz, nx
    local tangentSpeed = relativeX * tx + relativeZ * tz
    local friction = math.max(-0.35 * impulse, math.min(0.35 * impulse, -tangentSpeed * 0.25))
    a.vx, a.vz = a.vx - friction * tx, a.vz - friction * tz
    b.vx, b.vz = b.vx + friction * tx, b.vz + friction * tz
    return impulse
end

local obstacles = {
    {x = 150, z = 8, radius = 0.8, softness = 0.55},
    {x = -150, z = 0, radius = 0.8, softness = 0.55},
    {x = 0, z = 4, radius = 0.6, softness = 1},
}

local units = {}
local length = math.sqrt(300^2 + 8^2)
for side, mark in ipairs({obstacles[1], obstacles[2]}) do
    local sign = side == 1 and -1 or 1
    local dx, dz = sign*300/length, sign*8/length
    local unit = {x=mark.x+11*dx, z=mark.z+11*dz, dx=dx, dz=dz, length=18, width=0.9}
    table.insert(units, unit)
    for i = 0, 23 do
        local t = -8.55 + 17.1*i/23
        table.insert(obstacles, {x=unit.x+t*dx,z=unit.z+t*dz,radius=0.45,softness=1,unit=true})
    end
end

local function disqualify(boat, reason, clock)
    if boat.finished or boat.out then return end
    boat.out, boat.outAt = reason, clock
    boat.flying, boat.sunk = reason == "F", reason == "沈"
    boat.vx, boat.vz, boat.w, boat.speed = 0, 0, 0, 0
    boat.throttle, boat.steer = 0, 0
end

local function collideObstacles(boat, clock)
    if boat.out then return end
    local power, threshold = 0, 2
    local ch, sh = math.cos(boat.h), math.sin(boat.h)
    for _, obstacle in ipairs(obstacles) do
        if (boat.x-obstacle.x)^2+(boat.z-obstacle.z)^2 > 9 then continue end
        for _, offset in ipairs(offsets) do
            local dx = boat.x + ch * offset - obstacle.x
            local dz = boat.z + sh * offset - obstacle.z
            local distance = math.sqrt(dx * dx + dz * dz)
            local combinedRadius = radius + obstacle.radius
            if distance < combinedRadius then
                local nx, nz = -sh, ch
                if distance > 0.00001 then nx, nz = dx / distance, dz / distance end
                local penetration = (combinedRadius - distance) * obstacle.softness
                boat.x, boat.z = boat.x + nx * penetration, boat.z + nz * penetration
                local normalSpeed = boat.vx * nx + boat.vz * nz
                if normalSpeed < 0 then
                    if -normalSpeed > power then
                        power, threshold = -normalSpeed, obstacle.unit and 3.5 or 2
                    end
                    local rebound = obstacle.softness == 1 and 1.2 or 0.6
                    boat.vx = (boat.vx - rebound * normalSpeed * nx) * 0.985
                    boat.vz = (boat.vz - rebound * normalSpeed * nz) * 0.985
                    boat.w = boat.w + offset * (ch * nz - sh * nx) * (-normalSpeed) * 0.25
                end
            end
        end
    end
    if boat.started and power >= threshold then disqualify(boat,"沈",clock) end
end

local function walls(b, clock)
    if b.out then return end
    local impact = 0
    if b.x < -261 or b.x > 251 then
        if (b.x < -261 and b.vx < 0) or (b.x > 251 and b.vx > 0) then
            impact = math.abs(b.vx)
            b.vx, b.vz = -0.3*b.vx, 0.8*b.vz
        end
        b.x = math.clamp(b.x,-261,251)
    end
    if b.z < -77 or b.z > 57 then
        if (b.z < -77 and b.vz < 0) or (b.z > 57 and b.vz > 0) then
            impact = math.max(impact,math.abs(b.vz))
            b.vz, b.vx = -0.3*b.vz, 0.8*b.vx
        end
        b.z = math.clamp(b.z,-77,57)
    end
    if b.started and impact >= 7 then disqualify(b,"沈",clock) end
end

return {boats=collide, obstacles=collideObstacles, walls=walls, units=units, disqualify=disqualify}
