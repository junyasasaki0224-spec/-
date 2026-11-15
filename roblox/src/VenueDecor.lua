-- Client scenery in the same metre coordinates as src/gfx/venue.js.
local Art = require(script.Parent.VenueArt)
local Board = require(script.Parent.VenueBoard)
local roster = require(script.Parent.RaceRoster).roster
local v = Vector3.new
local rgb = Color3.fromRGB
local laneColors = {0xf2f2f0,0x272830,0xd91e2e,0x245fc2,0xf3d21b,0x18a24c}
local white, navy, gold = Color3.fromHex("f6f4eb"), Color3.fromHex("102840"), Color3.fromHex("ffcf5d")
local dark = Color3.fromHex("232d36")
local M = 3.5
local function paint(hex) return Color3.fromRGB(bit32.rshift(hex,16),bit32.extract(hex,8,8),bit32.extract(hex,0,8)) end

local function part(parent,name,pos,size,color)
    local p = Instance.new("Part")
    p.Name, p.Size, p.Position, p.Color = name, size*M, pos*M, color
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true,false,false,false
    p.Material = Enum.Material.SmoothPlastic
    p.Parent = parent
    return p
end

local function panel(parent,name,pos,normal,w,h,pixels,light)
    local p = part(parent,name,pos,v(w,h,.018),white)
    p.Transparency,p.CastShadow = 1,false
    p.CFrame = CFrame.lookAt(pos*M,pos*M+normal)
    local surface = Instance.new("SurfaceGui")
    surface.Name = name
    surface.Face = Enum.NormalId.Front
    surface.CanvasSize = pixels
    surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    surface.LightInfluence = light
    surface.MaxDistance = 2600
    surface.Parent = p
    return surface
end

local function block(parent,x,y,w,h,color)
    local f = Instance.new("Frame")
    f.BorderSizePixel = 0
    f.Position, f.Size = UDim2.fromScale(x,y), UDim2.fromScale(w,h)
    f.BackgroundColor3 = color
    f.Parent = parent
    return f
end
local function round(f)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(.5,0)
    corner.Parent = f
end
local function textLabel(parent,words,x,y,w,h,color)
    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Size,t.Position = UDim2.fromScale(w,h),UDim2.fromScale(x,y)
    t.Font,t.TextScaled,t.TextColor3 = Enum.Font.GothamBold,true,color
    t.Text = words
    t.Parent = parent
    return t
end

local function clock(parent)
    local dial = panel(parent,"StartClock",v(0,9,61.2),v(-.72,0,-.69),6.7,6.7,Vector2.new(320,320),.35)
    round(block(dial,0,0,1,1,dark))
    round(block(dial,.023,.023,.954,.954,white))
    for tick=0,59 do
        local big = tick%5==0
        local angle = tick*math.pi/30
        local sx,cy = math.sin(angle),math.cos(angle)
        local mark = block(dial,.5+sx*.431,.5-cy*.431,big and .017 or .006,big and .075 or .033,dark)
        mark.AnchorPoint,mark.Rotation = Vector2.new(.5,.5),tick*6
        if big then textLabel(dial,tostring(tick/5),.5+sx*.326-.055,.5-cy*.326-.046,.11,.092,dark) end
    end
    local function hand(length,width,color)
        local pivot = block(dial,.5,.5,1,1,white)
        pivot.AnchorPoint,pivot.BackgroundTransparency = Vector2.new(.5,.5),1
        block(pivot,.5-width/2,.5-length,width,length+.06,color)
        return pivot
    end
    local slow = hand(.31,.018,dark)
    local fast = hand(.415,.032,Color3.fromHex("e9a20d"))
    round(block(dial,.478,.478,.044,.044,dark))
    return fast,slow
end

