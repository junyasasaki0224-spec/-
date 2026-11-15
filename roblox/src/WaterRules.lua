-- Rendering only. Speed is m/s; Wave is the race's wave height in cm.
local Rules = {}

function Rules.wave(cm)
    local rough = math.clamp(cm or 0, 0, 8) / 8
    return 0.07 + 0.31 * rough, 7 + 17 * rough
end

function Rules.rates(speed, throttle, slip, distance, following)
    local speedRatio = math.clamp((speed - 1.2) / 21.4, 0, 1)
    local density = math.clamp(1 - distance / 550, 0.18, 1)
    local jet = speedRatio * (0.4 + 0.6 * throttle)
    local sheet = speedRatio * math.clamp(slip, 0, 1) * (0.4 + 0.6 * throttle)
    return 28 * jet * density, 34 * sheet * density * (following and 0.48 or 1),
        5 * math.max(jet, sheet) * density
end

return Rules
