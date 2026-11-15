-- A private exercise inside the lobby. Race records and rewards are never submitted.
local Step=require(script.Parent.RaceStep)
local Run=game:GetService("RunService")
local Input=game:GetService("UserInputService")
local Ui=require(script.Parent.HomeUi)
local Practice={}
local function launchWindow(lane)
    local probe=Step.soloBoat(lane-1,2)
    for tick=1,20*120 do
        Step.advance(probe,1,0,tick*Step.DT,Step.DT)
        if probe.started then return .12-probe.startTime end
    end
    return -8
end

function Practice.start(gui,model,lane,height,onClose)
    local origin=model:GetPivot()
    local layer=Instance.new("Frame")
    layer.Name="Practice";layer.Size=UDim2.fromScale(1,1);layer.BackgroundTransparency=1;layer.Parent=gui
    local line=Instance.new("Part")
    line.Name="PracticeStartLine";line.Anchored=true;line.CanCollide=false;line.CanQuery=false
    line.Size=Vector3.new(.6,.12,165);line.Position=Vector3.new(0,.08,86)
    line.Material=Enum.Material.Neon;line.Color=Color3.fromRGB(255,216,73);line.Parent=workspace
    local clock=Ui.text(layer,"Clock","",24,Ui.HEAVY,Color3.new(1,1,1))
    clock.BackgroundColor3=Color3.fromRGB(11,29,58);clock.BackgroundTransparency=.1
    clock.TextXAlignment=Enum.TextXAlignment.Center;Ui.corner(clock,12)
    local face=Instance.new("Frame")
    face.Name="Dial";face.BackgroundColor3=Color3.fromRGB(16,37,65);face.BorderSizePixel=0;face.Parent=layer
    Ui.corner(face,40);Ui.stroke(face,Ui.GOLD,1)
    for i=0,11 do
        local mark=Instance.new("Frame");local angle=math.rad(i*30)
        mark.AnchorPoint=Vector2.new(.5,.5);mark.Position=UDim2.fromScale(.5+.39*math.sin(angle),.5-.39*math.cos(angle))
        mark.Size=UDim2.fromOffset(i==0 and 4 or 2,5);mark.Rotation=i*30;mark.BorderSizePixel=0
        mark.BackgroundColor3=i==0 and Ui.GOLD or Ui.WHITE;mark.Parent=face
    end
    local rotor=Instance.new("Frame");rotor.Size=UDim2.fromScale(1,1);rotor.BackgroundTransparency=1;rotor.Parent=face
    local hand=Instance.new("Frame");hand.AnchorPoint=Vector2.new(.5,1);hand.Position=UDim2.fromScale(.5,.5)
    hand.Size=UDim2.fromScale(.045,.36);hand.BackgroundColor3=Ui.GOLD;hand.BorderSizePixel=0;hand.Parent=rotor
    local hint=Ui.text(layer,"LaunchHint","",15,Ui.BOLD,Ui.WHITE)
    hint.BackgroundColor3=clock.BackgroundColor3;hint.BackgroundTransparency=.18;hint.TextXAlignment=Enum.TextXAlignment.Center
    Ui.corner(hint,10)
    local launch=launchWindow(lane)
    local result=Ui.text(layer,"Result","",22,Ui.HEAVY,Ui.GOLD)
    result.BackgroundColor3=clock.BackgroundColor3;result.BackgroundTransparency=.08
    result.TextXAlignment=Enum.TextXAlignment.Center;Ui.corner(result,12)
    local b,elapsed,hold,accumulator,throttle,steer,finish
    local touches={}
    local function reset()
        b=Step.soloBoat(lane-1,2)
        elapsed,hold,accumulator,throttle,steer,finish=-14,2.5,0,0,0,nil
        table.clear(touches);result.Visible=false
    end
    local links={}
    local function connect(signal,callback) table.insert(links,signal:Connect(callback)) end
    local function close()
        for _,c in links do c:Disconnect() end
        line:Destroy();layer:Destroy();model:PivotTo(origin);onClose()
    end
    Ui.headButton(layer,"Back","‹ 戻る",8,8,86,close)
    Ui.headButton(layer,"Retry","もう一度",8,66,105,reset)
    local function control(name)
        local c=Instance.new("TextButton");c.Name=name;c.BackgroundColor3=clock.BackgroundColor3
        c.BackgroundTransparency=.18;c.TextColor3=Color3.new(1,1,1);c.TextSize=16;c.FontFace=Ui.HEAVY
        c.Parent=layer;Ui.corner(c,12);Ui.stroke(c,Ui.GOLD,1,.3)
        return c
    end
    local wheel,gas=control("Steer"),control("Throttle")
    wheel.Text="左　│　右"
    local function layout()
        local w,h=layer.AbsoluteSize.X,layer.AbsoluteSize.Y
        local rise=math.clamp(height or 40,0,math.max(0,h-270))
        Ui.place(face,w-208,10,46,46);Ui.place(clock,w-156,8,148,48);Ui.place(hint,w-208,62,200,34);Ui.place(result,12,math.floor(h*.42),w-24,58)
        Ui.place(wheel,12,h-64-rise,128,52);Ui.place(gas,w-84,h-142-rise,72,130)
    end
    local function drag(c,pos)
        if c==gas then throttle=math.clamp(1-(pos.Y-c.AbsolutePosition.Y)/c.AbsoluteSize.Y,0,1)
        else steer=math.clamp(1-2*(pos.X-c.AbsolutePosition.X)/c.AbsoluteSize.X,-1,1) end
    end
    for _,c in {wheel,gas} do
        connect(c.InputBegan,function(obj)
            if obj.UserInputType==Enum.UserInputType.Touch or obj.UserInputType==Enum.UserInputType.MouseButton1 then
                touches[obj]=c;drag(c,obj.Position)
            end
        end)
    end
    connect(Input.InputChanged,function(obj)
        for finger,c in touches do
            if finger==obj or finger.UserInputType==Enum.UserInputType.MouseButton1 and obj.UserInputType==Enum.UserInputType.MouseMovement then drag(c,obj.Position) end
        end
    end)
    connect(Input.InputEnded,function(obj)
        if touches[obj]==wheel then steer=0 end
        touches[obj]=nil
    end)
    connect(Input.WindowFocusReleased,function() table.clear(touches);steer=0 end)
    connect(layer:GetPropertyChangedSignal("AbsoluteSize"),layout)
    reset();layout()
    local function key(a,bkey) return Input:IsKeyDown(a) or Input:IsKeyDown(bkey) end
    connect(Run.RenderStepped,function(dt)
        if not finish then
            local up=key(Enum.KeyCode.Up,Enum.KeyCode.W)
            local down=key(Enum.KeyCode.Down,Enum.KeyCode.S)
            throttle=math.clamp(throttle+((up and 1 or 0)-(down and 1 or 0))*dt,0,1)
            local left=key(Enum.KeyCode.Left,Enum.KeyCode.A)
            local right=key(Enum.KeyCode.Right,Enum.KeyCode.D)
            local turn=left and 1 or right and -1 or steer
            if hold>0 then hold=math.max(0,hold-dt)
            else
                accumulator+=math.min(dt,.25)
                while accumulator>=Step.DT do
                    elapsed+=Step.DT;accumulator-=Step.DT
                    Step.advance(b,Input:IsKeyDown(Enum.KeyCode.Space) and 1 or throttle,turn,elapsed,Step.DT)
                    if b.out or (b.started and elapsed-b.startTime>=2.2) or (not b.started and elapsed>8) then
                        finish=b.out=="F" and string.format("フライング　%.2f 秒早い",-b.startTime)
                            or b.out and "沈没" or b.started and string.format("スタート　ST %.2f 秒",b.startTime) or "出遅れ"
                        break
                    end
                end
            end
        end
        rotor.Rotation=(elapsed%12)*30
        hint.Text=b.started and "スタートライン通過" or elapsed<launch-.35 and "助走のタイミングを待つ" or elapsed<launch+.35 and "今、全開" or "ラインを目指す"
        hint.TextColor3=math.abs(elapsed-launch)<.35 and Color3.fromRGB(110,255,150) or Ui.WHITE
        result.Visible=finish~=nil;result.Text=finish or ""
        gas.Text=string.format("開度\n%d%%",math.floor(throttle*100+.5))
        clock.Text=hold>0 and "大時計　準備" or string.format("大時計　%+.2f",elapsed)
        local pos=Vector3.new(b.x*3.5,0,b.z*3.5)
        local dir=Vector3.new(math.cos(b.h),0,math.sin(b.h))
        model:PivotTo(CFrame.lookAt(pos,pos+dir))
        local cam=workspace.CurrentCamera
        cam.CameraType=Enum.CameraType.Scriptable
        cam.CFrame=CFrame.lookAt(pos-dir*20+Vector3.new(0,9,0),pos+dir*12)
        cam.Focus=CFrame.new(pos)
    end)
end
return Practice
