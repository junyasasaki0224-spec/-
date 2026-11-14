-- Local viewing controls; selecting a boat or leaving this view sends no remote event.
local Input = game:GetService("UserInputService")
local names = {"追尾","接近","オンボード","上空","自由"}
local navy = Color3.fromRGB(11,29,58)
local gold = Color3.fromRGB(255,210,60)
local white = Color3.new(1,1,1)
local dark = Color3.fromRGB(17,17,17)
local colors = {Color3.fromRGB(242,242,240),Color3.fromRGB(22,22,26),Color3.fromRGB(217,30,46),
    Color3.fromRGB(27,80,212),Color3.fromRGB(243,210,27),Color3.fromRGB(24,162,76)}

local function rounded(item, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0,radius)
    corner.Parent = item
end

return function(gui)
    local view = {lane=1, mode=1, exited=false}
    local states = {}
    local bar = Instance.new("Frame")
    bar.Name = "SpectatorBar"
    bar.AnchorPoint = Vector2.new(0.5,1)
    bar.Position = UDim2.new(0.5,0,1,-4)
    bar.BackgroundColor3,bar.BackgroundTransparency = navy,0.16
    bar.Visible = false
    rounded(bar,12)
    bar.Parent = gui

    local function control(class,name,text,bg,fg)
        local item = Instance.new(class)
        item.Name,item.Text,item.Font,item.TextSize = name,text,Enum.Font.GothamBold,15
        item.BackgroundColor3,item.TextColor3 = bg,fg
        item.BorderSizePixel = 0
        item.Parent = bar
        rounded(item,8)
        return item
    end
    local title = control("TextLabel","Watching","観戦中",navy,Color3.fromRGB(255,90,77))
    title.BackgroundTransparency = 1
    local camera = control("TextButton","Camera",names[1],navy,white)
    local leave = control("TextButton","Exit","退出",white,dark)
    local buttons, strokes = {}, {}
    local function outline(item,color,alpha)
        local stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Color,stroke.Transparency = color,alpha
        stroke.Parent = item
        return stroke
    end
    outline(bar,white,.68)
    outline(camera,white,.55)
    local function eligible(i)
        return states[i] and states[i][17]=="" and not states[i][19]
    end
    for i=1,6 do
        local btn = control("TextButton","Boat"..i,tostring(i),colors[i],(i==1 or i==5) and dark or white)
        buttons[i],strokes[i] = btn,outline(btn,gold,0)
        strokes[i].Thickness = 3
        btn.Activated:Connect(function() if eligible(i) then view.lane=i end end)
    end
    local function position(item,x,y,w)
        item.Position,item.Size = UDim2.fromOffset(x,y),UDim2.fromOffset(w,44)
    end
    local function layout()
        local w=math.min(gui.AbsoluteSize.X-8,574)
        local compact=w<550 or gui.AbsoluteSize.X<gui.AbsoluteSize.Y
        bar.Size=UDim2.fromOffset(w,compact and 104 or 54)
        position(title,5,5,64)
        position(leave,w-61,5,56)
        position(camera,w-173,5,106)
        local start=compact and 5 or 74
        local space=(compact and w-10 or w-253)/6
        for i,btn in ipairs(buttons) do
            position(btn,start+(i-1)*space,compact and 55 or 5,math.max(44,space-4))
        end
    end
    gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
    layout()

    local yaw,pitch,radius=0,.36,38
    local mouse=false
    local fingers={}
    local function clearGesture()
        mouse=false
        table.clear(fingers)
    end
    local function orbit(dx,dy)
        yaw-=dx*.008
        pitch=math.clamp(pitch+dy*.006,.08,1.42)
    end
    Input.InputBegan:Connect(function(obj,used)
        if used or not bar.Visible or view.mode~=5 then return end
        if obj.UserInputType==Enum.UserInputType.MouseButton1 then mouse=true
        elseif obj.UserInputType==Enum.UserInputType.Touch then fingers[obj]=Vector2.new(obj.Position.X,obj.Position.Y) end
    end)
    Input.InputChanged:Connect(function(obj)
        if not bar.Visible or view.mode~=5 then return end
        if obj.UserInputType==Enum.UserInputType.MouseMovement and mouse then orbit(obj.Delta.X,obj.Delta.Y)
        elseif obj.UserInputType==Enum.UserInputType.MouseWheel then radius=math.clamp(radius-obj.Position.Z*3,6,180)
        elseif fingers[obj] then
            local old=fingers[obj]
            local pos=Vector2.new(obj.Position.X,obj.Position.Y)
            local other
            for finger,point in pairs(fingers) do if finger~=obj then other=point; break end end
            if other then
                local a,b=(old-other).Magnitude,(pos-other).Magnitude
                if a>2 and b>2 then radius=math.clamp(radius*a/b,6,180) end
            else orbit(pos.X-old.X,pos.Y-old.Y) end
            fingers[obj]=pos
        end
    end)
    Input.InputEnded:Connect(function(obj)
        fingers[obj]=nil
        if obj.UserInputType==Enum.UserInputType.MouseButton1 then mouse=false end
    end)
    Input.WindowFocusReleased:Connect(clearGesture)
    camera.Activated:Connect(function() view.mode=view.mode%#names+1; clearGesture() end)
    leave.Activated:Connect(function() view.exited=true; bar.Visible=false; clearGesture() end)

    function view.reset()
        view.mode,view.lane,view.exited=1,1,false
        clearGesture()
    end
    function view.update(show,latest)
        states=latest
        bar.Visible=show and not view.exited
        if not bar.Visible then clearGesture(); return end
        if not eligible(view.lane) then
            for i=1,6 do if eligible(i) then view.lane=i; break end end
        end
        for i,btn in ipairs(buttons) do
            local enabled=eligible(i)
            btn.BackgroundTransparency=enabled and 0 or .7
            btn.TextTransparency=enabled and 0 or .5
            strokes[i].Enabled=enabled and i==view.lane or false
        end
        camera.Text="視点　"..names[view.mode]
    end
    function view.camera(cf)
        local forward=Vector3.new(cf.LookVector.X,0,cf.LookVector.Z).Unit
        local up=Vector3.new(0,1,0)
        local center=cf.Position+up*1.5
        local eye,aim
        if view.mode==2 then eye,aim=center-forward*15+up*5,center+forward*6
        elseif view.mode==3 then eye,aim=center+forward*2.5+up*1.8,center+forward*45+up*1.6
        elseif view.mode==4 then eye,aim=center-forward*5+up*90,center
        elseif view.mode==5 then
            eye=center+Vector3.new(math.cos(yaw)*math.cos(pitch),math.sin(pitch),math.sin(yaw)*math.cos(pitch))*radius
            aim=center
        else eye,aim=center-forward*42+up*17,center+forward*12 end
        return CFrame.lookAt(eye,aim),CFrame.new(aim)
    end
    return view
end
