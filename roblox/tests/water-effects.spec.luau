local rules = require("../src/WaterRules")
local small,slow = rules.wave(0)
local large,fast = rules.wave(8)
assert(large > small and fast > slow and large <= 1)
assert(rules.wave(-1) == small and rules.wave(9) == large)
for _, speed in {0,1,3,15,24,80} do
    for _, throttle in {0,.5,1} do
        local jet, fan, mist, side = rules.rates(speed, throttle, 1, 0, false)
        assert(jet >= 0 and fan >= 0 and mist >= 0 and side >= 0 and jet + fan + mist + side <= 270)
        if speed < 1.2 then assert(jet + fan + mist + side == 0) end
        local _, own = rules.rates(speed, throttle, 1, 0, true)
        local _, distant = rules.rates(speed, throttle, 1, 700, false)
        local _, straight = rules.rates(speed, throttle, 0, 0, false)
        assert(own <= fan and distant <= fan and straight == 0)
    end
end
