local RS=game:GetService("ReplicatedStorage")
local Assets=RS:WaitForChild("VisualAssets")
local Visuals={}
function Visuals.boat(parent,number)
    local source=Assets:FindFirstChild("Boat")
    if not source or #source:GetDescendants()==0 then return nil end
    local model=source:Clone()
    model:SetAttribute("Detailed",true)
    -- 艇番(1〜6)で色は変えない。レースでも、倉庫で見た自分の着せ替えのままの見た目で走る(色は Outfit が塗る)
    local _=number
    -- 部品どうしの重なりを直す(元の模型の置き場所のずれ。前は -Z):
    --   ・風よけのガラスを少し前へ、ハンドルを少し後ろへ(ハンドルとレーサーの手がガラスに食い込まないように)
    --   ・艇番の板を少し上へ(艇首の甲板の山に板の真ん中が埋まり、暗い塗装で白い切れ端に見えていた)
    for name,move in pairs({Glass=Vector3.new(0,0,-.15),Wheel=Vector3.new(0,0,.08),Plates=Vector3.new(0,.04,0)}) do
        local group=model:FindFirstChild(name)
        if group then group:PivotTo(group:GetPivot()+move) end
    end
    for _,name in ipairs({"Motor","Wheel","RacerUpper"}) do
        local group=model:FindFirstChild(name)
        if group then group:SetAttribute("RestOrigin",group:GetPivot().Position) end
    end
    model.Parent=parent
    return model
end
function Visuals.venue(parent)
    local source=Assets:FindFirstChild("Venue")
    if not source or #source:GetDescendants()==0 then return nil end
    local model=source:Clone()
    model.Parent=parent
    return model
end
function Visuals.pose(model,steer,roll)
    if not model:GetAttribute("Detailed") then return end
    local root=model:GetPivot()
    for name,rotation in pairs({Motor=CFrame.Angles(0,-steer*.4,0),
        Wheel=CFrame.Angles(0,0,-steer*.7),RacerUpper=CFrame.Angles(0,0,roll*.5)}) do
        local group=model:FindFirstChild(name)
        if group then
            local origin=group:GetAttribute("RestOrigin")
            if origin then group:PivotTo(root*CFrame.new(origin)*rotation) end
        end
    end
end
return Visuals
