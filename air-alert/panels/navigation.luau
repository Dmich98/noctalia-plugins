--!strict

export type Request = { owner: string, panelId: string }

local stateKey = "panelRequest"
local ownerKey = "panelOwner"

local function open(panelId: string): ()
    local fullId = "dmich/air-alert:" .. panelId
    local owner: string? = noctalia.state.get(ownerKey)
    if owner then
        noctalia.state.set(stateKey, { owner = owner, panelId = fullId })
    else
        noctalia.togglePanel(fullId)
    end
end

return { stateKey = stateKey, ownerKey = ownerKey, open = open }
