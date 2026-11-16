-- Client-only introduction. The caller owns the six display models.
local Run = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Sfx = require(script.Parent.Sfx)
local Wake = require(script.Parent.BoatWake)
local Opening = {}
local colors = {0xf2f2f0,0x16161a,0xd91e2e,0x1b50d4,0xf3d21b,0x18a24c}
local font = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
local function label(parent, class, words, width, height)
    local item = Instance.new(class)
    item.Text = words
    item.FontFace = font
    item.TextScaled = true
    item.TextColor3 = Color3.new(1,1,1)
    item.BackgroundColor3 = Color3.fromRGB(11,29,58)
    item.BackgroundTransparency = .12
    item.Size = UDim2.new(width,0,0,height)
    local limit = Instance.new("UITextSizeConstraint")
    limit.MinTextSize,limit.MaxTextSize = 8,20
    limit.Parent = item
    Instance.new("UICorner",item)
    item.Parent = parent
    return item
end

function Opening.play(options)
    local camera = options.camera
    local original,focus = camera.CFrame,camera.Focus
    local event = Instance.new("BindableEvent")
    local show = {Done=event.Event}
    local gui = Instance.new("ScreenGui")
    gui.Name = "MinatoOpening"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 15
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.Parent = options.gui
    local title = label(gui,"TextLabel",options.title or "みなとグランプリ",.65,36)
    title.Position = UDim2.fromOffset(8,6)
    local skip = label(gui,"TextButton","スキップ",.25,44)
    skip.AnchorPoint = Vector2.new(1,0)
    skip.Position = UDim2.new(1,-8,0,6)
    local entries = {}
    for i,row in ipairs(options.rows or {}) do
        if i>6 then break end
        local item = label(gui,"TextLabel",string.format("%d号艇　%s　%s",row.number,row.name,row.cls),.48,23)
        item.Position = UDim2.fromOffset(8,46+(i-1)*25)
        local band=Instance.new("Frame")
        band.Size=UDim2.new(0,5,1,0)
        band.BackgroundColor3=Color3.fromHex(string.format("%06x",colors[row.number] or colors[1]))
        band.BorderSizePixel=0
        band.Parent=item
        item.Visible=false
        entries[i]=item
    end
    local pit
    if options.venue then
        for _,part in options.venue:GetDescendants() do
            if part:IsA("BasePart") and part.Name:match("^Pit__Blue__") then pit=part.Position;break end
        end
    end
    local spray=Instance.new("Folder")
    spray.Name="MinatoOpeningSpray"
    spray.Parent=workspace
    local paths,leader={},nil
    for i=1,6 do
        local boat,goal=options.boats[i],options.finalCFrames[i]
        if boat and goal then
            local last=goal.Position
            local dir=goal.LookVector
            local start=pit and Vector3.new(pit.X+8,last.Y,pit.Z+(i-3.5)*25)
                or last-dir*210
            paths[i]={boat=boat,goal=goal,start=start,a=start+dir*80+goal.RightVector*28,b=last-dir*64}
            local anchor=Instance.new("Part")
            anchor.Anchored=true
            anchor.CanCollide,anchor.CanTouch,anchor.CanQuery=false,false,false
            anchor.Transparency=1
            anchor.Parent=spray
            paths[i].anchor=anchor
            paths[i].wake=Wake.new(anchor)
            paths[i].last=start
            leader=leader or i
            boat:PivotTo(CFrame.lookAt(start,paths[i].a))
        end
    end
    local links={}
    local timer
    local finished=false
    local function finish()
        if finished then return end
        finished=true
        if timer then task.cancel(timer);timer=nil end
        for _,link in links do link:Disconnect() end
        for _,p in paths do if p.boat.Parent then p.boat:PivotTo(p.goal) end end
        camera.CFrame,camera.Focus=original,focus
        camera.CameraType=Enum.CameraType.Custom
        Sfx.opening(false)
        spray:Destroy()
        gui:Destroy()
        event:Fire()
        task.delay(.2,function() event:Destroy() end)
    end
    show.skip,show.destroy=finish,finish
    table.insert(links,skip.Activated:Connect(finish))
    table.insert(links,Input.InputBegan:Connect(function(key)
        if key.UserInputType==Enum.UserInputType.Touch or key.UserInputType==Enum.UserInputType.MouseButton1
            or key.KeyCode==Enum.KeyCode.Return or key.KeyCode==Enum.KeyCode.KeypadEnter then finish() end
    end))
    camera.CameraType=Enum.CameraType.Scriptable
    local duration=math.max(.01,options.duration or 24)
    local started=os.clock()
    Sfx.opening(true)
    table.insert(links,Run.Heartbeat:Connect(function(dt)
        local t=(os.clock()-started)/duration
        if t>=1 then finish();return end
        for i,item in entries do item.Visible=t>=.012+(i-1)*.035 and t<.34 end
        title.Visible=t<.4
        for i,p in paths do
            local delay=.28+(i-1)*.034
            local u=math.clamp((t-delay)/(.97-delay),0,1)
            u=u*u*(3-2*u)
            local v=1-u
            local pos=p.start*v^3+p.a*(3*v*v*u)+p.b*(3*v*u*u)+p.goal.Position*u^3
            local heading=(p.a-p.start)*v*v+(p.b-p.a)*(2*v*u)+(p.goal.Position-p.b)*u*u
            local pose=u==1 and p.goal or CFrame.lookAt(pos,pos+heading)
            if p.boat.Parent then p.boat:PivotTo(pose) end
            p.anchor.CFrame=pose
            local speed=(pos-p.last).Magnitude/(3.5*math.max(dt,.001))
            Wake.update(p.wake,0,"",0,speed,.65,0,1,(camera.CFrame.Position-pos).Magnitude,i==leader,false,.35)
            p.last=pos
        end
        local target=leader and paths[leader].boat:GetPivot().Position or Vector3.zero
        local eye
        if t<.30 then
            target=target:Lerp(Vector3.zero,.6)
            eye=target+Vector3.new(-210+140*t,185,210)
        elseif t<.65 then eye=target+Vector3.new(-17,8,24)
        elseif t<.86 then eye=target+Vector3.new(4,12,44)
        else eye=target+Vector3.new(-42,55,45) end
        camera.CFrame=CFrame.lookAt(eye,target)
        camera.Focus=CFrame.new(target)
    end))
    timer=task.delay(duration,function() timer=nil;finish() end)
    return show
end
return Opening
