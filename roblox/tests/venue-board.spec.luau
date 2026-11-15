local Board = require("../src/VenueBoard")
local pixels = require("../src/VenuePixels")
local f,s,visible = Board.angles(-3)
assert(f==270 and s==342 and visible)
f,s,visible=Board.angles(0)
assert(f==0 and s==0 and visible)
f,s,visible=Board.angles(15)
assert(f==90 and s==90 and not visible)
local rows={{lane=1,rank=3},{lane=2,rank=1,absent=true},{lane=3,rank=2},{lane=4,rank=2}}
assert(Board.order(rows,false)[1].lane==1)
local order=Board.order(rows,true)
assert(#order==3 and order[1].lane==3 and order[2].lane==4 and order[3].lane==1)
for _, name in {"Crowd","Windows","Lamps"} do
    for _,row in pixels[name] do
        assert(#row == #pixels[name][1])
        for i=1,#row do
            local pos=pixels.keys:find(row:sub(i,i),1,true)
            assert(pos and pos*8<=#pixels.palette)
        end
    end
end
