local Meta=require(game:GetService("ReplicatedStorage"):WaitForChild("Meta"))
local function color(n) return Color3.fromRGB(bit32.rshift(n,16),bit32.band(bit32.rshift(n,8),255),bit32.band(n,255)) end
return function(model,skinId,helmetId)
    local skin,helmet=Meta.item(skinId),Meta.item(helmetId)
    if skin then
        for name,key in pairs({Hull="hull",Bow="trim",Deck="deck",Motor="cowl"}) do
            local part=model:FindFirstChild(name)
            if part then part.Color=color(skin[key]) end
        end
    end
    if helmet then
        local part=model:FindFirstChild("Helmet")
        if part then
            part.Color=color(helmet.base)
            local stripe=model:FindFirstChild("HelmetStripe")
            if not stripe then
                stripe=Instance.new("Part")
                stripe.Name="HelmetStripe";stripe.Anchored=true;stripe.CanCollide=false
                stripe.Size=Vector3.new(part.Size.X*.19,part.Size.Y*1.01,part.Size.Z*.92)
                stripe.CFrame=part.CFrame;stripe.Parent=model
            end
            stripe.Color=color(helmet.stripe)
        end
    end
end
