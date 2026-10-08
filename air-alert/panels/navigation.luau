--!strict

local stateKey = "panelRequest"
local ownerKey = "panelOwner"
export type PanelRequest = { owner: string, panelId: string }

local function requestPanel(panelId: string): ()
    local fullId = "dmich/air-alert:" .. panelId
    local owner: string? = noctalia.state.get(ownerKey)
    if owner then
        noctalia.state.set(stateKey, { owner = owner, panelId = fullId })
    else
        -- A panel opened through IPC can work without a widget anchor.
        noctalia.togglePanel(fullId)
    end
end

return { stateKey = stateKey, ownerKey = ownerKey, requestPanel = requestPanel }
