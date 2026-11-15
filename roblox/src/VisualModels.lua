local RS=game:GetService("ReplicatedStorage")
local Assets=RS:WaitForChild("VisualAssets")
local Visuals={}
function Visuals.boat(parent,number)
    local source=Assets:FindFirstChild("Boat")
    if not source or #source:GetDescendants()==0 then return nil end
    local model=source:Clone()
    model:SetAttribute("Detailed",true)
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA("BasePart") and number then
            local material=p.Name:match("__(.-)__")
            if material=="BoatColor" or material=="Suit" or material=="NumberPlate" then
                local colors={0xf2f2f0,0x16161a,0xd91e2e,0x1b50d4,0xf3d21b,0x18a24c}
                local c=colors[number]
                p.Color=Color3.fromRGB(bit32.rshift(c,16),bit32.band(bit32.rshift(c,8),255),bit32.band(c,255))
            end
        end
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