local function scoreboard(parent, templates)
    local gui = panel(parent,"VideoBoard",v(38,14.6,-87.35),v(0,0,1),42,15.75,Vector2.new(768,288),.12)
    local screen = block(gui,0,0,1,1,navy)
    local title = textLabel(screen,"",.035,.034,.6,.17,white)
    title.TextXAlignment = Enum.TextXAlignment.Left
    textLabel(screen,"MINATO   /   LIVE",.66,.055,.30,.105,gold)
    block(screen,.035,.226,.93,.012,gold)
    local entries = {}
    for i=1,6 do
        local col,row=(i-1)%2,math.floor((i-1)/2)
        local base=block(screen,.035+col*.473,.26+row*.229,.455,.20,rgb(34,57,78))
        local chip=block(base,.033,.12,.15,.76,white)
        entries[i]={box=base,chip=chip,lane=textLabel(chip,"",0,0,1,1,navy),
            name=textLabel(base,"",.20,.12,.61,.76,white),rank=textLabel(base,"",.80,.22,.18,.53,gold)}
    end
    return function(time)
        local racing=templates~=nil and time>=0
        local header = if not templates then "本日の選手紹介" elseif racing then "レース順位" else "出走表"
        if title.Text~=header then title.Text=header end
        local rows={}
        for lane=1,6 do
            local b=templates and templates:FindFirstChild("Boat"..lane)
            rows[lane]={lane=lane,rank=b and b:GetAttribute("Rank") or lane,
                name=if templates then (b and b:GetAttribute("Racer") or "―") else roster[lane].name,
                finished=b and b:GetAttribute("Finished"),
                absent=b and b:GetAttribute("Absent")}
        end
        local order=Board.order(rows,racing)
        for i,entry in entries do
            local row=order[i]
            entry.box.Visible=row~=nil
            if row then
                local rank=racing and (row.rank..(row.finished and "着" or "位")) or ""
                if entry.name.Text~=row.name or entry.lane.Text~=tostring(row.lane) or entry.rank.Text~=rank then
                    entry.name.Text,entry.rank.Text,entry.lane.Text=row.name,rank,tostring(row.lane)
                    entry.chip.BackgroundColor3=paint(laneColors[row.lane])
                    entry.lane.TextColor3=(row.lane==1 or row.lane==5) and navy or white
                end
            end
        end
    end
end

local ads={{"海鮮 みなと丸",0x154677},{"湾岸モータース",0xa73140},{"港町食堂",0x287263},
    {"みなと観光ホテル",0x594366},{"しおかぜマリン",0x203e60},{"潮路工房",0x946736}}
