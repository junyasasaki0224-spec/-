-- Rebuild a prediction from an authoritative state and inputs not yet applied.
local function reconcile(state, pendingSteps, acknowledged, stepBoat)
    local predicted = {x=state[1],z=state[2],h=state[3],vx=state[4],vz=state[5],w=state[6],throttle=state[7],steer=state[8]}
    predicted.accF,predicted.topF,predicted.gripSet,predicted.gripF = state[9],state[10],state[11],state[12]
    predicted.thrustF,predicted.windX,predicted.windZ,predicted.motor = state[13],state[14],state[15],state[16]
    local remaining = {}
    for _, entry in ipairs(pendingSteps) do
        if entry.sequence > acknowledged then
            stepBoat(predicted,entry.throttle,entry.steer,1/120)
            remaining[#remaining+1] = entry
        end
    end
    return predicted,remaining
end
return reconcile
