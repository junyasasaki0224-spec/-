-- Three overlapping circles approximate each hull in the horizontal plane.
local offsets = {-1.95, 0, 1.95}
local radius = 1.55
local diameter = radius * 2
local inertia = 4.0
local restitution = 0.2

local function collide(a, b)
    local dx, dz = b.x - a.x, b.z - a.z
    if dx * dx + dz * dz > 49 then return end

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
end

local obstacles = {
    {x = 150, z = 8, radius = 1.5, softness = 0.55},
    {x = -150, z = 0, radius = 1.5, softness = 0.55},
    {x = 0, z = 4, radius = 0.6, softness = 1},
}

local function collideObstacles(boat)
    local ch, sh = math.cos(boat.h), math.sin(boat.h)
    for _, obstacle in ipairs(obstacles) do
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
                    local rebound = obstacle.softness == 1 and 1.2 or 0.6
                    boat.vx = (boat.vx - rebound * normalSpeed * nx) * 0.985
                    boat.vz = (boat.vz - rebound * normalSpeed * nz) * 0.985
                    boat.w = boat.w + offset * (ch * nz - sh * nx) * (-normalSpeed) * 0.25
                end
            end
        end
    end
end

return {boats = collide, obstacles = collideObstacles}
