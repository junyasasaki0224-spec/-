local changes = require("../src/Rating")

local one = changes({{rating=1500,place=1}})
assert(one[1] == 0, "a single human must not change rating")

local equal = changes({{rating=1500,place=1},{rating=1500,place=2}})
assert(equal[1] == 16 and equal[2] == -16, "equal-rating two-player race")

local upset = changes({{rating=1400,place=1},{rating=1600,place=2}})
assert(upset[1] == 24 and upset[2] == -24, "upset against a higher rating")

local tie = changes({{rating=1500,place=7},{rating=1500,place=7}})
assert(tie[1] == 0 and tie[2] == 0, "equal disqualifications must tie")

local three = changes({{rating=1500,place=1},{rating=1500,place=2},{rating=1500,place=3}})
assert(three[1] == 16 and three[2] == 0 and three[3] == -16, "pairwise averaging for three humans")
print("rating checks passed")
