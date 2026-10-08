--!strict

local stateKey = "panelRequest"

local function requestPanel(panelId: string): ()
    noctalia.state.set(stateKey, "dmich/air-alert:" .. panelId)
end

return { stateKey = stateKey, requestPanel = requestPanel }
