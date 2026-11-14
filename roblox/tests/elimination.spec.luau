local collision=require("../src/BoatCollision")
local rules=require("../src/ResultRules")
local rate=require("../src/Rating")

local function boat(x,z,vx,vz)
    return {x=x,z=z,vx=vx,vz=vz,h=0,w=0,started=true,finished=false}
end
-- A glancing blow has very high tangential speed, but insufficient closing speed.
for _,case in ipairs({{150,8,1.99,false},{150,8,2,true},{0,4,2,true}}) do
    local b=boat(case[1],case[2]+1.2,18,-case[3])
    collision.obstacles(b,2)
    assert((b.sunk==true)==case[4])
end
for _,u in ipairs(collision.units) do
    for _,speed in ipairs({3.49,3.6}) do
        local b=boat(u.x-u.dz*1.04,u.z+u.dx*1.04,u.dz*speed,-u.dx*speed)
        b.h=math.atan2(u.dz,u.dx)
        collision.obstacles(b,7)
        assert((b.sunk==true)==(speed>3.5))
    end
end
for _,speed in ipairs({6.99,7}) do
    local b=boat(251.1,20,speed,1)
    collision.walls(b,2)
    assert((b.sunk==true)==(speed==7))
end
for _,phase in ipairs({"before","after"}) do
    local b=boat(150,9.2,0,-18)
    b.started=phase~="before"
    b.finished=phase=="after"
    collision.obstacles(b,10)
    assert(not b.out)
end

for _,reason in ipairs({"F","沈","退出"}) do
    local lost=boat(0,5,0,-10)
    collision.disqualify(lost,reason,2)
    local live=boat(0,5.1,0,-7)
    assert(not collision.boats(live,lost) and live.z==5.1 and live.vz==-7)
    assert(not collision.boats(lost,live))
    collision.disqualify(lost,"退出",4)
    assert(lost.out==reason and lost.outAt==2)
    local row=rules.entry(lost,1)
    assert(row.place==6 and not row.won and not row.time)
    local change=rate({{rating=1500,place=row.place},{rating=1500,place=1}})
    assert(change[1]==-16)
end
-- Contact imparts velocity; only the hull hitting the obstacle can be disqualified.
local pushed,pusher=boat(150,9.24,0,0),boat(150,10.48,0,-15)
assert(collision.boats(pusher,pushed)>0)
collision.obstacles(pushed,5)
assert(pushed.sunk and not pusher.out)
local human={humanUserId=1,out="F"}
local field={human,{}}
local ending,since=rules.shouldEnd(field,-2,nil)
assert(not ending and since==-2)
assert(not rules.shouldEnd(field,7.99,since))
assert(rules.shouldEnd(field,8,since))
assert(not rules.shouldEnd({{},{}},40,nil))
assert(not rules.shouldEnd({human,{humanUserId=2}},40,nil))
assert(rules.shouldEnd({human,{finished=true}},0,nil))
print("elimination, collision, rating and round end passed")