local function signage(parent)
    local function sign(pos,dir,w,h,caption,color)
        local gui=panel(parent,"Sign",pos,dir,w,h,Vector2.new(640,112),.72)
        local base=block(gui,0,0,1,1,color)
        block(base,.016,.13,.016,.74,gold)
        textLabel(base,caption,.055,.12,.90,.76,white)
    end
    sign(v(20,35.44,79.68),v(0,0,-1),96,9,"MINATO   /   みなと競艇場",rgb(22,57,101))
    for i=0,38 do
        local ad=ads[i%#ads+1]
        sign(v(-254+13*i,2.9,-79.53),v(0,0,1),12,2.25,ad[1],paint(ad[2]))
    end
    for i=0,9 do
        local ad=ads[(39+i)%#ads+1]
        sign(v(253.63,2.9,-68+13*i),v(-1,0,0),12,2.25,ad[1],paint(ad[2]))
    end
    for d=50,200,50 do
        sign(v(-d,4.2,59.2),v(-.59,0,-.81),3.2,1.6,tostring(d),d==100 and rgb(161,43,48) or navy)
    end
end

local function spectators(parent)
    for section=0,9 do
        for band=0,3 do
            local row=band*3+(section%2)
            local pos=v(-133+section*34,1.6+.62*(row+1)+.84,72.85+row*1.5)
            local gui=panel(parent,"Spectators",pos,v(0,0,-1),34,1.4,Vector2.new(520,22),.85)
            gui.MaxDistance=1600
            local img=Art.put(gui,"Crowd")
            if img then
                img.ImageRectOffset=Vector2.new(0,22*((section+band)%3))
                img.ImageRectSize=Vector2.new(520,22)
            else
                -- Small, cached silhouettes when runtime images are unavailable.
                for j=1,12 do
                    local x=(j-.55)/13
                    block(gui,x,.4,.014,.43,paint(laneColors[(j+band+section)%6+1]))
                    block(gui,x+.002,.14,.009,.28,rgb(197,158,126))
                end
            end
        end
    end
end

local function finishBuildings(parent)
    for floor=0,2 do
        local gui=panel(parent,"FacadeGlazing",v(20,12.545+floor*5.8,84.56),v(0,0,-1),340,5.25,Vector2.new(2560,48),.85)
        local img=Art.put(gui,"Windows")
        if img then
            img.ScaleType=Enum.ScaleType.Tile
            img.TileSize=UDim2.fromOffset(64,48)
        else
            local shade=block(gui,0,0,1,.14,dark)
            shade.BackgroundTransparency=.55
        end
    end
    local function lamp(x,z,angle)
        local normal=v(math.sin(angle)*math.cos(.35),-math.sin(.35),math.cos(angle)*math.cos(.35))
        local gui=panel(parent,"FloodlightLenses",v(x,39.6,z)+normal*.36,normal,10.2,5.6,Vector2.new(144,72),.18)
        if not Art.put(gui,"Lamps") then
            for i=0,5 do
                local bezel=block(gui,.025+i/6,.09,.12,.82,dark)
                round(block(bezel,.07,.19,.86,.62,white))
            end
        end
    end
    for _,x in {-215,-75,95,215} do lamp(x,-92,0) end
    lamp(270,-40,-math.pi/2); lamp(270,25,-math.pi/2); lamp(-300,-55,math.pi/2)
end

local function vegetation(parent)
    local rng=Random.new(5417)
    local function tree(x,z)
        local scale=rng:NextNumber(.83,1.21)
        local trunk=part(parent,"Trunk",v(x,1.6+2.15*scale,z),v(.48,4.3,.48)*scale,rgb(102,87,69))
        trunk.Material=Enum.Material.Wood
        for i,offset in {v(-.7,3.8,.25),v(.85,4.4,-.2),v(0,5.8,0)} do
            local green=rng:NextInteger(80,109)
            local p=part(parent,"Canopy",v(x,1.6,z)+offset*scale,v(3.15,3.35,2.9)*scale,rgb(48+i*3,green,70))
            p.Material=Enum.Material.Grass
            p.Shape=Enum.PartType.Ball
            p.Orientation=v(8*i,rng:NextInteger(0,180),9*i)
        end
    end
    for x=-286,286,18 do if x<12 or x>64 then tree(x,-96-rng:NextNumber(0,3)) end end
    for z=-85,52,19 do tree(274,z) end
    for x=-140,180,32 do if math.abs(x-20)>=40 then tree(x,134) end end
end

local function flags(parent)
    local flutter={}
    for x=-238,238,24 do
        if math.abs(x)>14 then
            part(parent,"Flagstaff",v(x,3.6,66.5),v(.07,4,.07),rgb(164,171,165))
            local banner=part(parent,"Banner",v(x+.46,4.2,66.5),v(.86,2.6,.035),paint(laneColors[(#flutter)%6+1]))
            table.insert(flutter,{part=banner,base=CFrame.new(v(x,4.2,66.5)*M),offset=.46*M,phase=x*.41})
        end
    end
    for i=0,26 do
        local z=7+i*2
        local p=part(parent,"Pennant",v(0,12.23,z),v(.035,.7,.5),paint(laneColors[i%6+1]))
        p.Orientation=v((i%4-1)*9,0,7)
    end
    return flutter
end

return function(parent,templates)
    local folder=Instance.new("Folder")
    folder.Name="VenueDetails"
    spectators(folder)
    vegetation(folder)
    local flutter=flags(folder)
    signage(folder)
    finishBuildings(folder)
    local fast,slow=clock(folder)
    local draw=scoreboard(folder,templates)
    folder.Parent=parent
    local nextDial,nextBoard=0,0
    return function(time,now,wind)
        if now>=nextDial then
            nextDial=now+.1
            fast.Rotation,slow.Rotation,fast.Visible=Board.angles(time)
            for _,flag in flutter do
                local angle=math.sin(now*(2.3+wind*.14)+flag.phase)*(.13+.022*wind)
                flag.part.CFrame=flag.base*CFrame.Angles(0,angle,0)*CFrame.new(flag.offset,0,0)
            end
        end
        if now>=nextBoard then
            nextBoard=now+.5
            draw(time)
        end
    end
end
